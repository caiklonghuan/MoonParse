export const DEFAULT_QUERY_PAGE = 'overview'

export const QUERY_NAV = [
  { id: 'overview', label: '概览' },
  { id: 'concepts', label: '核心概念' },
  { id: 'language', label: '查询语言' },
  { id: 'matching', label: '匹配与谓词' },
  { id: 'highlights-locals', label: '高亮与 Locals' },
  { id: 'interfaces', label: '公共接口' },
  { id: 'examples', label: '示例' },
]

const QUERY_PAGE_IDS = new Set(QUERY_NAV.map((item) => item.id))

export function normalizeQueryPage(page) {
  if (typeof page !== 'string') {
    return DEFAULT_QUERY_PAGE
  }
  return QUERY_PAGE_IDS.has(page) ? page : DEFAULT_QUERY_PAGE
}

export function getQueryPageMeta(page) {
  return QUERY_NAV.find((item) => item.id === normalizeQueryPage(page)) ?? QUERY_NAV[0]
}