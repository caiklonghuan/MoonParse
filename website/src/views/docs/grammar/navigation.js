export const DEFAULT_GRAMMAR_PAGE = 'overview'

export const GRAMMAR_NAV = [
  { id: 'overview', label: '概览' },
  { id: 'usage-guide', label: '使用指南' },
  { id: 'examples', label: '示例' },
  { id: 'syntax-rules', label: '语法与规则' },
  { id: 'supported-features', label: '支持特性' },
  { id: 'interfaces', label: '公共接口' },
  { id: 'best-practices', label: '最佳实践' },
]

const GRAMMAR_PAGE_IDS = new Set(GRAMMAR_NAV.map((item) => item.id))

export function normalizeGrammarPage(page) {
  if (typeof page !== 'string') {
    return DEFAULT_GRAMMAR_PAGE
  }
  return GRAMMAR_PAGE_IDS.has(page) ? page : DEFAULT_GRAMMAR_PAGE
}

export function getGrammarPageMeta(page) {
  return GRAMMAR_NAV.find((item) => item.id === normalizeGrammarPage(page)) ?? GRAMMAR_NAV[0]
}