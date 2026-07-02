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
});
