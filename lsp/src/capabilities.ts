import {
  TextDocumentSyncKind,
  type ServerCapabilities,
} from "vscode-languageserver";

import { TOKEN_MODIFIERS, TOKEN_TYPES } from "./semantic-tokens.js";

export function createServerCapabilities(): ServerCapabilities {
  return {
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
    documentHighlightProvider: true,
    foldingRangeProvider: true,
    hoverProvider: true,
    definitionProvider: true,
    referencesProvider: true,
    renameProvider: {
      prepareProvider: true,
    },
    completionProvider: {
      triggerCharacters: [".", "@"],
    },
    documentFormattingProvider: true,
    documentRangeFormattingProvider: true,
    codeActionProvider: true,
  };
}
