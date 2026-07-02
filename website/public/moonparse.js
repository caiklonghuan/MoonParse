
const isBrowser =
  typeof globalThis.window !== "undefined" &&
  typeof globalThis.document !== "undefined";

const isNode =
  typeof globalThis.process !== "undefined" &&
  typeof globalThis.process.versions?.node === "string";

const JS_STRING_BUILTINS_OPTS = { builtins: ['js-string'] };

function uint8ArrayToBase64(bytes) {
  if (typeof Buffer !== 'undefined') {
    return Buffer.from(bytes).toString('base64');
  }
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

function base64ToUint8Array(base64) {
  if (typeof Buffer !== 'undefined') {
    return new Uint8Array(Buffer.from(base64, 'base64'));
  }
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

async function loadWasmModule(wasmUrl) {
  if (isBrowser) {
    if (typeof WebAssembly.compileStreaming === "function") {
      const response = await fetch(wasmUrl);
      return WebAssembly.compileStreaming(response, JS_STRING_BUILTINS_OPTS);
    }
    const response = await fetch(wasmUrl);
    const bytes = await response.arrayBuffer();
    return WebAssembly.compile(bytes, JS_STRING_BUILTINS_OPTS);
  }

  if (isNode) {
    const { readFileSync } = await import("fs");
    let path = wasmUrl;
    if (path.startsWith("file://")) {
      const { fileURLToPath } = await import("url");
      path = fileURLToPath(path);
    }
    const bytes = readFileSync(path);
    return WebAssembly.compile(bytes, JS_STRING_BUILTINS_OPTS);
  }

  throw new Error(
    "[MoonParse] Unsupported runtime: neither browser nor Node.js"
  );
}

class ParseTree {
  constructor(handle, wasm) {
    this.handle = handle;
    this._wasm = wasm;
    this._json = null;
    this._root = null;
  }

  get json() {
    if (this._json === null) {
      this._json = this._wasm.tree_to_json(this.handle) ?? "";
    }
    return this._json;
  }

  get root() {
    if (this._root === null) {
      this._root = JSON.parse(this.json);
    }
    return this._root;
  }

  sexp() {
    return this._wasm.tree_root_sexp(this.handle) ?? "";
  }

  text() {
    return this._wasm.tree_to_text?.(this.handle) ?? "";
  }

  prettyText() {
    return this._wasm.tree_to_pretty_text?.(this.handle) ?? "";
  }

  errorSummary() {
    return this._wasm.tree_error_summary(this.handle) ?? "invalid";
  }

  query(pattern) {
    const json = this._wasm.wasm_query(this.handle, pattern) ?? "[]";
    return JSON.parse(json);
  }

  walk() {
    return new TreeCursor(this.handle, this._wasm);
  }

  highlight(hlQuery, locsQuery) {
    let json;
    if (locsQuery != null) {
      json = this._wasm.highlight_exec_with_locals(
        hlQuery.handle,
        locsQuery.handle,
        this.handle,
      );
    } else {
      json = this._wasm.highlight_exec(hlQuery.handle, this.handle);
    }
    return JSON.parse(json ?? "[]");
  }
  free() {
    if (this.handle >= 0) {
      this._wasm.tree_free(this.handle);
      this.handle = -1;
    }
  }
}
class MoonParser {
  constructor(handle, wasm) {
    /** @type {number} @readonly */
    this.handle = handle;
    this._wasm = wasm;
  }

  get dsl() {
    return this._wasm.parser_get_dsl(this.handle) ?? "";
  }

  parse(source) {
    const tid = this._wasm.parse_full(this.handle, source);
    if (tid < 0) {
      const detail = this._wasm.parse_error_last?.() || "check the grammar or source";
      throw new Error(`[MoonParse] parse() failed — ${detail}`);
    }
    return new ParseTree(tid, this._wasm);
  }

  parseIncremental(source, oldTree, edit) {
    const oldHandle = oldTree.handle;
    const tid = this._wasm.parse_incremental(
      this.handle,
      oldHandle,
      source,
      edit.start_byte,
      edit.old_end_byte,
      edit.new_end_byte,
      edit.start_row,
      edit.start_col,
      edit.old_end_row,
      edit.old_end_col,
      edit.new_end_row,
      edit.new_end_col,
    );
    if (tid < 0) {
      const detail = this._wasm.parse_error_last?.() || "check parser_id, old_tree_id, and edit fields";
      throw new Error(`[MoonParse] parseIncremental() failed — ${detail}`);
    }
    this._wasm.tree_free(oldHandle);
    oldTree.handle = -1;
    return new ParseTree(tid, this._wasm);
  }

  tableJson() {
    return this._wasm.parser_table_to_json(this.handle) ?? "";
  }
  tableBytes() {
    const base64 = this._wasm.parser_table_to_base64?.(this.handle) ?? "";
    return base64ToUint8Array(base64);
  }
  diagnosticsJson() {
    return this._wasm.parser_diagnostics_json(this.handle) ?? "[]";
  }
  free() {
    if (this.handle >= 0) {
      this._wasm.parser_free(this.handle);
      this.handle = -1;
    }
  }
}

class TreeCursor {
  constructor(treeHandle, wasm) {
    this._wasm = wasm;
    this.handle = wasm.cursor_new(treeHandle);
    if (this.handle < 0) {
      throw new Error("[MoonParse] TreeCursor: failed to create cursor (invalid tree handle)");
    }
  }

  get nodeType() { return this._wasm.cursor_node_type(this.handle) ?? ""; }
  get nodeText() { return this._wasm.cursor_node_text(this.handle) ?? ""; }
  get nodeField() {
    const f = this._wasm.cursor_node_field(this.handle);
    return f === "" ? null : (f ?? null);
  }
  get isNamed()   { return this._wasm.cursor_node_is_named(this.handle)   !== 0; }
  get isError()   { return this._wasm.cursor_node_is_error(this.handle)   !== 0; }
  get isMissing() { return this._wasm.cursor_node_is_missing(this.handle) !== 0; }
  get isExtra()   { return this._wasm.cursor_node_extra(this.handle)       !== 0; }
  get hasChanges() { return this._wasm.cursor_node_has_changes?.(this.handle) !== 0; }
  get isKeyword()  { return this._wasm.cursor_node_is_keyword?.(this.handle)  !== 0; }
  get childCount()      { return this._wasm.cursor_node_child_count(this.handle); }
  get namedChildCount() { return this._wasm.cursor_node_named_child_count(this.handle); }
  get startByte() { return this._wasm.cursor_node_start_byte(this.handle); }
  get endByte()   { return this._wasm.cursor_node_end_byte(this.handle); }
  get startRow()  { return this._wasm.cursor_node_start_row(this.handle); }
  get startCol()  { return this._wasm.cursor_node_start_col(this.handle); }
  get endRow()    { return this._wasm.cursor_node_end_row(this.handle); }
  get endCol()    { return this._wasm.cursor_node_end_col(this.handle); }
  gotoFirstChild()   { return this._wasm.cursor_goto_first_child(this.handle)   !== 0; }
  gotoNextSibling()  { return this._wasm.cursor_goto_next_sibling(this.handle)  !== 0; }
  gotoParent()       { return this._wasm.cursor_goto_parent(this.handle)        !== 0; }
  free() {
    if (this.handle >= 0) {
      this._wasm.cursor_free(this.handle);
      this.handle = -1;
    }
  }
}

class MoonQuery {
  constructor(pattern, wasm) {
    this._wasm = wasm;
    this.handle = wasm.query_compile(pattern);
    if (this.handle < 0) {
      const errJson = wasm.query_compile_error_last?.() ?? "";
      let msg = errJson;
      try {
        const parsed = JSON.parse(errJson);
        msg = parsed.message ?? parsed.error ?? errJson;
      } catch (_) { /* errJson was not JSON; use as-is */ }
      throw new Error(`[MoonParse] compileQuery() failed: ${msg || "syntax error in query pattern"}`);
    }
  }
  exec(tree) {
    const json = this._wasm.query_exec(this.handle, tree.handle) ?? "[]";
    return JSON.parse(json);
  }

  resolveLocals(tree) {
    const json = this._wasm.query_resolve_locals?.(this.handle, tree.handle) ?? "{}";
    return JSON.parse(json);
  }

  resolveBindings(tree) {
    const json = this._wasm.query_resolve_bindings?.(this.handle, tree.handle) ?? "{}";
    return JSON.parse(json);
  }

  free() {
    if (this.handle >= 0) {
      this._wasm.query_free(this.handle);
      this.handle = -1;
    }
  }
}

class MoonLanguage {
  constructor(bundleJson, wasm) {
    this._wasm = wasm;
    this.handle = wasm.bundle_register(bundleJson);
    if (this.handle < 0) {
      throw new Error(`[MoonParse] loadBundle() failed: ${wasm.bundle_error_last?.() || "invalid LanguageBundle"}`);
    }
    try {
      this.bundle = JSON.parse(bundleJson);
      this.id = this.bundle.pack.id;
      this.version = this.bundle.pack.version;
      this.name = this.bundle.pack.name ?? this.id;
      this.extensions = this.bundle.pack.extensions ?? [];
      this.capabilities = {
        ...this.bundle.capabilities,
        folding: this.bundle.capabilities?.folding ?? false,
        modules: this.bundle.capabilities?.modules ?? false,
      };
      const parserId = wasm.bundle_parser_id(this.handle);
      if (parserId < 0) throw new Error("bundle parser is unavailable");
      this.parser = new MoonParser(parserId, wasm);
      this.highlightsQuery = this.bundle.queries?.highlights ? new MoonQuery(this.bundle.queries.highlights, wasm) : null;
      this.localsQuery = this.bundle.queries?.locals ? new MoonQuery(this.bundle.queries.locals, wasm) : null;
      this.bindingsQuery = this.bundle.queries?.bindings ? new MoonQuery(this.bundle.queries.bindings, wasm) : null;
      this.foldingQuery = this.bundle.queries?.folding ? new MoonQuery(this.bundle.queries.folding, wasm) : null;
    } catch (error) {
      this.highlightsQuery?.free();
      this.localsQuery?.free();
      this.bindingsQuery?.free();
      this.foldingQuery?.free();
      wasm.bundle_free(this.handle);
      if (this.parser) this.parser.handle = -1;
      this.handle = -1;
      throw error;
    }
  }
  parse(source) { return this.parser.parse(source); }
  highlight(tree) {
    if (!this.highlightsQuery) return [];
    return tree.highlight(this.highlightsQuery, this.localsQuery ?? undefined);
  }
  resolveLocals(tree) {
    return this.localsQuery ? this.localsQuery.resolveLocals(tree) : {};
  }
  resolveBindings(tree) {
    return this.bindingsQuery ? this.bindingsQuery.resolveBindings(tree) : {
      uri: "", scopes: [], definitions: [], references: [], edges: [], diagnostics: [],
    };
  }
  fold(tree) {
    return this.foldingQuery ? this.foldingQuery.exec(tree) : [];
  }
  free() {
    if (this.handle < 0) return;
    this.highlightsQuery?.free();
    this.localsQuery?.free();
    this.bindingsQuery?.free();
    this.foldingQuery?.free();
    this._wasm.bundle_free(this.handle);
    this.parser.handle = -1;
    this.handle = -1;
  }
}

export async function loadMoonParse(wasmUrl = "./moonparse.wasm") {
  const mod = await loadWasmModule(wasmUrl);

  // MoonBit wasm-gc with use-js-builtin-string imports:
  // - "_" module: all 385 imports are string-constant globals; field name IS the string value.
  // - "wasm:js-string": provided natively by V8 via { builtins: ['js-string'] } compile option.
  const importObj = {
    "_": new Proxy({}, { get(_, name) { return name; } }),
    "console": {
      log(value) {
        globalThis.console?.log?.(value);
      },
    },
  };

  const { exports: wasm } = await WebAssembly.instantiate(mod, importObj);
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
    loadBundle(bundleJson) {
      return new MoonLanguage(bundleJson, wasm);
    },
    createParser(dsl) {
      const pid = wasm.parser_create_from_dsl(dsl);
      if (pid < 0) {
        const errMsg = wasm.parser_dsl_error_last?.() ?? "";
        throw new Error(
          `[MoonParse] createParser() failed: ${errMsg || "grammar DSL parse error"}`
        );
      }
      return new MoonParser(pid, wasm);
    },
    createParserFromJson(tableJson, builtinId = null) {
      const pid = builtinId && typeof wasm.parser_create_from_json_with_builtin === "function"
        ? wasm.parser_create_from_json_with_builtin(builtinId, tableJson)
        : wasm.parser_create_from_json(tableJson);
      if (pid < 0) {
        throw new Error(
          "[MoonParse] createParserFromJson() failed — invalid table JSON"
        );
      }
      return new MoonParser(pid, wasm);
    },

    createParserFromBytes(bytes) {
      const base64 = uint8ArrayToBase64(bytes);
      const pid = wasm.parser_create_from_base64(base64);
      if (pid < 0) {
        throw new Error(
          "[MoonParse] createParserFromBytes() failed — invalid binary table"
        );
      }
      return new MoonParser(pid, wasm);
    },

    createParserFromGrammarObject(grammarObj) {
      const json = JSON.stringify(grammarObj);
      const pid = wasm.parser_create_from_grammar_json(json);
      if (pid < 0) {
        const errMsg = wasm.parser_dsl_error_last?.() ?? "";
        throw new Error(
          `[MoonParse] createParserFromGrammarObject() failed: ${errMsg || "invalid grammar JSON"}`
        );
      }
      return new MoonParser(pid, wasm);
    },

    compileQuery(pattern) {
      return new MoonQuery(pattern, wasm);
    },

    highlightNames() {
      const json = wasm.highlight_names_json() ?? "[]";
      return JSON.parse(json);
    },

    validateDsl(dsl) {
      const pid = wasm.parser_create_from_dsl(dsl);
      if (pid < 0) return false;
      wasm.parser_free(pid);
      return true;
    },

    validateDslErrors(dsl) {
      const json = wasm.grammar_validate_dsl?.(dsl) ?? "[]";
      return JSON.parse(json);
    },

    builtinGrammarsJson() {
      return wasm.builtin_grammars_json() ?? "{}";
    },
    builtinBundlesJson() {
      return wasm.builtin_bundles_json() ?? "{}";
    },

    version() {
      return wasm.moonparse_version() ?? "0.0.0";
    },

    parseErrorLast() {
      return wasm.parse_error_last?.() ?? "";
    },

    setParseConfig(config = {}) {
      const d = {
        errorCostPerSkippedTree:     100,
        errorCostPerSkippedChar:     1,
        errorCostPerSkippedLine:     30,
        errorCostPerMissingTree:     110,
        errorCostPerRecovery:        500,
        maxVersionCount:             6,
        maxVersionCountOverflow:     4,
      };
      wasm.parse_config_set(
        config.errorCostPerSkippedTree     ?? -1,
        config.errorCostPerSkippedChar     ?? -1,
        config.errorCostPerSkippedLine     ?? -1,
        config.errorCostPerMissingTree     ?? -1,
        config.errorCostPerRecovery        ?? -1,
        config.maxVersionCount             ?? -1,
        config.maxVersionCountOverflow     ?? -1,
      );
      void d;
    },

    resetParseConfig() {
      wasm.parse_config_reset?.();
    },

    byteOffsetToCharCol(source, line, colBytes) {
      return wasm.tree_byte_offset_to_char_col?.(source, line, colBytes) ?? colBytes;
    },
  };
}

export { ParseTree, MoonParser, TreeCursor, MoonQuery, MoonLanguage };
