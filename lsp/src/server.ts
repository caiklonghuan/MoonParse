import {
  createConnection,
  ProposedFeatures,
  type InitializeParams,
  type InitializeResult,
  type Diagnostic,
} from "vscode-languageserver/node.js";

import { TextDocument } from "vscode-languageserver-textdocument";
import { readFile, readdir, stat } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import {
  type ServerConfig,
  defaultConfig,
  mergeConfig,
} from "./config.js";

import { Logger } from "./logger.js";
import { DocumentStore, type DocumentEntry } from "./document-manager.js";
import { MoonParseRuntime, type CstErrorNode } from "./runtime.js";
import { createServerCapabilities } from "./capabilities.js";
import { MOONPARSE_VERSION } from "./version.js";
import { errorsToDiagnostics, bindingDiagnosticsToDiagnostics } from "./diagnostics.js";
import { SemanticTokensManager } from "./semantic-tokens.js";
import { extractDocumentSymbols } from "./document-symbol.js";
import { getDocumentHighlights } from "./document-highlight.js";
import { foldingRangesFromCaptures } from "./folding.js";
import {
  getWorkspaceDefinitionLocation,
  getWorkspaceReferenceLocations,
} from "./navigation.js";
import { getHover } from "./hover.js";
import { SymbolIndex } from "./symbol-index.js";
import { BindingIndex, bindingQueryForLang } from "./binding-index.js";
import { getCompletions } from "./completion.js";
import { parseTableInfo } from "./parse-table-info.js";
import { prepareRename, renameSymbol } from "./rename.js";
import { WorkspaceIndex } from "./workspace-index.js";
import { bindingDiagnosticsWithWorkspace } from "./workspace-bindings.js";
import {
  prepareWorkspaceRename,
  renameWorkspaceSymbol,
} from "./workspace-rename.js";
import type { WorkspaceFileEntry } from "./workspace-index.js";
import { formatGrammar, formatGrammarRange } from "./formatting.js";
import { getCodeActions } from "./code-actions.js";
import { isRangeChange, contentChangeToInputEdit } from "./input-edit.js";
import type { BindingGraph, MoonQuery, ParseTree } from "../../wasm/moonparse.js";

const connection = createConnection(ProposedFeatures.all);
const logger = new Logger(connection, defaultConfig.trace);

let config: ServerConfig = { ...defaultConfig };
let store = new DocumentStore(config);
let runtime = new MoonParseRuntime(logger, config.wasmPath);
let tokensManager = new SemanticTokensManager(runtime);
const workspaceIndex = new WorkspaceIndex(config.workspaceIndex);
let symbolIndex = new SymbolIndex();      // 旧索引，逐步迁移到 bindingIndex

// shutdown 后拒绝处理请求
let shutdownReceived = false;

// URI → 当前 ParseTree（用于增量解析及释放）
const configuredBundleIds = new Map<string, string>();
const parseDiagnosticsByUri = new Map<string, Diagnostic[]>();
const workspaceSkipDirectories = new Set([
  ".git",
  ".moon",
  "node_modules",
  "dist",
  "build",
  "out",
]);

function workspaceRootsFromInitialize(params: InitializeParams): string[] {
  const folders = params.workspaceFolders
    ?.map((folder) => folder.uri)
    .filter((uri): uri is string => !!uri) ?? [];
  if (folders.length > 0) return folders;
  if (params.rootUri) return [params.rootUri];
  if (params.rootPath) return [pathToFileURL(params.rootPath).href];
  return [];
}

function shouldIndexDocument(uri: string, sizeBytes: number): boolean {
  return workspaceIndex.shouldIndexUri(uri, sizeBytes, config.enabledExtensions);
}

// ── 生命周期 ──

connection.onInitialize(
  (params: InitializeParams): InitializeResult<ServerConfig> => {
    logger.info(
      `MoonParse LSP v${MOONPARSE_VERSION} — 初始化 (client: ${params.clientInfo?.name ?? "unknown"} ${params.clientInfo?.version ?? ""})`,
    );

    config = mergeConfig(
      defaultConfig,
      params.initializationOptions as Partial<ServerConfig> | undefined,
    );
    store.updateConfig(config);
    workspaceIndex.updateConfig(config.workspaceIndex);
    workspaceIndex.setRoots(workspaceRootsFromInitialize(params));

    return {
      capabilities: createServerCapabilities(),
      serverInfo: {
        name: "moonparse-lsp",
        version: MOONPARSE_VERSION,
      },
    };
  },
);

