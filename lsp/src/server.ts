import {
  createConnection,
  ProposedFeatures,
  TextDocumentSyncKind,
  type InitializeParams,
  type InitializeResult,
  type Diagnostic,
} from "vscode-languageserver/node.js";

import { TextDocument } from "vscode-languageserver-textdocument";

import {
  type ServerConfig,
  defaultConfig,
  mergeConfig,
} from "./config.js";

import { Logger } from "./logger.js";
import { DocumentStore, type DocumentEntry } from "./document-manager.js";
import { MoonParseRuntime, type CstErrorNode } from "./runtime.js";
import { errorsToDiagnostics, bindingDiagnosticsToDiagnostics } from "./diagnostics.js";
import {
  SemanticTokensManager,
  TOKEN_TYPES,
  TOKEN_MODIFIERS,
} from "./semantic-tokens.js";
import { extractDocumentSymbols } from "./document-symbol.js";
import { getHover } from "./hover.js";
import { SymbolIndex } from "./symbol-index.js";
import { BindingIndex, bindingQueryForLang } from "./binding-index.js";
import { getCompletions } from "./completion.js";
import { formatGrammar, formatGrammarRange } from "./formatting.js";
import { getCodeActions } from "./code-actions.js";
import { isRangeChange, contentChangeToInputEdit } from "./input-edit.js";
import type { ParseTree } from "../../wasm/moonparse.js";

const connection = createConnection(ProposedFeatures.all);
const logger = new Logger(connection, defaultConfig.trace);

let config: ServerConfig = { ...defaultConfig };
let store = new DocumentStore(config);
let runtime = new MoonParseRuntime(logger, config.wasmPath);
let tokensManager = new SemanticTokensManager(runtime);
let symbolIndex = new SymbolIndex();      // 旧索引，逐步迁移到 bindingIndex
const bindingIndexes = new Map<string, BindingIndex>();  // 每 URI 一个索引

// shutdown 后拒绝处理请求
let shutdownReceived = false;

// URI → 当前 ParseTree（用于增量解析及释放）
const currentTrees = new Map<string, ParseTree>();

// ── 生命周期 ──

connection.onInitialize(
  (params: InitializeParams): InitializeResult<ServerConfig> => {
    logger.info(
      `MoonParse LSP v0.1.0 — 初始化 (client: ${params.clientInfo?.name ?? "unknown"} ${params.clientInfo?.version ?? ""})`,
    );

    config = mergeConfig(
      defaultConfig,
      params.initializationOptions as Partial<ServerConfig> | undefined,
    );
    store.updateConfig(config);

    return {
      capabilities: {
        textDocumentSync: {
          openClose: true,
          change: TextDocumentSyncKind.Incremental,
        },
        semanticTokensProvider: {
          legend: {
            tokenTypes: TOKEN_TYPES as unknown as string[],
            tokenModifiers: TOKEN_MODIFIERS,
          },
          full: true,
          range: true,
        },
        documentSymbolProvider: true,
        hoverProvider: true,
        definitionProvider: true,
        referencesProvider: true,
        completionProvider: {
          triggerCharacters: [".", "@"],
        },
        documentFormattingProvider: true,
        documentRangeFormattingProvider: true,
        codeActionProvider: true,
        // Phase 3+ 将启用以下能力：
        // foldingRangeProvider / documentHighlightProvider
        // renameProvider
      },
      serverInfo: {
        name: "moonparse-lsp",
        version: "0.1.0",
      },
    };
  },
);

connection.onInitialized(() => {
  logger.info("服务已就绪");

  // 异步加载 WASM，不阻塞握手
  runtime.init().then(() => {
    logger.info("WASM 运行时已就绪");

    // 注入句柄释放函数
    store.setFreeHandlers(
      (_treeHandle) => { /* ParseTree 由 runtime.freeTree 管理 */ },
      (_parserHandle) => { /* MoonParser 由 runtime.freeParser 管理 */ },
    );

    logger.telemetry("server.initialized");
  }).catch((err) => {
    logger.error(`WASM 初始化失败: ${safeErrorMessage(err)}`);
  });
});

