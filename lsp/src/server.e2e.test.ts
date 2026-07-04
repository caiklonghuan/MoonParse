import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import {
  createMessageConnection,
  StreamMessageReader,
  StreamMessageWriter,
  type MessageConnection,
} from "vscode-jsonrpc/node.js";
import { afterEach, describe, expect, it } from "vitest";

interface Position {
  line: number;
  character: number;
}

interface Range {
  start: Position;
  end: Position;
}

interface Location {
  uri: string;
  range: Range;
}

interface Diagnostic {
  message: string;
  source?: string;
  range: Range;
}

interface WorkspaceEdit {
  changes?: Record<string, Array<{ range: Range; newText: string }>>;
}

interface PrepareRenameResult {
  range: Range;
  placeholder: string;
}

const lspRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = resolve(lspRoot, "..");
const serverPath = resolve(lspRoot, "dist/server.js");
const wasmPath = resolve(repoRoot, "wasm/moonparse.wasm");

let activeConnection: MessageConnection | null = null;
let activeServer: ChildProcessWithoutNullStreams | null = null;
let activeRoot: string | null = null;

afterEach(async () => {
  await stopServer();
  if (activeRoot) {
    await rm(activeRoot, { recursive: true, force: true });
    activeRoot = null;
  }
});

describe("MoonParse stdio LSP multi-module workspace", () => {
  it("navigates, finds references, and renames through a real moon.pkg import", async () => {
    const fixture = await createWorkspaceFixture();
    activeRoot = fixture.root;
    const { connection, ready, diagnostics, stderr } = startServer();
    const serverConfig = {
      wasmPath,
      debounceMs: 0,
      trace: "off",
      workspaceIndex: {
        enabled: true,
        maxFileBytes: 1_000_000,
        maxFiles: 100,
        parseTimeoutMs: 5_000,
        idleEvictMs: 300_000,
      },
    };

    await withTimeout(connection.sendRequest("initialize", {
      processId: null,
      clientInfo: { name: "moonparse-e2e", version: "1" },
      rootUri: fixture.rootUri,
      workspaceFolders: [{ uri: fixture.rootUri, name: "fixture" }],
      capabilities: {},
      initializationOptions: serverConfig,
    }), 20_000, () => `initialize timed out\n${stderr()}`);
    connection.sendNotification("initialized", {});
    await withTimeout(ready, 30_000, () => `server did not become ready\n${stderr()}`);

    const importerDiagnostics = waitForDiagnostics(diagnostics, fixture.importerUri);
    const exporterDiagnostics = waitForDiagnostics(diagnostics, fixture.exporterUri);
    const otherDiagnostics = waitForDiagnostics(diagnostics, fixture.otherUri);
    openDocument(connection, fixture.importerUri, fixture.importerText);
    openDocument(connection, fixture.exporterUri, fixture.exporterText);
    openDocument(connection, fixture.otherUri, fixture.otherText);

    expect(await withTimeout(exporterDiagnostics, 10_000, stderr)).toEqual([]);
    expect(await withTimeout(importerDiagnostics, 10_000, stderr)).toEqual([]);
    await withTimeout(otherDiagnostics, 10_000, stderr);

    const importerPosition = positionOf(fixture.importerText, "greet", 1);
    const exporterPosition = positionOf(fixture.exporterText, "greet", 1);
    const definition = await connection.sendRequest<Location | null>(
      "textDocument/definition",
      { textDocument: { uri: fixture.importerUri }, position: importerPosition },
    );
    expect(definition).toEqual({
      uri: fixture.exporterUri,
      range: rangeOf(fixture.exporterText, "greet"),
    });

    const references = await connection.sendRequest<Location[]>(
      "textDocument/references",
      {
        textDocument: { uri: fixture.exporterUri },
        position: exporterPosition,
        context: { includeDeclaration: true },
      },
    );
    expect(references).toEqual(expect.arrayContaining([
      { uri: fixture.exporterUri, range: rangeOf(fixture.exporterText, "greet") },
      { uri: fixture.importerUri, range: rangeOf(fixture.importerText, "greet") },
    ]));
    expect(references).toHaveLength(2);
    expect(references.some((location) => location.uri === fixture.otherUri)).toBe(false);

    const prepared = await connection.sendRequest<PrepareRenameResult | null>(
      "textDocument/prepareRename",
      { textDocument: { uri: fixture.importerUri }, position: importerPosition },
    );
    expect(prepared).toEqual({
      range: rangeOf(fixture.importerText, "greet"),
      placeholder: "greet",
    });

    const renamed = await connection.sendRequest<WorkspaceEdit | null>(
      "textDocument/rename",
      {
        textDocument: { uri: fixture.exporterUri },
        position: exporterPosition,
        newName: "welcome",
      },
    );
    expect(renamed?.changes).toEqual({
      [fixture.importerUri]: [{
        range: rangeOf(fixture.importerText, "greet"),
        newText: "welcome",
      }],
      [fixture.exporterUri]: [{
        range: rangeOf(fixture.exporterText, "greet"),
        newText: "welcome",
      }],
    });
    expect(renamed?.changes?.[fixture.moonPkgUri]).toBeUndefined();
    expect(renamed?.changes?.[fixture.importerUri]?.some((edit) =>
      edit.range.start.character === positionOf(fixture.importerText, "@dep").character))
      .toBe(false);
  }, 60_000);
});

