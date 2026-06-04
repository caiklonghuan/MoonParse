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
}

export type ServerTraceLevel = "off" | "messages" | "verbose";

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
};

// 将用户部分配置合并到默认值
export function mergeConfig(
  defaults: ServerConfig,
  overrides: Partial<ServerConfig> | undefined,
): ServerConfig {
  if (!overrides) return defaults;
  return {
    trace: overrides.trace ?? defaults.trace,
    maxDiagnostics: overrides.maxDiagnostics ?? defaults.maxDiagnostics,
    enabledExtensions:
      overrides.enabledExtensions ?? defaults.enabledExtensions,
    grammarAssociations:
      overrides.grammarAssociations ?? defaults.grammarAssociations,
    incrementalParse: overrides.incrementalParse ?? defaults.incrementalParse,
    wasmPath: overrides.wasmPath ?? defaults.wasmPath,
    debounceMs: overrides.debounceMs ?? defaults.debounceMs,
  };
}
