export const DEFAULT_RUNTIME_PAGE = 'overview'

export const RUNTIME_NAV = [
  { id: 'overview', label: '概览' },
  { id: 'examples', label: '示例' },
  { id: 'interfaces', label: '公共接口' },
  { id: 'lexer', label: '词法引擎' },
  { id: 'parser', label: 'LR 解析器' },
  { id: 'glr', label: 'GLR 与并行' },
  { id: 'recovery', label: '错误恢复' },
  { id: 'incremental', label: '增量解析' },
  { id: 'concepts', label: '核心概念' },
]

const RUNTIME_PAGE_IDS = new Set(RUNTIME_NAV.map((item) => item.id))

export function normalizeRuntimePage(page) {
  if (typeof page !== 'string') {
    return DEFAULT_RUNTIME_PAGE
  }
  return RUNTIME_PAGE_IDS.has(page) ? page : DEFAULT_RUNTIME_PAGE
}

export function getRuntimePageMeta(page) {
  return RUNTIME_NAV.find((item) => item.id === normalizeRuntimePage(page)) ?? RUNTIME_NAV[0]
}