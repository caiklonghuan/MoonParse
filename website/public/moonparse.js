
const isBrowser =
  typeof globalThis.window !== "undefined" &&
  typeof globalThis.document !== "undefined";

const isNode =
  typeof globalThis.process !== "undefined" &&
  typeof globalThis.process.versions?.node === "string";

const JS_STRING_BUILTINS_OPTS = { builtins: ['js-string'] };

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
    this.handle = handle;
    this._wasm = wasm;
  }

  get dsl() {
    return this._wasm.parser_get_dsl(this.handle) ?? "";
  }

  parse(source) {
    const tid = this._wasm.parse_full(this.handle, source);
    if (tid < 0) {
      throw new Error("[MoonParse] parse() failed — check the grammar or source");
    }
    return new ParseTree(tid, this._wasm);
  }

  parseIncremental(source, oldTree, edit) {
    const tid = this._wasm.parse_incremental(
      this.handle,
      oldTree.handle,
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
      throw new Error(
        "[MoonParse] parseIncremental() failed — check parser_id, old_tree_id, and edit fields",
      );
    }
    oldTree.handle = -1;
    return new ParseTree(tid, this._wasm);
  }

  tableJson() {
    return this._wasm.parser_table_to_json(this.handle) ?? "";
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
      } catch (_) {}
      throw new Error(`[MoonParse] compileQuery() failed: ${msg || "syntax error in query pattern"}`);
    }
  }
  exec(tree) {
    const json = this._wasm.query_exec(this.handle, tree.handle) ?? "[]";
    return JSON.parse(json);
  }

  free() {
    if (this.handle >= 0) {
      this._wasm.query_free(this.handle);
      this.handle = -1;
    }
  }
}

export async function loadMoonParse(wasmUrl = "./moonparse.wasm") {
  const mod = await loadWasmModule(wasmUrl);

  const importObj = {
    "_": new Proxy({}, { get(_, name) { return name; } }),
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
    createParser(dsl) {
      const pid = wasm.parser_create_from_dsl(dsl);
      if (pid < 0) {
        throw new Error(
          "[MoonParse] createParser() failed — grammar DSL parse error"
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

    compileQuery(pattern) {
      return new MoonQuery(pattern, wasm);
    },

    highlightNames() {
      const json = wasm.highlight_names_json() ?? "[]";
      return JSON.parse(json);
    },

    validateGrammarDsl(dsl) {
      const json = wasm.grammar_validate_dsl?.(dsl) ?? '[]';
      try { return JSON.parse(json); } catch { return []; }
    },

    setParseConfig(cfg) {
      wasm.parse_config_set?.(
        cfg.error_cost_per_skipped_tree ?? -1,
        cfg.error_cost_per_skipped_char ?? -1,
        cfg.error_cost_per_skipped_line ?? -1,
        cfg.error_cost_per_missing_tree ?? -1,
        cfg.error_cost_per_recovery     ?? -1,
        cfg.max_version_count           ?? -1,
        cfg.max_version_count_overflow  ?? -1,
      );
    },

    resetParseConfig() {
      wasm.parse_config_reset?.();
    },

    builtinGrammars() {
      const json = wasm.builtin_grammars_json?.() ?? '{}';
      try { return JSON.parse(json); } catch { return {}; }
    },

    version() {
      return wasm.moonparse_version() ?? "0.0.0";
    },
  };
}

export { ParseTree, MoonParser, TreeCursor, MoonQuery };
