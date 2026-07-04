
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

function nowMs() {
  return globalThis.performance?.now?.() ?? Date.now();
}

function roundMs(value) {
  return Math.round(value * 100) / 100;
}

function normalizeModuleQueryResults(results, source) {
  const normalized = [];
  for (const result of results) {
    if (result.capture === "module.export.candidate") {
      const offset = byteOffsetToStringOffset(source, result.start);
      const lineStart = source.lastIndexOf("\n", Math.max(0, offset - 1)) + 1;
      const prefix = source.slice(lineStart, offset);
      if (/\bpub(?:\s*\([^)]*\))?\s+(?:fn|const|type|struct|enum|trait|suberror)\b[^\n]*$/.test(prefix)) {
        normalized.push({ ...result, capture: "module.export" });
      }
      continue;
    }
    if (result.capture === "module.qualified.value" ||
      result.capture === "module.qualified.type") {
      const match = /@([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)/.exec(result.text);
      if (!match) continue;
      const leading = result.text.slice(0, match.index);
      const aliasText = `@${match[1]}`;
      const memberText = match[2];
      const aliasStart = result.start + utf8ByteLength(leading);
      const aliasEnd = aliasStart + utf8ByteLength(aliasText);
      const memberStart = aliasEnd + 1;
      const memberEnd = memberStart + utf8ByteLength(memberText);
      normalized.push(moduleCaptureAt(
        result,
        "module.reference",
        aliasStart,
        aliasEnd,
        aliasText,
        leading,
      ));
      normalized.push(moduleCaptureAt(
        result,
        result.capture === "module.qualified.type"
          ? "module.member.type"
          : "module.member.value",
        memberStart,
        memberEnd,
        memberText,
        leading + aliasText + ".",
      ));
      continue;
    }
    normalized.push(result);
  }
  return normalized;
}

function moduleCaptureAt(base, capture, start, end, text, prefix) {
  const lines = prefix.split("\n");
  const rowDelta = lines.length - 1;
  const col = rowDelta === 0
    ? base.start_col + utf8ByteLength(prefix)
    : utf8ByteLength(lines[lines.length - 1]);
  return {
    match_id: base.match_id,
    capture,
    start,
    end,
    start_row: base.start_row + rowDelta,
    start_col: col,
    end_row: base.start_row + rowDelta,
    end_col: col + utf8ByteLength(text),
    text,
  };
}

function utf8ByteLength(text) {
  return new TextEncoder().encode(text).length;
}

