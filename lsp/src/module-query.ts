import type {
  BindingGraph,
  CaptureResult,
} from "../../wasm/moonparse.js";

import type {
  QualifiedModuleReference,
  SourceModuleImport,
} from "./module-graph.js";

export interface ModuleQueryData {
  moduleName: string | null;
  publicExportRanges: Array<{ startByte: number; endByte: number }>;
  imports: SourceModuleImport[];
  qualifiedReferences: QualifiedModuleReference[];
}

interface NormalizedCapture {
  matchId: number;
  capture: string;
  startByte: number;
  endByte: number;
  text: string;
  order: number;
}

export function normalizeModuleCaptures(
  captures: CaptureResult[],
  sourceByteLength: number,
  graph: BindingGraph | null = null,
): ModuleQueryData {
  const normalized = captures.flatMap((capture, order) => {
    const startByte = Number(capture.start);
    const endByte = Number(capture.end);
    if (!Number.isInteger(startByte) || !Number.isInteger(endByte) ||
      startByte < 0 || endByte < startByte || endByte > sourceByteLength) {
      return [];
    }
    return [{
      matchId: Number.isInteger(capture.match_id) ? capture.match_id : -(order + 1),
      capture: capture.capture,
      startByte,
      endByte,
      text: normalizeCaptureText(capture.capture, capture.text),
      order,
    }];
  });

  const groups = new Map<number, NormalizedCapture[]>();
  for (const capture of normalized) {
    const group = groups.get(capture.matchId);
    if (group) group.push(capture);
    else groups.set(capture.matchId, [capture]);
  }

  const moduleNames: NormalizedCapture[] = [];
  const publicExports: NormalizedCapture[] = [];
  const imports: SourceModuleImport[] = [];
  const qualifiedReferences: QualifiedModuleReference[] = [];

  for (const group of groups.values()) {
    moduleNames.push(...group.filter((item) => item.capture === "module.name"));
    publicExports.push(...group.filter((item) => item.capture === "module.export"));

    const sources = group.filter((item) => item.capture === "import.source");
    const aliases = group.filter((item) => item.capture === "import.alias");
    if (sources.length === 1 && aliases.length <= 1 && sources[0].text) {
      imports.push({
        source: sources[0].text,
        alias: aliases[0]?.text || defaultImportAlias(sources[0].text),
        condition: "normal",
        sourceStartByte: sources[0].startByte,
        sourceEndByte: sources[0].endByte,
      });
    }

    const references = group.filter((item) => item.capture === "module.reference");
    const members = group.filter((item) =>
      item.capture === "module.member" ||
      item.capture === "module.member.value" ||
      item.capture === "module.member.type");
    if (references.length !== 1 || members.length !== 1 ||
      !references[0].text || !members[0].text) {
      continue;
    }
    const member = members[0];
    const namespace = member.capture === "module.member.type" ? "type" : "value";
    const matchingReferences = graph?.references.filter((reference) =>
      reference.start_byte === member.startByte &&
      reference.end_byte === member.endByte &&
      (reference.ns === namespace || reference.ns === "member")) ?? [];
    qualifiedReferences.push({
      alias: references[0].text,
      name: member.text,
      namespace,
      aliasStartByte: references[0].startByte,
      aliasEndByte: references[0].endByte,
      startByte: member.startByte,
      endByte: member.endByte,
      referenceId: matchingReferences.length === 1 ? matchingReferences[0].id : null,
    });
  }

  return {
    moduleName: moduleNames.length === 1 ? moduleNames[0].text : null,
    publicExportRanges: stableUniqueRanges(publicExports),
    imports: stableUniqueImports(imports),
    qualifiedReferences: stableUniqueQualifiedReferences(qualifiedReferences),
  };
}

function normalizeCaptureText(capture: string, text: string): string {
  let value = text.trim();
  if (value.length >= 2 &&
    ((value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'")))) {
    value = value.slice(1, -1);
  }
  if (capture === "import.alias" || capture === "module.reference") {
    value = value.replace(/^@/, "");
  }
  return value;
}

function defaultImportAlias(source: string): string {
  const parts = source.split("/").filter(Boolean);
  return parts.at(-1) ?? source;
}

function stableUniqueRanges(
  captures: NormalizedCapture[],
): Array<{ startByte: number; endByte: number }> {
  const sorted = captures.sort((a, b) =>
    a.startByte - b.startByte || a.endByte - b.endByte || a.order - b.order);
  const seen = new Set<string>();
  return sorted.flatMap((capture) => {
    const key = `${capture.startByte}:${capture.endByte}`;
    if (seen.has(key)) return [];
    seen.add(key);
    return [{ startByte: capture.startByte, endByte: capture.endByte }];
  });
}

function stableUniqueImports(imports: SourceModuleImport[]): SourceModuleImport[] {
  const seen = new Set<string>();
  return imports
    .sort((a, b) =>
      a.sourceStartByte - b.sourceStartByte ||
      a.sourceEndByte - b.sourceEndByte ||
      a.source.localeCompare(b.source) ||
      a.alias.localeCompare(b.alias))
    .filter((item) => {
      const key = `${item.source}\0${item.alias}\0${item.sourceStartByte}\0${item.sourceEndByte}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
}

function stableUniqueQualifiedReferences(
  references: QualifiedModuleReference[],
): QualifiedModuleReference[] {
  const seen = new Set<string>();
  return references
    .sort((a, b) =>
      a.startByte - b.startByte ||
      a.endByte - b.endByte ||
      a.aliasStartByte - b.aliasStartByte ||
      a.alias.localeCompare(b.alias))
    .filter((item) => {
      const key = [
        item.alias,
        item.name,
        item.namespace,
        item.aliasStartByte,
        item.aliasEndByte,
        item.startByte,
        item.endByte,
      ].join("\0");
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
}
