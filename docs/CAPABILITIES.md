# 小橘子桌宠能力对齐

本文件记录桌宠与 Hermes / Codex 本体能力的对应关系，避免后续把小橘子做成“只能发文字的外壳”。

## 已接入桌宠

| 能力 | Hermes 小橘子 | Codex 入口 |
| --- | --- | --- |
| 文字聊天 | 优先走官方 TUI gateway JSON-RPC：`session.resume/create` + `prompt.submit`；必要时回退 `hermes chat -q --resume` | `codex exec` / `codex exec resume` |
| 图片输入 | TUI gateway 下逐张调用官方 `image.attach`；gateway 不可用时回退 `hermes chat --image <path>` | `codex exec --image <path>`，支持多张图片参数 |
| 本地文件 | 桌宠把文件路径写入消息，Hermes 用 file / terminal 工具读取 | 桌宠把文件路径写入消息，Codex 按本地路径读取 |
| 会话选择 | 读取 `~/.hermes/state.db` 并可继续/删除 Hermes 会话 | 读取 `~/.codex/state_5.sqlite` 并可继续/归档 Codex 会话 |
| 模型选择 | 读取 Hermes 模型缓存与 `~/.hermes/config.yaml` | 读取/更新 `~/.codex/config.toml` |
| 指令联想 | 从 Hermes command registry / fallback 命令生成 `/model`、`/skills`、`/sessions` 等联想 | Codex 常用工作指令联想 |
| 长期记忆 | 明确 `/记住` 直接写 Hermes USER；桌宠自动识别的候选先进入小橘子候选箱，确认后再写官方 memory | 暂不写 Codex memory，只同步本地 Codex 会话 |
| 窗口交互 | 聊天窗口打开时初始贴近小橘子；打开后聊天窗口和小橘子本体分离拖动，任何一方移动都不会持续带动另一方；聊天窗口使用 macOS 标准红黄绿按钮，支持关闭、最小化、缩放和拖拽调整大小，点击窗口外不会自动收起 | Codex 入口共用同一聊天窗口交互 |
| 聊天样式 | 聊天区使用微信/QQ 式左右气泡；主人消息在右侧绿色气泡，小橘子回复在左侧橘色圆角气泡，并带小尾巴、独立昵称、内边距、对齐、字体权重和强调色；小橘子气泡支持 `MorangeAssistantBubbleSticker` 透明贴纸素材，适合后续接入 xAI 生成的橘子风装饰；聊天正文纸感底色更不透明，减少桌面内容穿透影响阅读 | 同 Hermes 聊天样式 |
| Gateway 保底 | TUI gateway 是主链路；如果 `prompt.submit`/`slash_worker` 长时间无正文增量，会在工具记录里显示卡住阶段并回退官方 `hermes chat -q --resume`，继续使用当前 Hermes session/model | 不适用 |
| 实时状态 | 解析 Hermes 官方 TUI gateway 事件名，并保留 `hermes chat -q` 文本兼容镜像；工具/工作流事件进入聊天区顶部常驻折叠条，展开可看最近 80 条；正文按 Hermes 实时增量直接追加，工具事件不再打断正文输出；小橘子状态/动画刷新不再重放历史清空流式正文和工具记录 | 解析 Codex JSON 事件，工具事件同样进入折叠记录 |
| 转录保底 | Hermes 发送中的消息会写入桌宠本地 pending transcript；会话切换/重启时如果本地缓存比 Hermes 官方库更新，会先恢复本地内容，再继续跟随官方会话 | 暂不做额外本地转录缓存 |
| 语音 | 麦克风按钮走官方 `voice.toggle on` + `voice.record`，采用“点一下开始、说完再点一下停止”；启动录音前确认官方 voice mode 已开启，并对短暂 `idle` 状态做防抖，避免按钮刚变红就恢复；转写事件 `voice.transcript` 自动提交；朗读是桌宠本地 ON/OFF 开关，开关状态会持久化，ON 时 TUI gateway、quick fallback、PTY 三种回复完成路径都会调用官方 `voice.tts`，OFF 时只显示文字且立即停掉当前 TTS；朗读前会过滤括号里的舞台动作/状态旁白、工具/工作流记录、Hermes 官方事件、JSON-RPC 状态、命令日志和用户回显，聊天区仍显示完整原文；新回复开始朗读会先打断上一段 Hermes TTS 播放；本机 Edge TTS 当前使用 `zh-TW-HsiaoChenNeural`，`tts.edge.speed` 为 `1.08`；桌面朗读保留显式 `.mp3` 播放路径，默认平台投递仍可走 voice-compatible `.ogg`；已关闭 `voice.beep_enabled` 以避开 macOS PortAudio 提示音输出错误；App 启动和每日会自动清理 Hermes 自动生成的 `tts_*` 语音缓存，也支持菜单栏手动清理；输入框显示当前语音状态和官方错误诊断；语音状态切换时已避开动画层 `AVPlayerLooper` 快速重建导致的闪退 | 暂不接 Codex 语音 |
| 官方工具对齐 | 小橘子能力区表达“图像/视频/语音创作”等主人意图，不直接强制调用具体工具；“工具”按钮会扫描 `~/.hermes/hermes-agent/tools/*` 的 `registry.register(...)`，按真实 toolset 展示工具组和工具名；`image_generate`、`video_generate`、`text_to_speech` 等是否被调用由 Hermes 本体按上下文自动决定，桌宠只负责意图入口、状态镜像和权限 UI | 后续继续把更多 toolset 做成专用小橘子状态/配置面板，但不改变 Hermes 自动调度原则 |
| 桌宠可见性 | 小橘子本体窗口使用独立高层级并进入所有 Space；显示循环会守护窗口、透明度、动画层、播放器 player/current item/queue、播放状态和屏幕内位置，避免气泡仍在但本体莫名消失；停顿时不再暂停并回到透明首帧 | 不适用 |

