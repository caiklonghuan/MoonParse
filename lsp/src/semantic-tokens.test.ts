import { describe, it, expect } from "vitest";
import { TOKEN_TYPES, TOKEN_MODIFIERS } from "./semantic-tokens.js";

describe("TOKEN_TYPES", () => {
  it("包含 8 个标准 token type", () => {
    expect(TOKEN_TYPES).toHaveLength(8);
  });

  it("索引顺序与 LSP 规范一致", () => {
    expect(TOKEN_TYPES[0]).toBe("function");
    expect(TOKEN_TYPES[1]).toBe("variable");
    expect(TOKEN_TYPES[2]).toBe("keyword");
    expect(TOKEN_TYPES[3]).toBe("string");
    expect(TOKEN_TYPES[4]).toBe("number");
    expect(TOKEN_TYPES[5]).toBe("comment");
    expect(TOKEN_TYPES[6]).toBe("type");
    expect(TOKEN_TYPES[7]).toBe("operator");
  });

  it("所有值均为唯一", () => {
    const seen = new Set<string>();
    for (const t of TOKEN_TYPES) {
      expect(seen.has(t)).toBe(false);
      seen.add(t);
    }
  });
});

describe("TOKEN_MODIFIERS", () => {
  it("当前列表为空", () => {
    expect(TOKEN_MODIFIERS).toEqual([]);
  });
});
