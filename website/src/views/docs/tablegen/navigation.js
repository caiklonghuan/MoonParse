export const DEFAULT_TABLEGEN_PAGE = 'overview'

export const TABLEGEN_NAV = [
  { id: 'overview', label: '概览' },
  { id: 'examples', label: '示例' },
  { id: 'conflicts', label: '冲突处理' },
  { id: 'serialization', label: '序列化' },
  { id: 'interfaces', label: '公共接口' },
  { id: 'best-practices', label: '最佳实践' },
  { id: 'concepts', label: '核心概念' },
  { id: 'pipeline-stages', label: '编译管线' },
]

const TABLEGEN_PAGE_IDS = new Set(TABLEGEN_NAV.map((item) => item.id))

export function normalizeTablegenPage(page) {
  if (typeof page !== 'string') {
    return DEFAULT_TABLEGEN_PAGE
  }
  return TABLEGEN_PAGE_IDS.has(page) ? page : DEFAULT_TABLEGEN_PAGE
}

export function getTablegenPageMeta(page) {
  return TABLEGEN_NAV.find((item) => item.id === normalizeTablegenPage(page)) ?? TABLEGEN_NAV[0]
}