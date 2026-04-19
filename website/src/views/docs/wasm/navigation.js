export const DEFAULT_WASM_PAGE = 'overview'

export const WASM_NAV = [
  { id: 'overview', label: '概览' },
  { id: 'concepts', label: '边界模型' },
  { id: 'parser-tree', label: 'Parser 与 Tree' },
  { id: 'incremental-config', label: '增量与配置' },
  { id: 'cursor-query', label: 'Cursor、Query 与高亮' },
  { id: 'interfaces', label: '公共接口' },
  { id: 'examples', label: '示例' },
]

const WASM_PAGE_IDS = new Set(WASM_NAV.map((item) => item.id))

export function normalizeWasmPage(page) {
  if (typeof page !== 'string') {
    return DEFAULT_WASM_PAGE
  }
  return WASM_PAGE_IDS.has(page) ? page : DEFAULT_WASM_PAGE
}

export function getWasmPageMeta(page) {
  return WASM_NAV.find((item) => item.id === normalizeWasmPage(page)) ?? WASM_NAV[0]
}