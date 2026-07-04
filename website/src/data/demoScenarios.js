import { BUILTIN_LANGUAGE_PRESETS } from './languagePresets.js'

function preset(id) {
  const value = BUILTIN_LANGUAGE_PRESETS.find((item) => item.id === id)
  if (!value) throw new Error(`Missing built-in preset: ${id}`)
  return value
}

function packProject(id, selectedPath = 'language-pack.json') {
  const value = preset(id)
  return {
    files: { ...(value.languagePackFiles ?? {}) },
    selectedPath,
    mode: 'source',
    bundleJson: null,
  }
}

function grammarState(id, overrides = {}) {
  const value = preset(id)
  return {
    v: 2,
    kind: 'grammar',
    grammar: value.grammar ?? '',
    source: value.source ?? '',
    query: value.query ?? '',
    highlight: value.highlightQuery ?? '',
    queryMode: 'query',
    queryModePatterns: {
      locals: '',
      bindings: '',
      folding: '',
    },
    incrementalTraceEnabled: false,
    previewTab: 'source',
    packBottomTab: 'diagnostics',
    outputTab: 'sexp',
    project: null,
    ...overrides,
  }
}

const jsonPreset = preset('json')
const pythonPreset = preset('python')
const moonbitPreset = preset('moonbit')

export const DEMO_SCENARIOS = [
  {
    id: 'pack-main-flow',
    name: 'Pack 主流程',
    description: '打开 JSON Language Pack，查看 Manifest、Corpus 和 Bundle 主流程。',
    state: {
      v: 2,
      kind: 'source-pack',
      grammar: jsonPreset.grammar ?? '',
      source: jsonPreset.source ?? '',
      query: jsonPreset.query ?? '(pair (jstring) @property ":" (value) @value)',
      highlight: jsonPreset.highlightQuery ?? '',
      queryMode: 'query',
      queryModePatterns: { locals: '', bindings: '', folding: '' },
      incrementalTraceEnabled: false,
      previewTab: 'source',
      packBottomTab: 'corpus',
      outputTab: 'sexp',
      project: packProject('json'),
    },
  },
  {
    id: 'query-debug',
    name: 'Query 调试',
    description: '展示普通 Query 的 match_id 分组和 capture 定位。',
    state: grammarState('json', {
      query: '(pair (jstring) @property ":" (value) @value)\n(number) @number',
      previewTab: 'query',
    }),
  },
  {
    id: 'lint-quick-fix',
    name: 'Lint Quick Fix',
    description: 'Run configured JSON lint rules and replace -0 with 0.',
    state: {
      v: 2,
      kind: 'source-pack',
      grammar: jsonPreset.grammar ?? '',
      source: '{"": -0, "ok": 1}',
      query: '',
      highlight: jsonPreset.highlightQuery ?? '',
      queryMode: 'query',
      queryModePatterns: { locals: '', bindings: '', folding: '' },
      incrementalTraceEnabled: false,
      previewTab: 'source',
      packBottomTab: 'lint',
      outputTab: 'sexp',
      project: packProject('json'),
    },
  },
  {
    id: 'binding-graph',
    name: 'Binding Graph',
    description: '运行 Bindings Query 并展示 definition/reference 解析图。',
    state: grammarState('moonbit', {
      source: moonbitPreset.source ?? '',
      query: '',
      queryMode: 'bindings',
      queryModePatterns: {
        locals: moonbitPreset.localsQuery ?? '',
        bindings: moonbitPreset.bindingsQuery ?? '',
        folding: moonbitPreset.foldingQuery ?? '',
      },
      previewTab: 'query',
    }),
  },
  {
    id: 'lr-conflict',
    name: 'LR 冲突路径',
    description: '构造未消解表达式冲突，直接查看候选 action 和状态路径。',
    state: grammarState('json', {
      grammar: [
        'start expr',
        'extras [/[ \\t\\n\\r]+/]',
        'rule expr: expr "+" expr | expr "*" expr | number',
        'rule number: /[0-9]+/',
      ].join('\n'),
      source: '1 + 2 * 3',
      query: '(number) @number',
      highlight: '(number) @number\n"+" @operator\n"*" @operator',
      previewTab: 'output',
      outputTab: 'diagnostics',
    }),
  },
  {
    id: 'incremental-trace',
    name: '增量 Trace',
    description: '默认开启增量 Trace；编辑源码后查看复用区间和耗时基准。',
    state: grammarState('python', {
      source: pythonPreset.source ?? '',
      query: pythonPreset.query ?? '',
      highlight: pythonPreset.highlightQuery ?? '',
      incrementalTraceEnabled: true,
      previewTab: 'output',
      outputTab: 'incremental',
    }),
  },
]

export function findDemoScenario(id) {
  return DEMO_SCENARIOS.find((scenario) => scenario.id === id) ?? null
}
