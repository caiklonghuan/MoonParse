export interface ParseTableInfo {
  literalTerminals: string[];
  wordPattern?: string;
}

interface TerminalPattern {
  id: number | string;
  pattern?: {
    type?: string;
    value?: string;
  };
}

interface KeywordEntry {
  k?: string;
  v?: number | string;
}

interface ParseTableJson {
  terminal_patterns?: TerminalPattern[];
  keyword_map?: KeywordEntry[] | Record<string, number | string>;
  word_token?: number | string;
}

export function parseTableInfo(tableJson: string | undefined): ParseTableInfo {
  if (!tableJson) return { literalTerminals: [] };
  try {
    const table = JSON.parse(tableJson) as ParseTableJson;
    const literals = new Set<string>();
    let wordPattern: string | undefined;
    const wordToken = table.word_token === undefined ? undefined : Number(table.word_token);

    for (const entry of table.terminal_patterns ?? []) {
      const pattern = entry.pattern;
      if (!pattern) continue;
      if (pattern.type === "literal" && typeof pattern.value === "string") {
        literals.add(pattern.value);
      }
      if (wordToken !== undefined &&
        Number(entry.id) === wordToken &&
        pattern.type === "regex" &&
        typeof pattern.value === "string") {
        wordPattern = pattern.value;
      }
    }

    const keywordMap = table.keyword_map;
    if (Array.isArray(keywordMap)) {
      for (const item of keywordMap) {
        if (typeof item.k === "string") literals.add(item.k);
      }
    } else if (keywordMap && typeof keywordMap === "object") {
      for (const key of Object.keys(keywordMap)) literals.add(key);
    }

    return {
      literalTerminals: [...literals].filter(Boolean).sort(),
      wordPattern,
    };
  } catch {
    return { literalTerminals: [] };
  }
}

export function isValidWordForTable(info: ParseTableInfo, value: string): boolean {
  if (value.length === 0) return false;
  const pattern = info.wordPattern;
  if (!pattern) return /^[A-Za-z_][A-Za-z0-9_]*$/.test(value);

  for (const candidate of regexCandidates(pattern)) {
    try {
      if (new RegExp(candidate, "u").test(value)) return true;
    } catch {
      // Try the next representation; table regexes are allowed to be dialectal.
    }
  }
  return /^[A-Za-z_][A-Za-z0-9_]*$/.test(value);
}

function regexCandidates(pattern: string): string[] {
  const trimmed = pattern.trim();
  const unwrapped = trimmed.startsWith("/") && trimmed.lastIndexOf("/") > 0
    ? trimmed.slice(1, trimmed.lastIndexOf("/"))
    : trimmed;
  return [`^(?:${trimmed})$`, `^(?:${unwrapped})$`];
}