connection.onInitialized(() => {
  logger.info("服务已就绪");

  // 异步加载 WASM，不阻塞握手
  runtime.init().then(async () => {
    logger.info("WASM 运行时已就绪");

    // 注入句柄释放函数
    store.setFreeHandlers(
      (_treeHandle) => { /* ParseTree 由 runtime.freeTree 管理 */ },
      (_parserHandle) => { /* MoonParser 由 runtime.freeParser 管理 */ },
    );

    logger.telemetry("server.initialized");
    await syncConfiguredBundles();
    await indexWorkspaceRoots();
  }).catch((err) => {
    logger.error(`WASM 初始化失败: ${safeErrorMessage(err)}`);
  });
});

connection.onShutdown(() => {
  logger.info("收到 shutdown");
  shutdownReceived = true;

  // 释放所有 ParseTree
  workspaceIndex.dispose((tree) => runtime.freeTree(tree));

  store.dispose();
  runtime.dispose();
});

connection.onExit(() => {
  logger.info("退出");
  process.exit(0);
});

// ── 配置更新 ──

connection.onDidChangeConfiguration(async (change) => {
  const raw = (change.settings as { moonparse?: Partial<ServerConfig> })
    ?.moonparse;
  if (raw) {
    const prevTrace = config.trace;
    config = mergeConfig(defaultConfig, raw);
    store.updateConfig(config);
    workspaceIndex.updateConfig(config.workspaceIndex);

    if (config.trace !== prevTrace) {
      logger.setLevel(config.trace);
    }

    logger.info(
      `配置已更新 — trace=${config.trace} incremental=${config.incrementalParse}`,
    );
    if (runtime.loaded) {
      await syncConfiguredBundles();
      await indexWorkspaceRoots();
    }
  }
});

function registerBundleExtensions(id: string, extensions: string[]): void {
  for (const raw of extensions) {
    const extension = raw.startsWith(".") ? raw.slice(1) : raw;
    if (!extension) continue;
    config.grammarAssociations[extension] = id;
    if (!config.enabledExtensions.includes(extension)) {
      config.enabledExtensions.push(extension);
    }
  }
  store.updateConfig(config);
}

async function syncConfiguredBundles(): Promise<void> {
  const wanted = new Set(config.languageBundles.map((entry) => entry.path));
  for (const [path, id] of configuredBundleIds) {
    if (!wanted.has(path)) {
      runtime.freeParser(id);
      configuredBundleIds.delete(path);
    }
  }
  for (const entry of config.languageBundles) {
    try {
      const bundleJson = await readFile(entry.path, "utf8");
      const language = runtime.loadBundle(bundleJson);
      configuredBundleIds.set(entry.path, language.id);
      registerBundleExtensions(
        language.id,
        entry.extensions ?? language.extensions,
      );
    } catch (err) {
      logger.error(`Bundle 加载失败 (${entry.path}): ${safeErrorMessage(err)}`);
    }
  }
}

async function indexWorkspaceRoots(): Promise<void> {
  if (!runtime.loaded || !config.workspaceIndex.enabled) return;

  const roots = workspaceIndex.getRoots();
  if (roots.length === 0) return;

  for (const rootUri of roots) {
    if (!rootUri.startsWith("file:")) continue;
    try {
      await scanWorkspacePath(fileURLToPath(rootUri));
    } catch (err) {
      logger.error(`workspace index failed (${rootUri}): ${safeErrorMessage(err)}`);
    }
  }
  refreshOpenBindingDiagnostics();
  logger.trace(`workspace index files=${workspaceIndex.size}`);
}

async function scanWorkspacePath(filePath: string): Promise<void> {
  if (workspaceIndex.size >= config.workspaceIndex.maxFiles) return;

  const info = await stat(filePath);
  if (info.isDirectory()) {
    await scanWorkspaceDirectory(filePath);
    return;
  }
  if (info.isFile()) {
    await indexWorkspaceFile(filePath, info.size, info.mtimeMs);
  }
}

async function scanWorkspaceDirectory(dirPath: string): Promise<void> {
  if (workspaceIndex.size >= config.workspaceIndex.maxFiles) return;

  const entries = await readdir(dirPath, { withFileTypes: true });
  for (const entry of entries) {
    if (workspaceIndex.size >= config.workspaceIndex.maxFiles) return;
    if (entry.isDirectory()) {
      if (workspaceSkipDirectories.has(entry.name)) continue;
      await scanWorkspaceDirectory(join(dirPath, entry.name));
    } else if (entry.isFile()) {
      const filePath = join(dirPath, entry.name);
      const info = await stat(filePath);
      await indexWorkspaceFile(filePath, info.size, info.mtimeMs);
    }
  }
}

