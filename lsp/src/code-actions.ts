// textDocument/codeAction — Quick Fix 代码动作

import {
  CodeActionKind,
  type CodeAction,
  type Diagnostic,
  type WorkspaceEdit,
  type TextEdit,
  Range,
} from "vscode-languageserver";
import type { DocumentEntry } from "./document-manager.js";
import type { SymbolIndex } from "./symbol-index.js";
import type { LintDiagnosticData } from "./diagnostics.js";

// ── 主入口 ──

export function getCodeActions(
  entry: DocumentEntry,
  diagnostics: Diagnostic[],
  _symbolIndex: SymbolIndex,
): CodeAction[] {
  const actions: CodeAction[] = [];

  for (const diag of diagnostics) {
    const lintData = readLintDiagnosticData(diag.data);
    if (lintData) {
      if (
        lintData.documentVersion === entry.version &&
        lintData.fix &&
        isValidRange(entry, lintData.fix.edit.range)
      ) {
        actions.push({
          title: lintData.fix.title,
          kind: CodeActionKind.QuickFix,
          diagnostics: [diag],
          isPreferred: true,
          edit: {
            changes: {
              [entry.uri]: [{
                range: lintData.fix.edit.range,
                newText: lintData.fix.edit.newText,
              }],
            },
          },
        });
      }
      continue;
    }
    const msg = diag.message;

    // Missing rule — 提供 "Create rule"
    const missingRule = matchMissingRule(msg);
    if (missingRule) {
      actions.push(createRuleAction(entry, missingRule, diag));
      continue;
    }

    // Missing token — 提供 "Insert <token>"
    const missingToken = matchMissingToken(msg);
    if (missingToken) {
      actions.push(insertTokenAction(entry, missingToken, diag));
      continue;
    }

    // Unclosed construct — 提供 "Insert <delim>"
    const unclosed = matchUnclosed(msg);
    if (unclosed) {
      actions.push(insertTokenAction(entry, unclosed, diag));
      continue;
    }

    // Unexpected token — 提供 "Remove"
    const unexpected = matchUnexpected(msg);
    if (unexpected) {
      actions.push(removeTokenAction(entry, diag));
      // 也提供通用占位
      continue;
    }

    // 冲突诊断 — 提供占位
    if (msg.includes("conflict") || msg.includes("Conflict")) {
      actions.push({
        title: "View conflict detail",
        kind: CodeActionKind.QuickFix,
        diagnostics: [diag],
        edit: voidEdit(),
      });
      continue;
    }
  }

  // 未使用 rule 检测
  if (entry.languageId === "__dsl__") {
    for (const diag of diagnostics) {
      const unusedRule = matchUnusedRule(diag.message);
      if (unusedRule) {
        actions.push(removeRuleAction(entry, unusedRule, diag));
        actions.push(deprecateRuleAction(unusedRule, diag));
      }
    }
  }

  return actions;
}

function readLintDiagnosticData(value: unknown): LintDiagnosticData | null {
  if (!value || typeof value !== "object") return null;
  const data = value as Partial<LintDiagnosticData>;
  if (
    data.kind !== "moonparse-lint" ||
    typeof data.ruleId !== "string" ||
    !Number.isInteger(data.documentVersion)
  ) return null;
  return data as LintDiagnosticData;
}

function isValidRange(entry: DocumentEntry, range: Diagnostic["range"]): boolean {
  const positions = [range.start, range.end];
  for (const position of positions) {
    if (!Number.isInteger(position.line) || !Number.isInteger(position.character)) return false;
    if (position.line < 0 || position.line >= entry.lineOffsets.length || position.character < 0) return false;
    const lineStart = entry.lineOffsets[position.line];
    const lineEnd = position.line + 1 < entry.lineOffsets.length
      ? Math.max(lineStart, entry.lineOffsets[position.line + 1] - 1)
      : entry.text.length;
    if (position.character > lineEnd - lineStart) return false;
  }
  return range.start.line < range.end.line ||
    (range.start.line === range.end.line && range.start.character <= range.end.character);
}

