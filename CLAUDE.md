# MoonParse 自主开发 Agent 配置

## 启动时
- 读取 `todo/` 目录下所有 `.md` 文件
- 按文件名排序，逐个执行
- 每个文件 = 一个独立任务块
- 除非同一任务块内部有依赖，否则不允许合并或跳过

## 工作流程（4 阶段）

### Phase 1: Planner — 分析任务
- 解析任务块内的依赖关系
- 输出 plan（不写代码）
- 格式：`1. [任务] 依赖：无 | 预估耗时：X min`

### Phase 2: Coder + Debugger — 增量执行
- 按 plan 顺序，改最小代码
- 每步验证：moon build + moon test，或 npx tsc --noEmit + npx vitest run
- 失败重试 ≤ 3 次，超过则标记 BLOCKED，停止

### Phase 3: Reviewer — 集成检查
- 全量测试 moon test + vitest
- 格式/lint 检查
- 覆盖率：若本次改动文件 < 80% 覆盖，补充测试
- 输出 review 报告 + APPROVED / REQUIRES_CHANGES / REJECTED

### Phase 4: Delivery — 提交
- 列出改动文件 + diff 摘要
- git commit + 规范 commit message
- 更新 PROJECT_STATUS.md 中相关条目

## 开发规则
- MoonBit 用 moon build && moon test 验证
- TypeScript 用 npx tsc --noEmit && npx vitest run 验证
- 全部通过才能 commit
- 不改 server.ts 对外 API 除非必要
- 不改 .grammar DSL 语法
- 修改前先读文件确认当前状态

## 验证命令
```bash
cd c:/Users/cky/project/moon/MoonParse
moon build && moon test
cd lsp && npx tsc --noEmit && npx vitest run
```

## 禁止事项
- 不修改 todo/ 目录下的任务文件本身
- 不跳过测试或伪造通过结果
- 未获确认不引入新第三方依赖
- 不无限循环修复：3 次失败即标记 BLOCKED