async function indexWorkspaceFile(
  filePath: string,
  sizeBytes: number,
  mtimeMs: number,
): Promise<void> {
  const uri = pathToFileURL(filePath).href;
  if (store.get(uri)) return;
  if (!store.isHandled(uri) || !shouldIndexDocument(uri, sizeBytes)) return;

  try {
    const text = await readFile(filePath, "utf8");
    const languageId = store.languageForUri(uri) ?? "unknown";
    const entry = createWorkspaceEntry(uri, text, languageId);
    parseWorkspaceFile(entry, sizeBytes, mtimeMs);
  } catch (err) {
    logger.error(`workspace file index failed (${uri}): ${safeErrorMessage(err)}`);
  }
}

function createWorkspaceEntry(
  uri: string,
  text: string,
  languageId: string,
): DocumentEntry {
  return {
    uri,
    text,
    version: -1,
    languageId,
    parserHandle: -1,
    treeHandle: -1,
    lastDiagnostics: [],
    lineOffsets: buildLineOffsets(text),
  };
}

function parseWorkspaceFile(
  entry: DocumentEntry,
  sizeBytes: number,
  mtimeMs: number,
): void {
  ensureParser(entry);
  if (!runtime.hasParser(entry.languageId)) return;

  const oldTree = workspaceIndex.tree(entry.uri);
  if (oldTree) {
    runtime.freeTree(oldTree);
    workspaceIndex.clearRuntime(entry.uri);
  }

  const tree = runtime.parseFull(entry.languageId, entry.text);
  const { graph, bindingIndex } = buildBindingsForTree(entry, tree);
  workspaceIndex.upsertParsedDocument({
    uri: entry.uri,
    text: entry.text,
    lineOffsets: entry.lineOffsets,
    languageId: entry.languageId,
    version: entry.version,
    mtimeMs,
    sizeBytes,
    isOpen: false,
    tree,
    graph,
    bindingIndex,
  });
}

connection.onRequest("moonparse/loadLanguageBundle", (params: {
  bundleJson: string;
  extensions?: string[];
}) => {
  const language = runtime.loadBundle(params.bundleJson);
  const extensions = params.extensions ?? language.extensions;
  registerBundleExtensions(language.id, extensions);
  void indexWorkspaceRoots();
  return {
    id: language.id,
    version: language.version,
    capabilities: language.capabilities,
    extensions,
  };
});

// ── 解析触发 ──

function ensureParser(entry: DocumentEntry): void {
  if (!runtime.loaded) return;
  if (runtime.hasParser(entry.languageId)) return;

  try {
    if (entry.languageId === "__dsl__") {
      runtime.createFromDsl(entry.languageId, entry.text);
    } else {
      // 内置语法：从 WASM builtin grammars 加载
      runtime.createFromBuiltinGrammar(entry.languageId);
    }

    tokensManager.ensureQueries(entry.languageId);
  } catch (err) {
    logger.error(
      `parser 创建失败 (${entry.languageId}): ${safeErrorMessage(err)}`,
    );
  }
}

function buildBindingsForTree(
  entry: DocumentEntry,
  tree: ParseTree,
): { graph: BindingGraph | null; bindingIndex: BindingIndex | null } {
  const bundleLanguage = runtime.getLanguage(entry.languageId);
  const bq = bindingQueryForLang(entry.languageId);
  let queryToFree: MoonQuery | null = null;

  try {
    let graph: BindingGraph;
    if (bundleLanguage?.capabilities.bindings) {
      graph = bundleLanguage.resolveBindings(tree);
    } else if (bq) {
      queryToFree = runtime.compileQuery(bq);
      graph = runtime.queryResolveBindings(queryToFree, tree);
    } else {
      return { graph: null, bindingIndex: null };
    }

    const bindingIndex = new BindingIndex();
    bindingIndex.update(entry.uri, entry, graph);
    return { graph, bindingIndex };
  } catch {
    return { graph: null, bindingIndex: null };
  } finally {
    if (queryToFree) runtime.freeQuery(queryToFree);
  }
}

