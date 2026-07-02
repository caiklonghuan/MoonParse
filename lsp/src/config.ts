// MoonParse LSP 服务配置

export interface ServerConfig {
  // 日志级别："off" | "messages" | "verbose"
  trace: ServerTraceLevel;

  // 每文件最多报错条数
  maxDiagnostics: number;

  // 需要处理的文件扩展名（不含点）
  enabledExtensions: string[];

  // 扩展名 → 语法 id 映射。内置 id：json / json5 / c / python / moonbit
  grammarAssociations: Record<string, string>;

  // 是否启用增量解析
  incrementalParse: boolean;

  // MoonParse WASM 文件路径
  wasmPath: string;

  // 解析防抖延迟（毫秒），连续输入时只触发最后一次。默认 100
  debounceMs: number;

  // 启动时加载的 LanguageBundle；配置扩展名优先于 Bundle 元数据。
  languageBundles: Array<{ path: string; extensions?: string[] }>;

  workspaceIndex: WorkspaceIndexConfig;
}

export type ServerTraceLevel = "off" | "messages" | "verbose";

export interface WorkspaceIndexConfig {
  enabled: boolean;
  maxFileBytes: number;
  maxFiles: number;
  parseTimeoutMs: number;
  idleEvictMs: number;
}

export const defaultConfig: ServerConfig = {
  trace: "off",
  maxDiagnostics: 256,
  enabledExtensions: ["grammar", "c", "h", "py", "mbt", "json", "json5"],
  grammarAssociations: {
    "grammar": "__dsl__", // Grammar DSL 特殊处理
    "c": "c",
    "h": "c",
    "py": "python",
    "mbt": "moonbit",
    "json": "json",
    "json5": "json5",
  },
  incrementalParse: true,
  wasmPath: "./moonparse.wasm",
  debounceMs: 100,
  languageBundles: [],
  workspaceIndex: {
    enabled: true,
    maxFileBytes: 1_000_000,
    maxFiles: 2000,
    parseTimeoutMs: 5000,
    idleEvictMs: 300000,
  },
};

// 将用户部分配置合并到默认值
export function mergeConfig(
  defaults: ServerConfig,
  overrides: Partial<ServerConfig> | undefined,
): ServerConfig {
  const value = overrides ?? {};
  return {
    trace: value.trace ?? defaults.trace,
    maxDiagnostics: value.maxDiagnostics ?? defaults.maxDiagnostics,
    enabledExtensions:
      [...(value.enabledExtensions ?? defaults.enabledExtensions)],
    grammarAssociations:
      { ...(value.grammarAssociations ?? defaults.grammarAssociations) },
    incrementalParse: value.incrementalParse ?? defaults.incrementalParse,
    wasmPath: value.wasmPath ?? defaults.wasmPath,
    debounceMs: value.debounceMs ?? defaults.debounceMs,
    languageBundles: [...(value.languageBundles ?? defaults.languageBundles)],
    workspaceIndex: {
      enabled: value.workspaceIndex?.enabled ?? defaults.workspaceIndex.enabled,
      maxFileBytes:
        value.workspaceIndex?.maxFileBytes ?? defaults.workspaceIndex.maxFileBytes,
      maxFiles: value.workspaceIndex?.maxFiles ?? defaults.workspaceIndex.maxFiles,
      parseTimeoutMs:
        value.workspaceIndex?.parseTimeoutMs ?? defaults.workspaceIndex.parseTimeoutMs,
      idleEvictMs:
        value.workspaceIndex?.idleEvictMs ?? defaults.workspaceIndex.idleEvictMs,
    },
  };
}
