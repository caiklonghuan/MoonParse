import { describe, expect, it } from "vitest";

import { defaultConfig, mergeConfig } from "./config.js";

describe("mergeConfig", () => {
  it("keeps workspace index resource defaults", () => {
    const merged = mergeConfig(defaultConfig, undefined);

    expect(merged.workspaceIndex.parseTimeoutMs).toBe(5000);
    expect(merged.workspaceIndex.idleEvictMs).toBe(300000);
  });

  it("overrides workspace index resource limits independently", () => {
    const merged = mergeConfig(defaultConfig, {
      workspaceIndex: {
        enabled: false,
        maxFileBytes: 123,
        maxFiles: 4,
        parseTimeoutMs: 25,
        idleEvictMs: 50,
      },
    });

    expect(merged.workspaceIndex).toEqual({
      enabled: false,
      maxFileBytes: 123,
      maxFiles: 4,
      parseTimeoutMs: 25,
      idleEvictMs: 50,
    });
  });

  it("merges lint defaults and copies override maps", () => {
    const ruleSets = { "json/recommended": false };
    const rules = { "json/recommended/negative-zero": "error" as const };
    const merged = mergeConfig(defaultConfig, {
      lint: { enabled: true, ruleSets, rules },
    });
    expect(merged.lint).toEqual({ enabled: true, ruleSets, rules });
    expect(merged.lint.ruleSets).not.toBe(ruleSets);
    expect(mergeConfig(defaultConfig, undefined).lint).toEqual({
      enabled: true,
      ruleSets: {},
      rules: {},
    });
  });
});