connection.onShutdown(() => {
  logger.info("收到 shutdown");
  shutdownReceived = true;

  // 释放所有 ParseTree
  for (const [, tree] of currentTrees) {
    runtime.freeTree(tree);
  }
  currentTrees.clear();

  store.dispose();
  runtime.dispose();
});

connection.onExit(() => {
  logger.info("退出");
  process.exit(0);
});

// ── 配置更新 ──

connection.onDidChangeConfiguration((change) => {
  const raw = (change.settings as { moonparse?: Partial<ServerConfig> })
    ?.moonparse;
  if (raw) {
    const prevTrace = config.trace;
    config = mergeConfig(defaultConfig, raw);
    store.updateConfig(config);

    if (config.trace !== prevTrace) {
      logger.setLevel(config.trace);
    }

    logger.info(
      `配置已更新 — trace=${config.trace} incremental=${config.incrementalParse}`,
    );
  }
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

function triggerParse(entry: DocumentEntry): void {
  if (!runtime.loaded) return;

  ensureParser(entry);
  if (!runtime.hasParser(entry.languageId)) return;

  try {
    logger.trace(`parse 开始: ${entry.uri} (${entry.text.length} 字节)`);

    // 尝试增量解析
    let tree: ParseTree;
    const oldTree = currentTrees.get(entry.uri);
    const edit = entry.pendingEdit;
    const prevText = entry.previousText;

    if (config.incrementalParse && oldTree && edit && prevText) {
      try {
        tree = runtime.parseIncremental(
          entry.languageId, entry.text, oldTree, edit,
        );
        logger.trace(`parse 增量: ${entry.uri}`);
      } catch {
        // 增量失败 → fallback 全量
        logger.trace(`parse 增量失败，回退全量: ${entry.uri}`);
        if (oldTree) { runtime.freeTree(oldTree); }
        tree = runtime.parseFull(entry.languageId, entry.text);
      }
    } else {
      // 全量解析
      if (oldTree) { runtime.freeTree(oldTree); }
      tree = runtime.parseFull(entry.languageId, entry.text);
    }

    // 清理增量状态
    currentTrees.set(entry.uri, tree);
    entry.pendingEdit = undefined;
    entry.previousText = undefined;

    // 收集 CST 语法错误
    const errors: CstErrorNode[] = runtime.collectErrors(tree);
    const parseDiags = errorsToDiagnostics(entry, errors, config.maxDiagnostics);

    // 旧索引（仅 Grammar DSL，按 name 字符串匹配）
    if (entry.languageId === "__dsl__") {
      symbolIndex.build(entry.uri, entry, tree);
    }

    // 新索引（任意语言，按 scope/edge 精确匹配）
    const bq = bindingQueryForLang(entry.languageId);
    if (bq) {
      try {
        const query = runtime.compileQuery(bq);
        const graph = runtime.queryResolveBindings(query, tree);
        const bi = new BindingIndex();
        bi.update(entry.uri, entry, graph);
        bindingIndexes.set(entry.uri, bi);
        runtime.freeQuery(query);
      } catch {
        // binding query 编译失败 → 清除该 URI 旧索引
        bindingIndexes.delete(entry.uri);
      }
    } else {
      // 该语言无 binding query → 清除旧索引
      bindingIndexes.delete(entry.uri);
    }

    // 合并语法诊断 + 绑定诊断，推送到客户端
    const bi = bindingIndexes.get(entry.uri);
    const bindingDiags = bi
      ? bindingDiagnosticsToDiagnostics(entry, bi.diagnostics(), config.maxDiagnostics)
      : [];
    const allDiags = [...parseDiags, ...bindingDiags];
    connection.sendDiagnostics({ uri: entry.uri, diagnostics: allDiags });

    logger.trace(
      `parse 完成: ${entry.uri} root=${tree.root.type} errors=${errors.length}`,
    );
  } catch (err) {
    logger.error(`parse 失败 (${entry.uri}): ${safeErrorMessage(err)}`);
  }
}

// ── 文档同步：打开 / 修改 / 关闭 ──

connection.onDidOpenTextDocument((params) => {
  if (shutdownReceived) return;
  try {
    const { uri, version, text } = params.textDocument;

    if (!store.isHandled(uri)) {
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
    const tree = currentTrees.get(uri);
    if (tree) {
      runtime.freeTree(tree);
      currentTrees.delete(uri);
    }
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

    // 清除符号索引
    symbolIndex.clear();
    bindingIndexes.delete(uri);

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
    const tree = currentTrees.get(uri);
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
    const tree = currentTrees.get(uri);
    if (!entry || !tree) return [];

    const symbols = extractDocumentSymbols(entry, tree);
    logger.trace(`documentSymbol: ${uri} → ${symbols.length} symbols`);
    return symbols;
  } catch (err) {
    logger.error(`documentSymbol 异常: ${safeErrorMessage(err)}`);
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
    const tree = currentTrees.get(uri);
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

// ── definition / references（Grammar DSL） ──

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

    // 优先用新 bindingIndex（scope/edge 精确匹配）
    const bi = bindingIndexes.get(uri);
    const sym = bi?.getSymbolAt(
      entry,
      params.position.line,
      params.position.character,
    );
    if (sym && bi) {
      let targetDef = sym.kind === "definition"
        ? bi.getDefinition(sym.id)
        : bi.findDefinition(sym.id);

      if (targetDef) {
        const lspPos = store.byteToPosition(entry, targetDef.start_byte);
        logger.trace(
          `definition(binding): ${sym.name} → [${lspPos.line}:${lspPos.character}]`,
        );
        return {
          uri,
          range: { start: lspPos, end: store.byteToPosition(entry, targetDef.end_byte) },
        };
      }
    }

    // 回退旧 symbolIndex
    const hit = symbolIndex.getNameAt(
      entry,
      params.position.line,
      params.position.character,
    );
    if (hit) {
      const def = symbolIndex.findDefinition(hit.name);
      if (def) {
        logger.trace(
          `definition: ${hit.name} → [${def.range.start.line}:${def.range.start.character}]`,
        );
        return { uri: def.uri, range: def.range };
      }
    }

    return null;
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

    // 优先用新 bindingIndex
    const bi = bindingIndexes.get(uri);
    const sym = bi?.getSymbolAt(
      entry,
      params.position.line,
      params.position.character,
    );
    if (sym && bi) {
      // 找到该符号对应的"权威定义 ID"
      const defId = sym.kind === "definition"
        ? sym.id
        : bi.findDefinition(sym.id)?.id;

      if (defId !== undefined) {
        const refs = bi.findReferences(defId);
        const results = [];
        // 包含声明本身
        if (params.context?.includeDeclaration !== false) {
          const def = bi.getDefinition(defId);
          if (def) {
            results.push({
              uri,
              range: {
                start: store.byteToPosition(entry, def.start_byte),
                end: store.byteToPosition(entry, def.end_byte),
              },
            });
          }
        }
        for (const r of refs) {
          results.push({
            uri,
            range: {
              start: store.byteToPosition(entry, r.start_byte),
              end: store.byteToPosition(entry, r.end_byte),
            },
          });
        }
        logger.trace(
          `references(binding): ${sym.name} → ${results.length} locations`,
        );
        return results;
      }
    }

    // 回退旧 symbolIndex
    const hit = symbolIndex.getNameAt(
      entry,
      params.position.line,
      params.position.character,
    );
    if (hit) {
      const refs = symbolIndex.findReferences(hit.name);
      logger.trace(
        `references: ${hit.name} → ${refs.length} locations`,
      );
      return refs.map((r) => ({ uri: r.uri, range: r.range }));
    }

    return [];
  } catch (err) {
    logger.error(`references 异常: ${safeErrorMessage(err)}`);
    return [];
  }
});

// ── completion — 代码补全 ──

interface CompletionParams extends PositionParams {
  context?: { triggerKind: number; triggerCharacter?: string };
}

connection.onRequest("textDocument/completion", (params: CompletionParams) => {
  if (shutdownReceived) return null;
  try {
    const { uri } = params.textDocument;
    const entry = store.get(uri);
    const tree = currentTrees.get(uri);
    if (!entry || !tree) return null;

    const items = getCompletions(
      entry,
      tree,
      symbolIndex,
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
    const tree = currentTrees.get(uri);
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
