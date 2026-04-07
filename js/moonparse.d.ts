/**
 * MoonParse TypeScript Bindings
 *
 * Tree-Sitter Web API compatible interface for MoonParse WASM module.
 * Requires: Chrome >= 117 / Node.js >= 22 / Deno >= 1.37 (for wasm-gc + use-js-builtin-string).
 *
 * Quick start:
 * ```ts
 * import { loadMoonParse } from "./moonparse.js";
 * const mp = await loadMoonParse("path/to/moonparse.wasm");
 * const parser = mp.createParser(`
 *   start expr
 *   rule expr: /[0-9]+/ (("+" | "-") /[0-9]+/)*
 * `);
 * const tree = parser.parse("1 + 2 + 3");
 * console.log(tree.sexp());
 * parser.free();
 * ```
 */

// ── Primitive types ──────────────────────────────────────────────

/** Opaque integer handle to a parser object stored in WASM. */
export type ParserHandle = number;

/** Opaque integer handle to a parsed syntax tree stored in WASM. */
export type TreeHandle = number;

// ── CST node shape (matches cst_to_json output) ─────────────────

/**
 * A node in the Concrete Syntax Tree produced by MoonParse.
 * Mirrors the JSON structure emitted by `tree_to_json` / `wasm_parse`.
 */
export interface CstNode {
  /** Node type name (rule name for inner nodes, token name for leaves). */
  type: string;
  /** Whether the node is a named (non-anonymous) node. */
  named: boolean;
  /** Whether the node represents a syntax error. */
  error: boolean;
  /** Whether the node was inserted by error recovery (missing token). */
  missing: boolean;
  /** Byte offset of the first character (inclusive). */
  start_byte: number;
  /** Byte offset past the last character (exclusive). */
  end_byte: number;
  /** 0-based line of the first character. */
  start_row: number;
  /** 0-based column of the first character. */
  start_col: number;
  /** 0-based line past the last character. */
  end_row: number;
  /** 0-based column past the last character. */
  end_col: number;
  /** Field name for each child (parallel array; null where no field is assigned). */
  field_names: (string | null)[];
  /** Child nodes (all children, named and anonymous). */
  children: CstNode[];
}

// ── InputEdit ────────────────────────────────────────────────────

/**
 * Describes a single text edit for incremental re-parsing.
 * All byte offsets are UTF-16 code unit counts (matching JS string indices).
 */
export interface InputEdit {
  /** Start byte of the edited region in the original source. */
  start_byte: number;
  /** End byte of the edited region in the original source (exclusive). */
  old_end_byte: number;
  /** End byte of the replacement text in the new source (exclusive). */
  new_end_byte: number;
  /** Row/col of start_byte in the original source. */
  start_row: number;
  start_col: number;
  /** Row/col of old_end_byte in the original source. */
  old_end_row: number;
  old_end_col: number;
  /** Row/col of new_end_byte in the new source. */
  new_end_row: number;
  new_end_col: number;
}

// ── Query capture ────────────────────────────────────────────────

/** A single named capture produced by a structured query match. */
export interface CaptureResult {
  /** Index of the match this capture belongs to (multiple captures per match). */
  match_id: number;
  /** Capture name (the `@name` part of the query pattern). */
  capture: string;
  /** Start byte offset in the source. */
  start: number;
  /** End byte offset in the source (exclusive). */
  end: number;
  start_row: number;
  start_col: number;
  end_row: number;
  end_col: number;
  /** Matched source text for this capture. */
  text: string;
}

// ── ParseTree ────────────────────────────────────────────────────

/**
 * A parsed syntax tree. Wraps an internal WASM tree handle.
 * **Must** be freed via `.free()` when no longer needed to avoid memory leaks.
 */
export declare class ParseTree {
  /** Raw tree handle (opaque; use the methods instead). */
  readonly handle: TreeHandle;

  /**
   * Full tree JSON representation (lazily cached).
   * Mirrors the output of `tree_to_json`.
   */
  readonly json: string;

  /** Root node of the CST. */
  readonly root: CstNode;