function triggerParse(entry: DocumentEntry): void {
  if (!runtime.loaded) return;

  ensureParser(entry);
  if (!runtime.hasParser(entry.languageId)) return;
  if (!shouldIndexDocument(entry.uri, entry.text.length)) {
    workspaceIndex.remove(entry.uri, (tree) => runtime.freeTree(tree));
    parseDiagnosticsByUri.delete(entry.uri);
    connection.sendDiagnostics({ uri: entry.uri, diagnostics: [] });
    return;
  }

  try {
    logger.trace(`parse 开始: ${entry.uri} (${entry.text.length} 字节)`);

    // 尝试增量解析
    let tree: ParseTree;
    const oldTree = workspaceIndex.tree(entry.uri);
    const edit = entry.pendingEdit;
    const prevText = entry.previousText;

    if (config.incrementalParse && oldTree && edit && prevText) {
      try {
        tree = runtime.parseIncremental(
          entry.languageId, entry.text, oldTree, edit,
        );
        workspaceIndex.clearRuntime(entry.uri);
        logger.trace(`parse 增量: ${entry.uri}`);
      } catch {
        // 增量失败 → fallback 全量
        logger.trace(`parse 增量失败，回退全量: ${entry.uri}`);
        if (oldTree) {
          runtime.freeTree(oldTree);
          workspaceIndex.clearRuntime(entry.uri);
        }
        tree = runtime.parseFull(entry.languageId, entry.text);
      }
    } else {
      // 全量解析
      if (oldTree) {
        runtime.freeTree(oldTree);
        workspaceIndex.clearRuntime(entry.uri);
      }
      tree = runtime.parseFull(entry.languageId, entry.text);
    }

    // 清理增量状态
    entry.pendingEdit = undefined;
    entry.previousText = undefined;

    // 收集 CST 语法错误
    const errors: CstErrorNode[] = runtime.collectErrors(tree);
    const parseDiags = errorsToDiagnostics(entry, errors, config.maxDiagnostics);

    // 旧索引（仅 Grammar DSL，按 name 字符串匹配）
    if (entry.languageId === "__dsl__") {
      symbolIndex.build(entry.uri, entry, tree);
    }

    const { graph: bindingGraph, bindingIndex } = buildBindingsForTree(entry, tree);

    // 合并语法诊断 + 绑定诊断，推送到客户端
    workspaceIndex.upsertParsedDocument({
      uri: entry.uri,
      text: entry.text,
      lineOffsets: entry.lineOffsets,
      languageId: entry.languageId,
      version: entry.version,
      sizeBytes: entry.text.length,
      isOpen: true,
      tree,
      graph: bindingGraph,
      bindingIndex,
    });

    parseDiagnosticsByUri.set(entry.uri, parseDiags);
    publishDiagnosticsForEntry(entry, parseDiags);
    refreshOpenBindingDiagnostics(entry.uri);

    logger.trace(
      `parse 完成: ${entry.uri} root=${tree.root.type} errors=${errors.length}`,
    );
  } catch (err) {
    logger.error(`parse 失败 (${entry.uri}): ${safeErrorMessage(err)}`);
  }
}

// ── 文档同步：打开 / 修改 / 关闭 ──

function buildBindingIndexForText(entry: DocumentEntry, text: string): BindingIndex | null {
  if (!runtime.loaded || !runtime.hasParser(entry.languageId)) return null;
  const tree = runtime.parseFull(entry.languageId, text);
  let queryToFree: MoonQuery | null = null;
  try {
    const bundleLanguage = runtime.getLanguage(entry.languageId);
    let graph: BindingGraph;
    if (bundleLanguage?.capabilities.bindings) {
      graph = bundleLanguage.resolveBindings(tree);
    } else {
      const bq = bindingQueryForLang(entry.languageId);
      if (!bq) return null;
      queryToFree = runtime.compileQuery(bq);
      graph = runtime.queryResolveBindings(queryToFree, tree);
    }
    const tempEntry = { ...entry, text, lineOffsets: buildLineOffsets(text) };
    const index = new BindingIndex();
    index.update(entry.uri, tempEntry, graph);
    return index;
  } catch {
    return null;
  } finally {
    if (queryToFree) runtime.freeQuery(queryToFree);
    runtime.freeTree(tree);
  }
}

