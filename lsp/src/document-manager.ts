import type { Diagnostic } from "vscode-languageserver";
import type { InputEdit } from "../../wasm/moonparse.js";
import type { ServerConfig } from "./config.js";
import {
  utf16ToByteOffset,
  byteOffsetToUtf16,
  byteRangeToUtf16,
  type LspPosition,
  type LspRange,
} from "./position.js";

// 单个文档的完整状态
export interface DocumentEntry {
  uri: string;
  // 文档全文
  text: string;
  // 从 textDocument/didChange 递增的版本号
  version: number;
  // 语法 id，"__dsl__" 表示 Grammar DSL
  languageId: string;
  // MoonParse parser handle，-1 表示尚未创建
  parserHandle: number;
  // 最近一次 parse 的 tree handle，-1 表示未解析
  treeHandle: number;
  // 最近一次推送的诊断
  lastDiagnostics: Diagnostic[];
  // 行首字节偏移，lineOffsets[i] = 第 i 行首字节在全文中的 offset
  lineOffsets: Uint32Array;
  // 待处理的增量编辑（用于增量解析路径）
  pendingEdit?: InputEdit;
  // 编辑前文本快照（增量解析需要）
  previousText?: string;
}

// 句柄释放回调，Phase 2 接入 WASM 时注入
export type FreeTreeFn = (handle: number) => void;
export type FreeParserFn = (handle: number) => void;

// parse 触发回调
export type ParseTrigger = (entry: DocumentEntry) => void;

// 管理所有已打开文档的状态、解析器句柄和行列索引
export class DocumentStore {
  private documents = new Map<string, DocumentEntry>();

  // 每个 URI 的防抖计时器
  private debounceTimers = new Map<string, ReturnType<typeof setTimeout>>();

  // 句柄释放函数，默认空操作，Phase 2 注入
  private freeTreeFn: FreeTreeFn = () => {};
  private freeParserFn: FreeParserFn = () => {};

  constructor(private config: ServerConfig) {}

  // ── 扩展名/语言判断 ──

  // 从 URI 中提取扩展名并查出语法 id
  languageForUri(uri: string): string | undefined {
    const ext = uri.split(".").pop()?.toLowerCase();
    if (!ext) return undefined;
    return this.config.grammarAssociations[ext];
  }

  // 判断该 URI 是否需要被 MoonParse 处理
  isHandled(uri: string): boolean {
    const ext = uri.split(".").pop()?.toLowerCase();
    if (!ext) return false;
    return this.config.enabledExtensions.includes(ext);
  }

  // ── 句柄释放注入（Phase 2） ──

  // 注入释放函数，供 WASM 加载后调用
  setFreeHandlers(freeTree: FreeTreeFn, freeParser: FreeParserFn): void {
    this.freeTreeFn = freeTree;
    this.freeParserFn = freeParser;
  }

  // ── 文档生命周期 ──

  open(uri: string, text: string, version: number): void {
    const languageId = this.languageForUri(uri) ?? "unknown";
    this.documents.set(uri, {
      uri,
      text,
      version,
      languageId,
      parserHandle: -1,
      treeHandle: -1,
      lastDiagnostics: [],
      lineOffsets: buildLineOffsets(text),
    });
  }

  update(uri: string, text: string, version: number): void {
    const entry = this.documents.get(uri);
    if (!entry) return;
    // 释放旧 tree（如果存在）
    this.freeTree(entry);
    entry.text = text;
    entry.version = version;
    entry.lineOffsets = buildLineOffsets(text);
  }

  close(uri: string): void {
    const entry = this.documents.get(uri);
    if (entry) {
      // 取消该 URI 上的待处理防抖
      this.cancelDebounce(uri);
      // 释放 tree 和 parser 句柄
      this.freeTree(entry);
      this.freeParser(entry);
      this.documents.delete(uri);
    }
  }

  get(uri: string): DocumentEntry | undefined {
    return this.documents.get(uri);
  }

  // 统计某 languageId 的打开文档数（排除 excludeUri）
  countByLanguage(languageId: string, excludeUri?: string): number {
    let c = 0;
    for (const [, entry] of this.documents) {
      if (entry.languageId === languageId && entry.uri !== excludeUri) {
        c++;
      }
    }
    return c;
  }

  // 当前打开文档数
  get count(): number {
    return this.documents.size;
  }

  entries(): IterableIterator<[string, DocumentEntry]> {
    return this.documents.entries();
  }

  // ── 句柄管理（Phase 2 接入 WASM 时使用） ──

  setParserHandle(uri: string, handle: number): void {
    const entry = this.documents.get(uri);
    if (entry) entry.parserHandle = handle;
  }

  setTreeHandle(uri: string, handle: number): void {
    const entry = this.documents.get(uri);
    if (entry) {
      // 新 tree 写入前先释放旧的，防止泄漏
      this.freeTree(entry);
      entry.treeHandle = handle;
    }
  }

  setDiagnostics(uri: string, diagnostics: Diagnostic[]): void {
    const entry = this.documents.get(uri);
    if (entry) entry.lastDiagnostics = diagnostics;
  }

  // ── 防抖解析 ──

  // 安排一次防抖解析。连续调用时取消前一次，只保留最后一次。
  scheduleParse(uri: string, onTrigger: ParseTrigger): void {
    this.cancelDebounce(uri);

    const timer = setTimeout(() => {
      this.debounceTimers.delete(uri);
      const entry = this.documents.get(uri);
      if (entry) {
        onTrigger(entry);
      }
    }, this.config.debounceMs);

    this.debounceTimers.set(uri, timer);
  }

  // 取消某 URI 的待处理解析
  cancelDebounce(uri: string): void {
    const existing = this.debounceTimers.get(uri);
    if (existing) {
      clearTimeout(existing);
      this.debounceTimers.delete(uri);
    }
  }

  // ── 位置转换 ──

  // LSP (行号, 列号) → 全文字节偏移（MoonParse 使用）
  byteOffset(entry: DocumentEntry, line: number, character: number): number {
    return utf16ToByteOffset(entry.text, entry.lineOffsets, line, character);
  }

  // MoonParse 字节偏移 → LSP (line, character)
  byteToPosition(entry: DocumentEntry, byteOffset: number): LspPosition {
    return byteOffsetToUtf16(entry.text, entry.lineOffsets, byteOffset);
  }

  // MoonParse 字节范围 → LSP Range
  byteRangeToLsp(entry: DocumentEntry, startByte: number, endByte: number): LspRange {
    return byteRangeToUtf16(entry.text, entry.lineOffsets, startByte, endByte);
  }

  // ── 配置热更新 ──

  updateConfig(config: ServerConfig): void {
    this.config = config;
  }

  dispose(): void {
    for (const [, entry] of this.documents) {
      this.cancelDebounce(entry.uri);
      this.freeTree(entry);
      this.freeParser(entry);
    }
    this.documents.clear();
  }

  // ── 内部句柄释放 ──

  private freeTree(entry: DocumentEntry): void {
    if (entry.treeHandle >= 0) {
      this.freeTreeFn(entry.treeHandle);
      entry.treeHandle = -1;
    }
  }

  private freeParser(entry: DocumentEntry): void {
    if (entry.parserHandle >= 0) {
      this.freeParserFn(entry.parserHandle);
      entry.parserHandle = -1;
    }
  }
}

// ── 行索引构建 ──

function buildLineOffsets(text: string): Uint32Array {
  const offsets: number[] = [0];
  for (let i = 0; i < text.length; i++) {
    if (text[i] === "\n") {
      offsets.push(i + 1);
    }
  }
  return new Uint32Array(offsets);
}
