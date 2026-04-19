export const DEFAULT_CMD_PAGE = 'overview'

export const CMD_NAV = [
  { id: 'overview', label: '概览' },
  { id: 'examples', label: '示例' },
  { id: 'interfaces', label: '公共接口' },
  { id: 'commands', label: '命令总览' },
  { id: 'generate', label: 'generate' },
  { id: 'parse-query', label: 'parse 与 query' },
  { id: 'check-fmt-test', label: 'check / fmt / test' },
  { id: 'io-reporter', label: 'I/O 与报告' },
  { id: 'best-practices', label: '最佳实践' },
]

const CMD_PAGE_IDS = new Set(CMD_NAV.map((item) => item.id))

export function normalizeCmdPage(page) {
  if (typeof page !== 'string') {
    return DEFAULT_CMD_PAGE
  }
  return CMD_PAGE_IDS.has(page) ? page : DEFAULT_CMD_PAGE
}

export function getCmdPageMeta(page) {
  return CMD_NAV.find((item) => item.id === normalizeCmdPage(page)) ?? CMD_NAV[0]
}