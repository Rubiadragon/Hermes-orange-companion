# 小橘子桌宠记忆策略

小橘子桌宠是 Hermes 的桌面 UI/皮套，不替换 Hermes 官方 memory 系统，也不修改 Hermes 官方源码。桌宠只负责把与桌宠体验相关的长期信息精选出来，放到主人能确认的候选箱。

## 边界

- Hermes 官方长期记忆仍然在 `~/.hermes/memories/USER.md` 和 `~/.hermes/memories/MEMORY.md`。
- 小橘子的候选箱在工作区：`core/hermes_memory_inbox.md`。
- 普通聊天不会直接污染 Hermes 官方 memory。
- 主人明确说 `/记住`、`请记住`、`帮我记住` 时，桌宠会按主人的明确指令直接写入 Hermes USER memory，并同步记录到候选箱。

## 自动候选

桌宠会从 Hermes 对话里识别这些候选：

- 主人偏好：例如“我喜欢”“我不喜欢”“以后不要”“我习惯”。
- 项目事实：例如小橘子桌宠、Hermes、Codex、工作区、模型、会话、权限、UI 的长期规则。
- 提醒/后续事项：进入当日备忘录，不直接写长期 memory。
- 任务完成记录：进入当日备忘录，用来形成工作日志。

USER/MEMORY 类候选默认状态为“待确认”。主人在桌宠聊天面板点“候选”，再选择“写入”或“忽略”。

## 写入规则

- `USER` 候选确认后写入 `~/.hermes/memories/USER.md`。
- `MEMORY` 候选确认后写入 `~/.hermes/memories/MEMORY.md`。
- `DAILY` 候选只写入当天小橘子备忘录。
- 如果写入后超过 Hermes 官方 memory 容量限制，桌宠不强行写入，只记录到当天工作日志。

## UI

聊天面板 Hermes 工具条有“候选”入口：

- 查看待确认候选。
- 按 `全部` / `USER` / `MEMORY` / `DAILY` 筛选。
- 在候选箱里编辑内容，再写入 Hermes 官方 memory。
- 单条写入 Hermes 官方 memory。
- 单条忽略。
- 批量写入当前筛选结果。
- 批量忽略当前筛选结果。
- 打开候选箱 `.md`。
- 打开 Hermes 官方 memory 目录。

后续可以继续加：候选来源跳转、与 TUI gateway `on_memory_write` 事件的实时双向同步。