function rebuildWorkspaceFileForRename(
  file: WorkspaceFileEntry,
  text: string,
): { graph: BindingGraph | null; bindingIndex: BindingIndex | null } | null {
  if (!runtime.loaded) return null;
  const entry = createWorkspaceEntry(file.uri, text, file.languageId);
  ensureParser(entry);
  if (!runtime.hasParser(entry.languageId)) return null;
  const tree = runtime.parseFull(entry.languageId, text);
  try {
    return buildBindingsForTree(entry, tree);
  } finally {
    runtime.freeTree(tree);
  }
}

function isWorkspaceFileFreshForRename(file: WorkspaceFileEntry): boolean {
  if (!file.isOpen) return true;
  const entry = store.get(file.uri);
  if (!entry) return false;
  return workspaceIndex.isOpenEntryFresh(file.uri, entry.text, entry.version) &&
    !entry.pendingEdit &&
    !entry.previousText;
}

function buildLineOffsets(text: string): Uint32Array {
  const offsets: number[] = [0];
  for (let i = 0; i < text.length; i++) {
    if (text[i] === "\n") offsets.push(i + 1);
  }
  return new Uint32Array(offsets);
}

function publishDiagnosticsForEntry(
  entry: DocumentEntry,
  parseDiags: Diagnostic[] = parseDiagnosticsByUri.get(entry.uri) ?? [],
): void {
  const bindingIndex = workspaceIndex.bindingIndex(entry.uri);
  const bindingDiags = bindingIndex
    ? bindingDiagnosticsToDiagnostics(
      entry,
      bindingDiagnosticsWithWorkspace(entry.uri, bindingIndex, workspaceIndex),
      config.maxDiagnostics,
    )
    : [];
  const allDiags = [...parseDiags, ...bindingDiags];
  store.setDiagnostics(entry.uri, allDiags);
  connection.sendDiagnostics({ uri: entry.uri, diagnostics: allDiags });
}

function refreshOpenBindingDiagnostics(excludeUri?: string): void {
  for (const [uri, entry] of store.entries()) {
    if (uri === excludeUri) continue;
    publishDiagnosticsForEntry(entry);
  }
}

function tableInfoFor(entry: DocumentEntry) {
  return parseTableInfo(runtime.getParser(entry.languageId)?.tableJson());
}

connection.onDidOpenTextDocument((params) => {
  if (shutdownReceived) return;
  try {
    const { uri, version, text } = params.textDocument;

    if (!store.isHandled(uri) || !shouldIndexDocument(uri, text.length)) {
      logger.trace(`didOpen 跳过: ${uri} (扩展名未在 enabledExtensions 中)`);
      return;
    }

    store.open(uri, text, version);
    const entry = store.get(uri);
    logger.trace(
      `didOpen: ${uri} lang=${entry?.languageId} v${version} (${text.length} 字节)`,
    );

    if (entry) triggerParse(entry);
  } catch (err) {
    logger.error(`didOpen 异常: ${safeErrorMessage(err)}`);
  }
});

connection.onDidChangeTextDocument((params) => {
  if (shutdownReceived) return;
  try {
    const { uri } = params.textDocument;
    const entry = store.get(uri);
    if (!entry) {
      logger.trace(`didChange 跳过: ${uri} 未被跟踪`);
      return;
    }

    // 合并增量变更
    const prevText = entry.text;
    const prevDoc = TextDocument.create(uri, "", entry.version, prevText);
    const updated = TextDocument.update(
      prevDoc,
      params.contentChanges,
      params.textDocument.version,
    );

    const newText = updated.getText();

    // 生成增量编辑信息（单次 range change 才走增量路径）
    const change = params.contentChanges[0];
    if (params.contentChanges.length === 1 && isRangeChange(change)) {
      // 已有未消费的 pendingEdit → 不可叠加，清空走 full parse
      if (entry.pendingEdit || entry.previousText) {
        entry.pendingEdit = undefined;
        entry.previousText = undefined;
      } else {
        entry.pendingEdit = contentChangeToInputEdit(
          prevText, entry.lineOffsets, change,
        );
        entry.previousText = prevText;
      }
    } else {
      // full doc 或 multi-change 清空旧增量状态
      entry.pendingEdit = undefined;
      entry.previousText = undefined;
    }

    logger.trace(
      `didChange: ${uri} v${params.textDocument.version}` +
        ` 变更数=${params.contentChanges.length} 文本=${newText.length}字节`,
    );

    if (!shouldIndexDocument(uri, newText.length)) {
      workspaceIndex.remove(uri, (tree) => runtime.freeTree(tree));
      parseDiagnosticsByUri.delete(uri);
      store.update(uri, newText, params.textDocument.version);
      connection.sendDiagnostics({ uri, diagnostics: [] });
      return;
    }

    store.update(uri, newText, params.textDocument.version);

    // 防抖解析
    store.scheduleParse(uri, triggerParse);
    logger.trace(
      `didChange: ${uri} 已排入防抖队列 (${config.debounceMs}ms)`,
    );
  } catch (err) {
    logger.error(`didChange 异常: ${safeErrorMessage(err)}`);
  }
});