function byteOffsetToStringOffset(text, byteOffset) {
  if (byteOffset <= 0) return 0;
  let bytes = 0;
  let offset = 0;
  for (const char of text) {
    const next = bytes + utf8ByteLength(char);
    if (next > byteOffset) break;
    bytes = next;
    offset += char.length;
  }
  return offset;
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
  constructor(handle, wasm, parserHandle, source = "") {
    this.handle = handle;
    this._wasm = wasm;
    this._parserHandle = parserHandle;
    this._source = source;
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
    return new ParseTree(tid, this._wasm, this.handle, source);
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
    return new ParseTree(tid, this._wasm, this.handle, source);
  }

  parseIncrementalTrace(source, oldTree, edit) {
    const oldHandle = oldTree.handle;
    const incrementalStart = nowMs();
    const raw = this._wasm.parse_incremental_trace(
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
    const incrementalElapsedMs = roundMs(nowMs() - incrementalStart);
    const result = JSON.parse(raw ?? '{"ok":false,"error":"empty trace response","treeId":-1,"trace":null}');
    if (!result.ok || result.treeId < 0) {
      const detail = result.error || this._wasm.parse_error_last?.() || "check parser_id, old_tree_id, and edit fields";
      throw new Error(`[MoonParse] parseIncrementalTrace() failed — ${detail}`);
    }

    const tree = new ParseTree(result.treeId, this._wasm, this.handle, source);
    this._wasm.tree_free(oldHandle);
    oldTree.handle = -1;

    let baselineTree = null;
    let fullBaselineElapsedMs = null;
    let baselineError = null;
    const baselineStart = nowMs();
    try {
      baselineTree = this.parse(source);
    } catch (error) {
      baselineError = error?.message ?? String(error);
    } finally {
      fullBaselineElapsedMs = roundMs(nowMs() - baselineStart);
      try { baselineTree?.free?.(); } catch (_) {}
    }

    const speedup = incrementalElapsedMs > 0 && fullBaselineElapsedMs != null
      ? roundMs(fullBaselineElapsedMs / incrementalElapsedMs)
      : null;
    const trace = {
      ...(result.trace ?? {}),
      incrementalElapsedMs,
      fullBaselineElapsedMs,
      speedup,
    };
    if (baselineError) trace.baselineError = baselineError;
    return { tree, trace };
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
      this.modulesQuery = this.bundle.queries?.modules ? new MoonQuery(this.bundle.queries.modules, wasm) : null;
    } catch (error) {
      this.highlightsQuery?.free();
      this.localsQuery?.free();
      this.bindingsQuery?.free();
      this.foldingQuery?.free();
      this.modulesQuery?.free();
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
  modules(tree) {
    if (this.handle < 0) {
      throw new Error("[MoonParse] modules() failed: Language Bundle has been freed");
    }
    if (!tree || tree.handle < 0) {
      throw new Error("[MoonParse] modules() failed: ParseTree has been freed or is invalid");
    }
    if (tree._wasm !== this._wasm || tree._parserHandle !== this.parser.handle) {
      throw new Error("[MoonParse] modules() failed: tree was not created by this Language Bundle");
    }
    return this.modulesQuery
      ? normalizeModuleQueryResults(this.modulesQuery.exec(tree), tree._source ?? "")
      : [];
  }
  lint(tree, options = {}) {
    if (this.handle < 0) {
      throw new Error("[MoonParse] lint() failed: Language Bundle has been freed");
    }
    if (!tree || tree.handle < 0) {
      throw new Error("[MoonParse] lint() failed: ParseTree has been freed or is invalid");
    }
    if (tree._wasm !== this._wasm || tree._parserHandle !== this.parser.handle) {
      throw new Error("[MoonParse] lint() failed: tree was not created by this Language Bundle");
    }
    let optionsJson;
    try {
      optionsJson = JSON.stringify(options ?? {});
    } catch (error) {
      throw new Error(`[MoonParse] lint() failed: invalid options: ${error?.message ?? String(error)}`);
    }
    const result = JSON.parse(
      this._wasm.bundle_lint(this.handle, tree.handle, optionsJson) ??
        '{"ok":false,"diagnostics":[],"error":"empty lint response"}',
    );
    if (!result.ok) {
      throw new Error(`[MoonParse] lint() failed: ${result.error || "unknown error"}`);
    }
    return result.diagnostics ?? [];
  }
  free() {
    if (this.handle < 0) return;
    this.highlightsQuery?.free();
    this.localsQuery?.free();
    this.bindingsQuery?.free();
    this.foldingQuery?.free();
    this.modulesQuery?.free();
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
    checkPack(files) {
      return JSON.parse(wasm.pack_check(JSON.stringify({ files })));
    },

    buildPack(files) {
      const result = JSON.parse(wasm.pack_build(JSON.stringify({ files })));
      if (!result.ok || result.bundle == null) {
        return {
          ok: false,
          diagnostics: result.diagnostics ?? [],
          bundleJson: null,
          language: null,
        };
      }
      const bundleJson = JSON.stringify(result.bundle);
      const language = new MoonLanguage(bundleJson, wasm);
      return {
        ok: true,
        diagnostics: result.diagnostics ?? [],
        bundleJson,
        language,
      };
    },

    runCorpus(files) {
      return JSON.parse(wasm.pack_test(JSON.stringify({ files })));
    },

    rewriteCorpusSnapshots(request) {
      return JSON.parse(wasm.corpus_rewrite_snapshots(JSON.stringify(request)));
    },

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
