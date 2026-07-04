const STATUS_RANK = { ambiguous: 0, dynamic: 1, declared: 2, warn: 3, legacy: 4 }

function numberOr(value, fallback = -1) {
  const number = Number(value)
  return Number.isFinite(number) ? number : fallback
}

export function conflictStatus(diagnostic) {
  const severity = String(diagnostic?.severity ?? '').toLowerCase()
  const resolution = String(diagnostic?.resolution?.kind ?? '').toLowerCase()
  if (severity.startsWith('ambiguous') || resolution === 'ambiguous-glr') return 'ambiguous'
  if (severity.startsWith('dynamic') || resolution === 'dynamic-precedence') return 'dynamic'
  if (severity.startsWith('declared') || resolution === 'declared-glr') return 'declared'
  if (severity.startsWith('warn') || resolution === 'resolved') return 'warn'
  return 'legacy'
}

function normalizeAction(action, index) {
  const kind = String(action?.kind ?? 'unknown')
  return {
    ...action,
    index: numberOr(action?.index, index),
    kind,
    display: String(action?.display ?? kind),
    body: Array.isArray(action?.body) ? action.body.map(String) : [],
  }
}

export function normalizeConflictDiagnostic(raw, index = 0) {
  if (typeof raw === 'string') {
    return {
      key: `legacy:${index}`,
      severity: raw,
      status: 'legacy',
      state: -1,
      terminal: -1,
      terminalName: '?',
      message: raw,
      actions: [],
      items: [],
      statePath: [],
      branches: [],
      branchByAction: new Map(),
      resolution: null,
      extended: false,
    }
  }
  const diagnostic = raw && typeof raw === 'object' ? raw : {}
  const actions = (Array.isArray(diagnostic.actions) ? diagnostic.actions : [])
    .map(normalizeAction)
  const branches = (Array.isArray(diagnostic.branches) ? diagnostic.branches : []).map((branch) => ({
    ...branch,
    actionIndex: numberOr(branch?.actionIndex),
    outcome: String(branch?.outcome ?? 'unknown'),
    message: String(branch?.message ?? ''),
  }))
  const normalized = {
    ...diagnostic,
    key: `conflict:${numberOr(diagnostic.state)}:${numberOr(diagnostic.terminal)}:${index}`,
    severity: String(diagnostic.severity ?? ''),
    state: numberOr(diagnostic.state),
    terminal: numberOr(diagnostic.terminal),
    terminalName: String(diagnostic.terminalName ?? diagnostic.terminal ?? '?'),
    message: String(diagnostic.message ?? diagnostic.severity ?? ''),
    actions,
    items: Array.isArray(diagnostic.items) ? diagnostic.items : [],
    statePath: Array.isArray(diagnostic.statePath) ? diagnostic.statePath : [],
    branches,
    resolution: diagnostic.resolution && typeof diagnostic.resolution === 'object'
      ? diagnostic.resolution
      : null,
    extended: Array.isArray(diagnostic.actions) && diagnostic.resolution != null,
  }
  normalized.status = conflictStatus(normalized)
  normalized.branchByAction = new Map(branches.map((branch) => [branch.actionIndex, branch]))
  return normalized
}

export function normalizeConflictDiagnostics(diagnostics = []) {
  return (Array.isArray(diagnostics) ? diagnostics : [])
    .map(normalizeConflictDiagnostic)
    .map((diagnostic, index) => ({ diagnostic, index }))
    .sort((left, right) =>
      left.diagnostic.state - right.diagnostic.state ||
      left.diagnostic.terminal - right.diagnostic.terminal ||
      (STATUS_RANK[left.diagnostic.status] ?? 99) - (STATUS_RANK[right.diagnostic.status] ?? 99) ||
      left.index - right.index)
    .map((entry) => entry.diagnostic)
}

export function conflictActionTitle(action) {
  if (action?.kind === 'shift') return `Shift to state ${action.targetState}`
  if (action?.kind === 'reduce') return `Reduce #${action.productionId} · ${action.ruleName ?? action.head ?? '?'}`
  if (action?.kind === 'accept') return 'Accept'
  return action?.display ?? 'Unknown action'
}