connection.onDidCloseTextDocument((params) => {
  if (shutdownReceived) return;
  try {
    const { uri } = params.textDocument;

    // 释放 tree 和 parser
    workspaceIndex.markClosed(uri);
    const entry = store.get(uri);
    if (entry) {
      // 仅在没有其他同语言文档打开时释放 language-level 缓存
      const langId = entry.languageId;
      if (store.countByLanguage(langId, uri) === 0) {
        tokensManager.freeQueries(langId);
        runtime.freeParser(langId);
      }
    }

    store.close(uri);
    parseDiagnosticsByUri.delete(uri);

    // 清除符号索引
    symbolIndex.clear();

    // 推送空诊断清除波浪线
    connection.sendDiagnostics({ uri, diagnostics: [] });

    logger.trace(`didClose: ${uri} (剩余打开文档: ${store.count})`);
  } catch (err) {
    logger.error(`didClose 异常: ${safeErrorMessage(err)}`);
  }
});

// ── semanticTokens ──

connection.onRequest("textDocument/semanticTokens/full", (params: { textDocument: { uri: string } }) => {
  if (shutdownReceived) return { data: [] };
  try {
    const { uri } = params.textDocument;
    const entry = store.get(uri);
    const tree = workspaceIndex.tree(uri);
    if (!entry || !tree) return { data: [] };

    const data = tokensManager.generateTokens(entry, tree);
    if (!data) return { data: [] };

    logger.trace(`semanticTokens: ${uri} → ${data.length / 5} tokens`);
    return { data };
  } catch (err) {
    logger.error(`semanticTokens 异常: ${safeErrorMessage(err)}`);
    return { data: [] };
  }
});

// ── documentSymbol — 代码大纲 ──

connection.onRequest("textDocument/documentSymbol", (params: { textDocument: { uri: string } }) => {
  if (shutdownReceived) return [];
  try {
    const { uri } = params.textDocument;
    const entry = store.get(uri);
    const tree = workspaceIndex.tree(uri);
    if (!entry || !tree) return [];

    const symbols = extractDocumentSymbols(entry, tree, workspaceIndex.bindingIndex(uri));
    logger.trace(`documentSymbol: ${uri} → ${symbols.length} symbols`);
    return symbols;
  } catch (err) {
    logger.error(`documentSymbol 异常: ${safeErrorMessage(err)}`);
    return [];
  }
});

connection.onRequest("textDocument/documentHighlight", (params: PositionParams) => {
  if (shutdownReceived) return [];
  try {
    const { uri } = params.textDocument;
    const entry = store.get(uri);
    if (!entry) return [];

    const highlights = getDocumentHighlights(
      entry,
      workspaceIndex.bindingIndex(uri),
      params.position.line,
      params.position.character,
    );
    logger.trace(`documentHighlight: ${uri} → ${highlights.length} ranges`);
    return highlights;
  } catch (err) {
    logger.error(`documentHighlight 异常: ${safeErrorMessage(err)}`);
    return [];
  }
});

connection.onRequest("textDocument/foldingRange", (params: { textDocument: { uri: string } }) => {
  if (shutdownReceived) return [];
  try {
    const { uri } = params.textDocument;
    const entry = store.get(uri);
    const tree = workspaceIndex.tree(uri);
    if (!entry || !tree) return [];

    const language = runtime.getLanguage(entry.languageId);
    if (!language?.capabilities.folding) return [];
    const ranges = foldingRangesFromCaptures(entry, language.fold(tree));
    logger.trace(`foldingRange: ${uri} → ${ranges.length} ranges`);
    return ranges;
  } catch (err) {
    logger.error(`foldingRange 异常: ${safeErrorMessage(err)}`);
    return [];
  }
});

// ── hover — 光标悬停提示 ──

interface HoverParams {
  textDocument: { uri: string };
  position: { line: number; character: number };
}