// ── Quick Fix 生成 ──

// "Create rule <name>"
function createRuleAction(
  entry: DocumentEntry,
  name: string,
  diag: Diagnostic,
): CodeAction {
  const pos = endOfFile(entry);
  return {
    title: `Create rule '${name}'`,
    kind: CodeActionKind.QuickFix,
    diagnostics: [diag],
    edit: {
      changes: {
        [entry.uri]: [
          {
            range: Range.create(pos, pos),
            newText: `\n\nrule ${name}: `,
          },
        ],
      },
    },
  };
}

// "Insert '<token>'"
function insertTokenAction(
  entry: DocumentEntry,
  token: string,
  diag: Diagnostic,
): CodeAction {
  return {
    title: `Insert '${token}'`,
    kind: CodeActionKind.QuickFix,
    diagnostics: [diag],
    edit: {
      changes: {
        [entry.uri]: [
          {
            range: diag.range,
            newText: token,
          },
        ],
      },
    },
  };
}

// "Remove unexpected token"
function removeTokenAction(
  entry: DocumentEntry,
  diag: Diagnostic,
): CodeAction {
  return {
    title: "Remove unexpected token",
    kind: CodeActionKind.QuickFix,
    diagnostics: [diag],
    edit: {
      changes: {
        [entry.uri]: [
          {
            range: diag.range,
            newText: "",
          },
        ],
      },
    },
  };
}

// "Remove rule <name>"
function removeRuleAction(
  entry: DocumentEntry,
  name: string,
  diag: Diagnostic,
): CodeAction {
  return {
    title: `Remove rule '${name}'`,
    kind: CodeActionKind.QuickFix,
    diagnostics: [diag],
    isPreferred: false,
    edit: voidEdit(),
  };
}

// "Mark deprecated"
function deprecateRuleAction(
  name: string,
  diag: Diagnostic,
): CodeAction {
  return {
    title: `Mark '${name}' as deprecated`,
    kind: CodeActionKind.Refactor,
    diagnostics: [diag],
    edit: voidEdit(),
  };
}

// ── 消息模式匹配 ──

function matchMissingRule(msg: string): string | null {
  // Missing '<name>' where name looks like a rule (not a single delimiter)
  const m = msg.match(/^Missing '(\w[\w._-]*)'$/);
  if (!m) return null;
  const name = m[1];
  // 排除单字符分隔符 token
  if (/^[{}()[\];,:.<>+\-*/%&=|^!~?#@]$/.test(name)) return null;
  return name;
}

function matchMissingToken(msg: string): string | null {
  // Missing '<token>' — 单字符或分隔符
  const m = msg.match(/^Missing '(.+)'$/);
  if (!m) return null;
  const token = m[1];
  // 仅对短 token 提供自动插入
  if (token.length <= 3) return token;
  return null;
}

function matchUnclosed(msg: string): string | null {
  // Unclosed construct — missing '<delim>'
  const m = msg.match(/missing '(.+)'$/);
  if (!m) return null;
  return m[1];
}

function matchUnexpected(msg: string): string | null {
  if (msg.startsWith("Unexpected token")) return "unexpected";
  return null;
}

function matchUnusedRule(msg: string): string | null {
  // 这条需要 diagnostic 的 message 包含 rule name
  // 当前 diagnostic 不生成 unused rule 消息，预留接口
  const m = msg.match(/^Unused rule '(\w[\w._-]*)'$/);
  return m ? m[1] : null;
}

// ── 辅助 ──

function endOfFile(entry: DocumentEntry): { line: number; character: number } {
  const lines = entry.text.split("\n");
  return { line: Math.max(lines.length - 1, 0), character: lines[lines.length - 1]?.length ?? 0 };
}

function voidEdit(): WorkspaceEdit {
  return { changes: {} };
}