async function createWorkspaceFixture() {
  const root = await mkdtemp(join(tmpdir(), "moonparse-lsp-e2e-"));
  const appRoot = join(root, "app");
  const depRoot = join(root, "dep");
  const otherRoot = join(root, "other");
  const appSource = join(appRoot, "src");
  const depSource = join(depRoot, "lib");
  const otherSource = join(otherRoot, "src");
  await Promise.all([
    mkdir(appSource, { recursive: true }),
    mkdir(depSource, { recursive: true }),
    mkdir(otherSource, { recursive: true }),
  ]);
  await Promise.all([
    writeFile(join(root, "moon.work"), JSON.stringify({
      members: ["app", "dep", "other"],
    }), "utf8"),
    writeFile(join(appRoot, "moon.mod.json"), '{"name":"acme/app"}', "utf8"),
    writeFile(join(depRoot, "moon.mod.json"), '{"name":"acme/dep"}', "utf8"),
    writeFile(join(otherRoot, "moon.mod.json"), '{"name":"acme/other"}', "utf8"),
  ]);

  const importerPath = join(appSource, "main.mbt");
  const exporterPath = join(depSource, "api.mbt");
  const otherPath = join(otherSource, "main.mbt");
  const moonPkgPath = join(appSource, "moon.pkg");
  const importerText = "fn main() { @dep.greet() }\n";
  const exporterText = "pub fn greet() -> Int { 1 }\n";
  const otherText = "fn unrelated() { greet() }\n";
  await Promise.all([
    writeFile(moonPkgPath, 'import { "acme/dep/lib" @dep }\n', "utf8"),
    writeFile(importerPath, importerText, "utf8"),
    writeFile(exporterPath, exporterText, "utf8"),
    writeFile(otherPath, otherText, "utf8"),
  ]);

  return {
    root,
    rootUri: pathToFileURL(root).href,
    importerUri: pathToFileURL(importerPath).href,
    exporterUri: pathToFileURL(exporterPath).href,
    otherUri: pathToFileURL(otherPath).href,
    moonPkgUri: pathToFileURL(moonPkgPath).href,
    importerText,
    exporterText,
    otherText,
  };
}

function startServer() {
  const child = spawn(process.execPath, [serverPath, "--stdio"], {
    cwd: lspRoot,
    stdio: ["pipe", "pipe", "pipe"],
    windowsHide: true,
  });
  activeServer = child;
  let stderrText = "";
  let serverLog = "";
  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (chunk: string) => {
    stderrText += chunk;
  });

  const connection = createMessageConnection(
    new StreamMessageReader(child.stdout),
    new StreamMessageWriter(child.stdin),
  );
  activeConnection = connection;
  const readyDeferred = deferred<void>();
  const diagnostics = new Map<string, DiagnosticWaiter[]>();
  connection.onNotification("telemetry/event", (event: { event?: string }) => {
    if (event?.event === "server.initialized") readyDeferred.resolve();
  });
  connection.onNotification("window/logMessage", (params: { message?: string }) => {
    if (params?.message) serverLog += `${params.message}\n`;
  });
  connection.onNotification("$/logTrace", (params: { message?: string; verbose?: string }) => {
    if (params?.message) serverLog += `${params.message}${params.verbose ?? ""}\n`;
  });
  connection.onNotification("textDocument/publishDiagnostics", (params: {
    uri: string;
    diagnostics: Diagnostic[];
  }) => {
    const waiters = diagnostics.get(params.uri);
    if (!waiters?.length) return;
    diagnostics.delete(params.uri);
    for (const waiter of waiters) waiter.resolve(params.diagnostics);
  });
  child.once("exit", (code, signal) => {
    readyDeferred.reject(new Error(
      `LSP server exited before ready: code=${code} signal=${signal}\n${stderrText}`,
    ));
  });
  connection.listen();
  return {
    connection,
    ready: readyDeferred.promise,
    diagnostics,
    stderr: () => `${stderrText}${serverLog}`,
  };
}

interface DiagnosticWaiter {
  resolve: (diagnostics: Diagnostic[]) => void;
}

function waitForDiagnostics(
  waiters: Map<string, DiagnosticWaiter[]>,
  uri: string,
): Promise<Diagnostic[]> {
  return new Promise((resolve) => {
    const existing = waiters.get(uri) ?? [];
    existing.push({ resolve });
    waiters.set(uri, existing);
  });
}

function openDocument(connection: MessageConnection, uri: string, text: string): void {
  connection.sendNotification("textDocument/didOpen", {
    textDocument: { uri, languageId: "moonbit", version: 1, text },
  });
}

function positionOf(text: string, needle: string, inside = 0): Position {
  const offset = text.indexOf(needle);
  if (offset < 0) throw new Error(`needle not found: ${needle}`);
  const before = text.slice(0, offset + inside);
  const lines = before.split("\n");
  return { line: lines.length - 1, character: lines.at(-1)?.length ?? 0 };
}

function rangeOf(text: string, needle: string): Range {
  const start = positionOf(text, needle);
  return {
    start,
    end: { line: start.line, character: start.character + needle.length },
  };
}

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

async function withTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number,
  detail: () => string,
): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<T>((_, reject) => {
        timer = setTimeout(() => reject(new Error(detail())), timeoutMs);
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

async function stopServer(): Promise<void> {
  const connection = activeConnection;
  const child = activeServer;
  activeConnection = null;
  activeServer = null;
  if (!connection || !child) return;
  try {
    if (child.exitCode == null) {
      await withTimeout(connection.sendRequest("shutdown"), 5_000, () => "shutdown timeout");
      connection.sendNotification("exit");
    }
  } catch {
    // The fallback below owns process cleanup.
  } finally {
    connection.dispose();
  }
  if (child.exitCode == null) {
    await Promise.race([
      new Promise<void>((resolveExit) => child.once("exit", () => resolveExit())),
      new Promise<void>((resolveTimeout) => setTimeout(resolveTimeout, 2_000)),
    ]);
  }
  if (child.exitCode == null) child.kill();
}