## Hermes 本体能力

本机 `hermes tools list --platform cli` 显示 CLI 当前已启用：

- web、browser、terminal、file、code_execution、vision、image_gen、x_search、tts
- skills、todo、memory、session_search、clarify、delegation、cronjob、messaging、computer_use

桌宠侧的策略：

- 图片优先走官方 `image.attach`。
- 文本聊天优先走 Hermes 官方 `tui_gateway.entry`，不是伪协议。
- 语音优先走 Hermes 官方 `voice.toggle` / `voice.record` / `voice.tts`，不是桌宠自建 STT/TTS 协议。
- 文件不伪装上传，直接把真实本地路径交给 Hermes。
- 联网、浏览器、图像生成、视频生成、TTS、电脑操作、MCP、skills 等保持 Hermes 原生工具逻辑，由 Hermes 自己决定何时调用；小橘子只提供意图入口、能力可视化和状态镜像。
- 需要危险操作时继续走小橘子的权限确认弹窗；TUI gateway 下通过官方 `approval.respond` 返回 `once/session/always/deny`。
- 桌宠不修改 Hermes 官方记忆系统源码；`core/hermes_memory_inbox.md` 是小橘子桌宠自己的精选队列。
- 官方事件/权限/记忆对齐细节见 [HERMES_ALIGNMENT.md](HERMES_ALIGNMENT.md)。

## Codex 本体能力

本机 `codex --help` / `codex exec --help` 显示：

- CLI 支持 `--image` 图片输入。
- CLI 支持模型、profile、sandbox、approval、MCP、plugins、resume/fork 等。
- 顶层 Codex CLI 支持 `--search` web search；当前桌宠使用 `codex exec --json` 做对话同步，所以联网能力先保持为提示/本体能力，不强行塞进 exec JSON 通道。

桌宠侧的策略：

- 图片走 `codex exec --image` / `codex exec resume --image`。
- 文件作为路径交给 Codex 读取。
- 模型、智能程度、对话标题、归档继续同步本机 Codex。
- MCP、插件、web search、subagents 等能力先作为 Codex 本体能力展示，后续若 Codex exec JSON 通道稳定暴露对应参数，再做按钮直连。

## 后续优先级

1. 细化 Hermes 状态镜像：在折叠工具记录中继续补齐工具参数、当前文件、等待原因、失败原因、最近工具进度。
2. 完善权限策略：按工具/命令记住选择、授权规则管理、非敏感审计记录。
3. 完善长期记忆治理：候选去重、重要性分级、来源标记、任务完成记录和写入差异预览。
4. 完善模型错误诊断：把 Hermes 404/403/provider mismatch 转成中文可操作提示，并给出官方 `/model <model> --provider <provider>` 修复建议。
5. 完善附件队列：图片缩略图预览、拖拽附件、`image.attach` 已附加状态和失败重试。
6. 完善语音体验：电话模式、单条消息朗读、停止朗读、语音设置页、权限弹窗期间暂停收音。
7. 增加桌宠可见性诊断日志：记录窗口被拉回、动画层重建、播放器 item/queue/播放状态失效等自动修复原因。
8. Codex web search 的 JSON 通道直连。
9. MCP/工具列表实时读取并在 UI 中按启用状态展示。
10. 输出媒体保存：Hermes image_gen / TTS / video_gen 产物自动归档到小橘子工作区。
11. 正式 Release：签名、DMG、版本号、自动更新和发布校验。