connection.onRequest("textDocument/hover", (params: HoverParams) => {
  if (shutdownReceived) return null;
  try {
    const { uri } = params.textDocument;
    const entry = store.get(uri);
    const tree = workspaceIndex.tree(uri);
    if (!entry || !tree) return null;

    const hover = getHover(entry, tree, params.position.line, params.position.character);
    if (hover) {
      logger.trace(
        `hover: ${uri} [${params.position.line}:${params.position.character}] → 命中`,
      );
    }
    return hover;
  } catch (err) {
    logger.error(`hover 异常: ${safeErrorMessage(err)}`);
    return null;
  }
});

// -- definition / references via BindingIndex --

interface PositionParams {
  textDocument: { uri: string };
  position: { line: number; character: number };
}

connection.onRequest("textDocument/definition", (params: PositionParams) => {
  if (shutdownReceived) return null;
  try {
    const { uri } = params.textDocument;
    const entry = store.get(uri);
    if (!entry) return null;

    const location = getWorkspaceDefinitionLocation(
      entry,
      workspaceIndex.bindingIndex(uri),
      workspaceIndex,
      params.position.line,
      params.position.character,
    );
    if (location) logger.trace(`definition(binding): ${uri}`);
    return location;
  } catch (err) {
    logger.error(`definition 异常: ${safeErrorMessage(err)}`);
    return null;
  }
});

interface ReferencesParams extends PositionParams {
  context: { includeDeclaration: boolean };
}

connection.onRequest("textDocument/references", (params: ReferencesParams) => {
  if (shutdownReceived) return [];
  try {
    const { uri } = params.textDocument;
    const entry = store.get(uri);
    if (!entry) return [];

    const locations = getWorkspaceReferenceLocations(
      entry,
      workspaceIndex.bindingIndex(uri),
      workspaceIndex,
      params.position.line,
      params.position.character,
      params.context?.includeDeclaration !== false,
    );
    logger.trace(`references(binding): ${uri} -> ${locations.length} locations`);
    return locations;
  } catch (err) {
    logger.error(`references 异常: ${safeErrorMessage(err)}`);
    return [];
  }
});

// ── completion — 代码补全 ──

connection.onRequest("textDocument/prepareRename", (params: PositionParams) => {
  if (shutdownReceived) return null;
  try {
    const { uri } = params.textDocument;
    const entry = store.get(uri);
    if (!entry) return null;
    const workspaceResult = prepareWorkspaceRename(
      entry,
      workspaceIndex.bindingIndex(uri),
      workspaceIndex,
      tableInfoFor(entry),
      params.position.line,
      params.position.character,
    );
    if (workspaceResult.applies) return workspaceResult.result;
    return prepareRename(
      entry,
      workspaceIndex.bindingIndex(uri),
      tableInfoFor(entry),
      params.position.line,
      params.position.character,
    );
  } catch (err) {
    logger.error(`prepareRename 异常: ${safeErrorMessage(err)}`);
    return null;
  }
});

interface RenameParams extends PositionParams {
  newName: string;
}

connection.onRequest("textDocument/rename", (params: RenameParams) => {
  if (shutdownReceived) return null;
  try {
    const { uri } = params.textDocument;
    const entry = store.get(uri);
    if (!entry) return null;
    const workspaceResult = renameWorkspaceSymbol(
      entry,
      workspaceIndex.bindingIndex(uri),
      workspaceIndex,
      tableInfoFor(entry),
      params.position.line,
      params.position.character,
      params.newName,
      {
        rebuildFile: rebuildWorkspaceFileForRename,
        isOpenFileFresh: isWorkspaceFileFreshForRename,
      },
    );
    if (workspaceResult.applies) return workspaceResult.edit;
    return renameSymbol(
      entry,
      workspaceIndex.bindingIndex(uri),
      tableInfoFor(entry),
      params.position.line,
      params.position.character,
      params.newName,
      (text) => buildBindingIndexForText(entry, text),
    );
  } catch (err) {
    logger.error(`rename 异常: ${safeErrorMessage(err)}`);
    return null;
  }
});

interface CompletionParams extends PositionParams {
  context?: { triggerKind: number; triggerCharacter?: string };
}

