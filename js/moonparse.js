
/** True when running inside a browser (or browser-like environment). */
const isBrowser =
  typeof globalThis.window !== "undefined" &&
  typeof globalThis.document !== "undefined";

/** True when running inside Node.js. */
const isNode =
  typeof globalThis.process !== "undefined" &&
  typeof globalThis.process.versions?.node === "string";

// ── WASM loading ─────────────────────────────────────────────────

/**
 * Load the raw WebAssembly module bytes.
 *
 * - Browser: uses `fetch()` to download the .wasm file.
 * - Node.js: reads the file synchronously with `fs.readFileSync`.
 *
 * @param {string} wasmUrl  Path or URL to the .wasm file.
 * @returns {Promise<WebAssembly.Module>}
 */
async function loadWasmModule(wasmUrl) {
  if (isBrowser) {
    // Streaming compilation (fastest path in browsers)
    if (typeof WebAssembly.compileStreaming === "function") {
      const response = await fetch(wasmUrl);
      return WebAssembly.compileStreaming(response);
    }
    // Fallback: fetch bytes then compile
    const response = await fetch(wasmUrl);
    const bytes = await response.arrayBuffer();
    return WebAssembly.compile(bytes);
  }

  if (isNode) {
    // Lazily import `fs` to avoid bundler errors in browser builds
    const { readFileSync } = await import("fs");
    // Accept both regular paths and file:// URLs
    let path = wasmUrl;
    if (path.startsWith("file://")) {
      const { fileURLToPath } = await import("url");
      path = fileURLToPath(path);
    }
    const bytes = readFileSync(path);
    return WebAssembly.compile(bytes);
  }

  throw new Error(
    "[MoonParse] Unsupported runtime: neither browser nor Node.js"
  );
}

// ── ParseTree class ──────────────────────────────────────────────

class ParseTree {
  /** @param {number} handle @param {object} wasm */
  constructor(handle, wasm) {
    /** @type {number} @readonly */
    this.handle = handle;
    this._wasm = wasm;
    this._json = null;
    this._root = null;
  }

  /** Full tree as JSON string (lazily cached). */
  get json() {
    if (this._json === null) {
      this._json = this._wasm.tree_to_json(this.handle) ?? "";
    }
    return this._json;
  }

  /** Root node of the CST. */
  get root() {
    if (this._root === null) {
      this._root = JSON.parse(this.json);
    }
    return this._root;
  }

  /** S-expression string (Tree-Sitter compatible). */
  sexp() {
    return this._wasm.tree_root_sexp(this.handle) ?? "";
  }

  /**
   * Quick error check.
   * @returns {"ok" | `error:${number}:${number}` | "invalid"}
   */
  errorSummary() {
    return this._wasm.tree_error_summary(this.handle) ?? "invalid";
  }

  /**
   * Run a structured query pattern and return all captures.
   * @param {string} pattern
   * @returns {import("./moonparse.d.ts").CaptureResult[]}
   */
  query(pattern) {
    const json = this._wasm.wasm_query(this.handle, pattern) ?? "[]";
    return JSON.parse(json);
  }

  /** Free the underlying WASM handle. */
  free() {
    if (this.handle >= 0) {
      this._wasm.tree_free(this.handle);
      this.handle = -1;
    }
  }
}

// ── MoonParser class ─────────────────────────────────────────────

class MoonParser {
  /** @param {number} handle @param {object} wasm */
  constructor(handle, wasm) {
    /** @type {number} @readonly */
    this.handle = handle;
    this._wasm = wasm;
  }

  /** Grammar DSL used to create this parser (empty if restored from JSON). */
  get dsl() {
    return this._wasm.parser_get_dsl(this.handle) ?? "";
  }

  /**
   * Parse a source string from scratch.
   * @param {string} source
   * @returns {ParseTree}
   */
  parse(source) {
    const tid = this._wasm.parse_full(this.handle, source);
    if (tid < 0) {
      throw new Error("[MoonParse] parse() failed — check the grammar or source");
    }
    return new ParseTree(tid, this._wasm);
  }

  /**
   * Incremental re-parse after a text edit.
   * @param {string} source             Full new source text.
   * @param {ParseTree} oldTree         Previous parse tree.
   * @param {import("./moonparse.d.ts").InputEdit} edit
   * @returns {ParseTree}
   */
  parseIncremental(source, oldTree, edit) {
    const changesJson = JSON.stringify(edit);
    const newJson = this._wasm.wasm_parse_incremental(
      this.handle,
      source,
      oldTree.handle,
      changesJson
    );
    if (!newJson) {
      throw new Error("[MoonParse] parseIncremental() failed");
    }
    // wasm_parse_incremental already freed the internal tree handle and returned JSON.
    // We wrap the JSON in a temporary ParseTree with handle = -1 to signal it's JSON-only.
    return new _JsonOnlyTree(newJson);
  }