  /**
   * Tree-Sitter compatible S-expression string.
   * Example: `(expression (number) "+" (number))`
   */
  sexp(): string;

  /**
   * Quick error check.
   * Returns `"ok"` if the tree has no errors, `"error:row:col"` otherwise, `"invalid"` if the handle is stale.
   */
  errorSummary(): string;

  /**
   * Run a structured query against this tree and return all captures.
   * Equivalent to `language.query(pattern).matches(root)` in web-tree-sitter.
   *
   * @param pattern - S-expression query pattern, e.g. `"(identifier) @name"`
   */
  query(pattern: string): CaptureResult[];

  /** Free the underlying WASM handle. The object must not be used after this call. */
  free(): void;
}

// ── MoonParser ───────────────────────────────────────────────────

/**
 * A MoonParse parser instance backed by a compiled grammar.
 * **Must** be freed via `.free()` when no longer needed.
 */
export declare class MoonParser {
  /** Raw parser handle (opaque). */
  readonly handle: ParserHandle;

  /**
   * Parse a full source string from scratch.
   * Returns a {@link ParseTree} which must be freed when done.
   */
  parse(source: string): ParseTree;

  /**
   * Incrementally re-parse after a single text edit.
   * Much faster than `parse()` for small edits on large files.
   *
   * @param source  - Full new source text (after the edit).
   * @param oldTree - The {@link ParseTree} returned by the previous `parse()` call.
   * @param edit    - Description of the edit (byte offsets + row/col).
   */
  parseIncremental(source: string, oldTree: ParseTree, edit: InputEdit): ParseTree;

  /**
   * The original Grammar DSL string used to create this parser.
   * Empty string if the parser was restored from a pre-compiled table JSON.
   */
  readonly dsl: string;

  /**
   * Pre-compiled parse table as a JSON string.
   * Can be passed to {@link MoonParseInstance.createParserFromJson} for faster startup.
   */
  tableJson(): string;

  /**
   * Conflict / diagnostic reports produced during grammar compilation.
   * Returns a JSON array string `[{severity, state, terminal}, ...]`.
   */
  diagnosticsJson(): string;

  /** Free the underlying WASM handle. */
  free(): void;
}

// ── Top-level module API ─────────────────────────────────────────

/** The resolved MoonParse module API returned by {@link loadMoonParse}. */
export interface MoonParseInstance {
  /**
   * Compile a Grammar DSL string into a parser.
   * Throws if the DSL has parse errors or the grammar is invalid.
   *
   * @param dsl - Grammar DSL string (see MoonParse grammar format).
   */
  createParser(dsl: string): MoonParser;

  /**
   * Restore a parser from a pre-compiled JSON table (fast path).
   * Throws if the JSON is invalid.
   *
   * @param tableJson - JSON string previously obtained from `parser.tableJson()`.
   */
  createParserFromJson(tableJson: string): MoonParser;

  /**
   * Validate a grammar DSL file using MoonParse's meta-grammar.
   * Returns `true` if the DSL is syntactically valid.
   */
  validateDsl(dsl: string): boolean;

  /** MoonParse runtime version string (e.g. `"0.1.0"`). */
  version(): string;
}

// ── Entry point ──────────────────────────────────────────────────

/**
 * Load and initialize the MoonParse WASM module.
 *
 * **Browser**: pass the URL to `moonparse.wasm`:
 * ```ts
 * const mp = await loadMoonParse("/static/moonparse.wasm");
 * ```
 *
 * **Node.js**: pass a `file://` URL or an absolute path:
 * ```ts
 * import { fileURLToPath } from "url";
 * import { resolve } from "path";
 * const wasmPath = resolve(__dirname, "moonparse.wasm");
 * const mp = await loadMoonParse(wasmPath);
 * ```
 *
 * @param wasmUrl - Optional path/URL to the WASM file.
 *                  Defaults to `"./moonparse.wasm"` (resolved relative to the script).
 */
export declare function loadMoonParse(wasmUrl?: string): Promise<MoonParseInstance>;