connection.onRequest("textDocument/completion", (params: CompletionParams) => {
  if (shutdownReceived) return null;
  try {
    const { uri } = params.textDocument;
    const entry = store.get(uri);
    const tree = workspaceIndex.tree(uri);
    if (!entry || !tree) return null;

    const items = getCompletions(
      entry,
      tree,
      workspaceIndex.bindingIndex(uri),
      tableInfoFor(entry),
      params.position.line,
      params.position.character,
    );

    if (!items || items.length === 0) return null;

    logger.trace(
      `completion: ${uri} [${params.position.line}:${params.position.character}] → ${items.length} items`,
    );
    return { isIncomplete: false, items };
  } catch (err) {
    logger.error(`completion 异常: ${safeErrorMessage(err)}`);
    return null;
  }
});

// ── formatting — Grammar DSL 格式化 ──

interface FormattingParams {
  textDocument: { uri: string };
  options: { tabSize: number; insertSpaces: boolean };
}

function makePos(line: number, character: number): { line: number; character: number } {
  return { line, character };
}

connection.onRequest("textDocument/formatting", (params: FormattingParams) => {
  if (shutdownReceived) return [];
  try {
    const entry = store.get(params.textDocument.uri);
    if (!entry || entry.languageId !== "__dsl__") return [];

    return formatGrammar(entry.text, (line, char) => makePos(line, char));
  } catch (err) {
    logger.error(`formatting 异常: ${safeErrorMessage(err)}`);
    return [];
  }
});

interface RangeFormattingParams extends FormattingParams {
  range: { start: { line: number; character: number }; end: { line: number; character: number } };
}

connection.onRequest("textDocument/rangeFormatting", (params: RangeFormattingParams) => {
  if (shutdownReceived) return [];
  try {
    const entry = store.get(params.textDocument.uri);
    if (!entry || entry.languageId !== "__dsl__") return [];

    return formatGrammarRange(
      entry.text,
      params.range.start,
      params.range.end,
      (line, char) => makePos(line, char),
    );
  } catch (err) {
    logger.error(`rangeFormatting 异常: ${safeErrorMessage(err)}`);
    return [];
  }
});

// ── codeAction — Quick Fix ──

interface CodeActionParams {
  textDocument: { uri: string };
  range: { start: { line: number; character: number }; end: { line: number; character: number } };
  context: { diagnostics: Diagnostic[] };
}

connection.onRequest("textDocument/codeAction", (params: CodeActionParams) => {
  if (shutdownReceived) return [];
  try {
    const entry = store.get(params.textDocument.uri);
    if (!entry || params.context.diagnostics.length === 0) return [];

    const actions = getCodeActions(entry, params.context.diagnostics, symbolIndex);
    logger.trace(
      `codeAction: ${params.textDocument.uri} → ${actions.length} actions`,
    );
    return actions;
  } catch (err) {
    logger.error(`codeAction 异常: ${safeErrorMessage(err)}`);
    return [];
  }
});

// semanticTokens/range — 仅返回与请求范围有交集的 token
interface SemanticTokensRangeParams {
  textDocument: { uri: string };
  range: { start: { line: number; character: number }; end: { line: number; character: number } };
}

connection.onRequest("textDocument/semanticTokens/range", (params: SemanticTokensRangeParams) => {
  if (shutdownReceived) return { data: [] };
  try {
    const { uri } = params.textDocument;
    const entry = store.get(uri);
    const tree = workspaceIndex.tree(uri);
    if (!entry || !tree) return { data: [] };

    // LSP range → 字节范围
    const startByte = store.byteOffset(entry, params.range.start.line, params.range.start.character);
    const endByte = store.byteOffset(entry, params.range.end.line, params.range.end.character);

    const data = tokensManager.generateTokensRange(entry, tree, startByte, endByte);
    if (!data) return { data: [] };

    logger.trace(
      `semanticTokens/range: ${uri} [${params.range.start.line}:${params.range.start.character}–${params.range.end.line}:${params.range.end.character}] → ${data.length / 5} tokens`,
    );
    return { data };
  } catch (err) {
    logger.error(`semanticTokens/range 异常: ${safeErrorMessage(err)}`);
    return { data: [] };
  }
});

// ── 全局兜底错误处理 ──

process.on("uncaughtException", (err) => {
  logger.error(`未捕获异常: ${safeErrorMessage(err)}`);
});

process.on("unhandledRejection", (reason) => {
  logger.error(`未处理的 rejection: ${safeErrorMessage(reason)}`);
});

// ── 工具函数 ──

function safeErrorMessage(err: unknown): string {
  if (err instanceof Error) return err.message;
  if (typeof err === "string") return err;
  try {
    return JSON.stringify(err);
  } catch {
    return String(err);
  }
}

// ── 启动监听 ──

connection.listen();