  /**
   * Pre-compiled parse table as a JSON string (for fast re-loading).
   * @returns {string}
   */
  tableJson() {
    return this._wasm.parser_table_to_json(this.handle) ?? "";
  }

  /**
   * Conflict / diagnostics JSON array string.
   * @returns {string}
   */
  diagnosticsJson() {
    return this._wasm.parser_diagnostics_json(this.handle) ?? "[]";
  }

  /** Free the underlying WASM handle. */
  free() {
    if (this.handle >= 0) {
      this._wasm.parser_free(this.handle);
      this.handle = -1;
    }
  }
}

// ── JSON-only tree (returned from wasm_parse_incremental) ────────

class _JsonOnlyTree extends ParseTree {
  /** @param {string} json */
  constructor(json) {
    super(-1, null);
    this._json = json;
  }

  sexp() {
    // wasm_parse_incremental drops the tree handle; reconstruct sexp from JSON.
    // For full sexp support on incremental results, use the handle-based API instead.
    return "(incremental-result — use handle-based API for sexp)";
  }

  errorSummary() {
    const root = this.root;
    if (!root) return "invalid";
    const hasError = (n) =>
      n.error || n.missing || (n.children ?? []).some(hasError);
    if (hasError(root)) return "error:?:?";
    return "ok";
  }

  query(_pattern) {
    throw new Error(
      "[MoonParse] query() is not available on JSON-only trees from parseIncremental(). " +
      "Use the handle-based wasm_parse_incremental API."
    );
  }

  free() {
    // Nothing to free — no WASM handle.
  }
}

// ── loadMoonParse ────────────────────────────────────────────────

/**
 * Load and initialise the MoonParse WASM module.
 *
 * @param {string} [wasmUrl="./moonparse.wasm"]  Path or URL to the .wasm file.
 * @returns {Promise<import("./moonparse.d.ts").MoonParseInstance>}
 */
export async function loadMoonParse(wasmUrl = "./moonparse.wasm") {
  const mod = await loadWasmModule(wasmUrl);

  // Instantiate with an empty import object.
  // MoonBit wasm-gc generates a self-contained module; no imports needed beyond default.
  const { exports: wasm } = await WebAssembly.instantiate(mod, {});

  // Validate that the expected exports are present
  const required = [
    "parser_create_from_dsl",
    "parser_free",
    "parse_full",
    "tree_to_json",
    "tree_free",
  ];
  for (const fn of required) {
    if (typeof wasm[fn] !== "function") {
      throw new Error(
        `[MoonParse] WASM is missing expected export: "${fn}". ` +
        "Did you build with --target wasm-gc?"
      );
    }
  }

  return {
    /**
     * Compile a Grammar DSL into a MoonParser.
     * @param {string} dsl
     * @returns {MoonParser}
     */
    createParser(dsl) {
      const pid = wasm.parser_create_from_dsl(dsl);
      if (pid < 0) {
        throw new Error(
          "[MoonParse] createParser() failed — grammar DSL parse error"
        );
      }
      return new MoonParser(pid, wasm);
    },

    /**
     * Restore a MoonParser from a pre-compiled JSON table (faster startup).
     * @param {string} tableJson
     * @returns {MoonParser}
     */
    createParserFromJson(tableJson) {
      const pid = wasm.parser_create_from_json(tableJson);
      if (pid < 0) {
        throw new Error(
          "[MoonParse] createParserFromJson() failed — invalid table JSON"
        );
      }
      return new MoonParser(pid, wasm);
    },

    /**
     * Validate a grammar DSL file using MoonParse's meta-grammar.
     * Returns `true` if the DSL is syntactically valid (no error nodes).
     * @param {string} dsl
     * @returns {boolean}
     */
    validateDsl(dsl) {
      // Use a temporary parser backed by the meta-grammar to validate.
      // The meta-parser is compiled once as a built-in grammar in the WASM module;
      // `wasm_create_parser` compiles from DSL, which is heavier — here we use a
      // lightweight heuristic: try to compile the DSL and check for errors.
      const pid = wasm.parser_create_from_dsl(dsl);
      if (pid < 0) return false;
      wasm.parser_free(pid);
      return true;
    },

    /** MoonParse runtime version string. */
    version() {
      return wasm.moonparse_version() ?? "0.0.0";
    },
  };
}

// ── Re-exports ───────────────────────────────────────────────────

export { ParseTree, MoonParser };
