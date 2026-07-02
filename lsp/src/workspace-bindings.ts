import type {
  BindingDefinition,
  BindingDiagnostic,
  BindingReference,
} from "../../wasm/moonparse.js";

import type { BindingIndex } from "./binding-index.js";
import type { ExportedDefinition } from "./module-graph.js";
import type { WorkspaceFileEntry, WorkspaceIndex } from "./workspace-index.js";

export interface WorkspaceBindingOccurrence {
  uri: string;
  file: WorkspaceFileEntry;
  kind: "definition" | "reference";
  item: BindingDefinition | BindingReference;
}

export function isWorkspaceResolvableReference(reference: BindingReference): boolean {
  return reference.ns === "value" || reference.ns === "type";
}

export function exportedDefinitionForLocal(
  workspace: WorkspaceIndex,
  uri: string,
  definition: BindingDefinition,
): ExportedDefinition | null {
  return workspace.module(uri)?.exportedDefinitions.find(
    (exported) => exported.localId === definition.id,
  ) ?? null;
}

export function workspaceCandidatesForReference(
  workspace: WorkspaceIndex,
  uri: string,
  reference: BindingReference,
): ExportedDefinition[] {
  if (!isWorkspaceResolvableReference(reference)) return [];
  const module = workspace.module(uri);
  if (!module) return [];
  return workspace.findExportedDefinitions(
    module.packageId,
    reference.name,
    reference.ns,
  );
}

export function resolveWorkspaceReference(
  workspace: WorkspaceIndex,
  uri: string,
  reference: BindingReference,
): ExportedDefinition | null {
  const candidates = workspaceCandidatesForReference(workspace, uri, reference);
  return candidates.length === 1 ? candidates[0] : null;
}

export function workspaceOccurrencesForExported(
  workspace: WorkspaceIndex,
  exported: ExportedDefinition,
  includeDeclaration: boolean,
): WorkspaceBindingOccurrence[] {
  const occurrences: WorkspaceBindingOccurrence[] = [];
  const exportedFile = workspace.get(exported.uri);
  if (includeDeclaration && exportedFile) {
    const definition = exportedFile.bindingIndex?.getDefinition(exported.localId);
    if (definition) {
      occurrences.push({
        uri: exported.uri,
        file: exportedFile,
        kind: "definition",
        item: definition,
      });
    }
  }

  for (const [, file] of workspace.entries()) {
    if (file.packageId !== exported.packageId) continue;
    if (!file.bindingIndex) continue;
    for (const reference of file.bindingIndex.allReferences()) {
      if (!referenceMatchesExport(reference, exported)) continue;

      const localDefinition = file.bindingIndex.findDefinition(reference.id);
      if (localDefinition) {
        if (file.uri === exported.uri && localDefinition.id === exported.localId) {
          occurrences.push({
            uri: file.uri,
            file,
            kind: "reference",
            item: reference,
          });
        }
        continue;
      }

      const resolved = resolveWorkspaceReference(workspace, file.uri, reference);
      if (resolved?.globalId === exported.globalId) {
        occurrences.push({
          uri: file.uri,
          file,
          kind: "reference",
          item: reference,
        });
      }
    }
  }

  return sortUniqueOccurrences(occurrences);
}

export function bindingDiagnosticsWithWorkspace(
  uri: string,
  index: BindingIndex,
  workspace: WorkspaceIndex,
): BindingDiagnostic[] {
  const result: BindingDiagnostic[] = [];
  const seen = new Set<string>();

  for (const diagnostic of index.diagnostics()) {
    if (diagnostic.kind === "unresolved" && diagnostic.reference_id >= 0) {
      const reference = index.getReference(diagnostic.reference_id);
      if (reference) {
        const candidates = workspaceCandidatesForReference(workspace, uri, reference);
        if (candidates.length === 1) continue;
        if (candidates.length > 1) {
          addDiagnostic(result, seen, ambiguousDiagnostic(reference));
          continue;
        }
      }
    }
    addDiagnostic(result, seen, diagnostic);
  }

  for (const duplicate of exportedDuplicateDiagnostics(uri, workspace)) {
    addDiagnostic(result, seen, duplicate);
  }

  return result;
}

export function exportedDuplicateDiagnostics(
  uri: string,
  workspace: WorkspaceIndex,
): BindingDiagnostic[] {
  const module = workspace.module(uri);
  if (!module) return [];

  const result: BindingDiagnostic[] = [];
  for (const exported of module.exportedDefinitions) {
    const candidates = workspace.findExportedDefinitions(
      exported.packageId,
      exported.name,
      exported.ns,
    );
    if (candidates.length <= 1) continue;
    result.push({
      kind: "duplicate",
      message: `duplicate exported definition '${exported.name}'`,
      reference_id: -1,
      definition_id: exported.localId,
      start_byte: exported.startByte,
      end_byte: exported.endByte,
    });
  }
  return result;
}

function ambiguousDiagnostic(reference: BindingReference): BindingDiagnostic {
  return {
    kind: "ambiguous",
    message: `ambiguous reference '${reference.name}'`,
    reference_id: reference.id,
    definition_id: -1,
    start_byte: reference.start_byte,
    end_byte: reference.end_byte,
  };
}

function referenceMatchesExport(
  reference: BindingReference,
  exported: ExportedDefinition,
): boolean {
  return isWorkspaceResolvableReference(reference) &&
    reference.name === exported.name &&
    reference.ns === exported.ns;
}

function sortUniqueOccurrences(
  occurrences: WorkspaceBindingOccurrence[],
): WorkspaceBindingOccurrence[] {
  const sorted = occurrences.sort((a, b) =>
    a.uri.localeCompare(b.uri) ||
    a.item.start_byte - b.item.start_byte ||
    a.item.end_byte - b.item.end_byte);
  const seen = new Set<string>();
  const result: WorkspaceBindingOccurrence[] = [];
  for (const occurrence of sorted) {
    const key = [
      occurrence.uri,
      occurrence.item.start_byte,
      occurrence.item.end_byte,
      occurrence.item.name,
      occurrence.kind,
    ].join(":");
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(occurrence);
  }
  return result;
}

function addDiagnostic(
  result: BindingDiagnostic[],
  seen: Set<string>,
  diagnostic: BindingDiagnostic,
): void {
  const key = [
    diagnostic.kind,
    diagnostic.reference_id,
    diagnostic.definition_id,
    diagnostic.start_byte,
    diagnostic.end_byte,
  ].join(":");
  if (seen.has(key)) return;
  seen.add(key);
  result.push(diagnostic);
}
