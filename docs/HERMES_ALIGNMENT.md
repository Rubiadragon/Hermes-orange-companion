# Hermes 官方能力对齐记录

小橘子桌宠主要维护桌面 UI/皮套层，尽量不改 `~/.hermes/hermes-agent` 官方源码。若为了本机 macOS 语音/桌面宿主适配做了小补丁，会在本文单独记录，方便后续跟随 Hermes 官方更新时核对。

## 桌面 UI

桌宠当前状态：

- 小橘子本体窗口和聊天窗口是两个独立窗口。聊天窗口打开时只做一次贴近小橘子的初始定位，之后小橘子走路/拖动不会持续带动聊天窗口；聊天窗口被主人手动拖动后也只保存自己的位置。
- 聊天窗口现在使用 macOS 标准窗口能力：红色关闭按钮会走小橘子 `closePopover()` 状态恢复逻辑，黄色按钮最小化，绿色按钮缩放/放大，窗口边缘可拖拽调整大小；点击窗口外不会自动收起。
- 聊天正文按发言者区分视觉层级：主人消息使用右侧绿色聊天气泡，小橘子回复使用左侧橘色圆角聊天气泡。两者使用自定义 `NSTextBlock` 绘制气泡底色、描边和小尾巴，并使用独立昵称、内边距、对齐、字体权重和强调色。小橘子气泡预留 `MorangeAssistantBubbleSticker` 素材插槽；有 xAI 生成的透明 PNG 贴纸时自动叠加，没有素材时使用代码绘制的橘瓣点缀兜底。
- 聊天正文区域使用更实的纸感底色，减少桌面或其他窗口内容穿透，保留手账感和小橘子化风格，但优先保证可读性。
- 小橘子本体窗口的可见性守护会恢复窗口层级、透明度、content view、`AVPlayerLayer`、player/current item/queue、播放状态和屏幕内位置，处理“进程还在但形象消失”的情况。停顿时播放器保持运行，不再暂停并 seek 回素材透明首帧。

## 程序化入口

Hermes 官方 `website/docs/developer-guide/programmatic-integration.md` 给出的自定义宿主首选入口是 TUI gateway JSON-RPC。

桌宠当前状态：

- 生产聊天优先启动官方 `python -m tui_gateway.entry`，通过 JSON-RPC over stdio 发送 `session.resume` / `session.create` / `prompt.submit`。
- 图片输入走官方 `image.attach`，由 TUI gateway 把图片挂到当前 session；单张/多张图片都会逐张附加。
- 语音输入/朗读走官方 gateway voice 方法：`voice.toggle`、`voice.record`、`voice.tts`。
- 原生 PTY/TUI 只保留为显式 opt-in，避免把 ANSI TUI 控制字符直接刷进聊天。
- 状态镜像已按 TUI gateway 官方事件名解析：`message.delta`、`message.complete`、`thinking.delta`、`reasoning.delta`、`tool.start`、`tool.progress`、`tool.complete`、`approval.request`、`clarify.request`、`sudo.request`、`secret.request`、`voice.status`、`voice.transcript`、`gateway.ready`。
- slash 指令优先走 `slash.exec`；遇到官方提示需走 pending-input/skill/plugin 分支时，回落到 `command.dispatch`。
- 如果 gateway 已启动但 `prompt.submit` 后长时间没有 `message.delta`/`message.complete`，桌宠会把卡住阶段写入工具记录，终止当前 gateway/slash worker，并回退到官方 `hermes chat -q --resume` 继续当前 session；这只是传输层保底，不改 Hermes 官方模型、memory 或工具执行逻辑。

完整度边界：

- 当前已经使用官方 gateway 作为 Hermes 主链路，不再把 Hermes 当成纯 `hermes chat -q` 文本壳。
- 仍需要继续跟随 Hermes 官方新增 gateway 事件，避免未来事件只落到文本兼容解析。
- 原生 TUI/PTY 嵌入目前是保守 opt-in；默认体验优先走结构化 JSON-RPC，避免 ANSI 控制字符污染聊天 UI。
- 当前实测遇到过官方 `tui_gateway.slash_worker --model grok-4.20-0309-reasoning` 停在接管阶段但未进入 `conversation_loop`；保底链路会切到 quick CLI，并在日志里继续看到 `platform=cli` 的官方 Hermes 调用。

## 权限确认

官方来源：

- `tools/approval.py`：gateway approval 数据包含 `command`、`description`、`pattern_key`、`pattern_keys`，结果使用 Hermes 字符串 `once`、`session`、`always`、`deny`。
- `acp_adapter/permissions.py`：ACP option 映射到同一组 Hermes 结果字符串。
- `tui_gateway/server.py`：TUI gateway 用 `approval.request` 发事件，用 `approval.respond` 回 `choice`。

桌宠当前状态：

- 小橘子权限弹窗返回 Hermes 官方结果：`once`、`session`、`always`、`deny`。
- 在 TUI gateway transport 下，小橘子用官方 `approval.respond` 发送 `choice`。
- 如果进入原生 TUI 数字选择界面，桌宠只在那个分支发送数字键，避免把 `--provider`/模型或权限词误写成 TUI 输入。
- 状态镜像能识别官方 `approval.request` / MCP `approval_requested`，并弹出小橘子确认 UI。
- `clarify.request` 使用小橘子选择/输入弹窗，并通过官方 `clarify.respond` 回传 `answer`。
- `sudo.request` 使用小橘子安全输入框，并通过官方 `sudo.respond` 回传 `password`；输入内容不写入日志、记忆或聊天记录。
- `secret.request` 使用小橘子安全输入框，并通过官方 `secret.respond` 回传 `value`；输入内容不写入日志、记忆或聊天记录。

待继续：

- 把“记住选择”从一次性 `always` 回传扩展成桌宠可查看、可撤销的授权规则面板。
- 对不同工具类型展示更具体的风险摘要，例如 shell 命令、文件写入、联网请求、电脑操作分开说明。
- 记录权限请求的非敏感审计信息，但继续禁止记录 sudo password 和 secret value。

## 工具状态

官方来源：

- `tui_gateway/server.py`：`tool.start`、`tool.progress`、`tool.complete`。
- `acp_adapter/events.py`：`tool.started` 转 ACP ToolCallStart，完成事件从 step callback 的 previous tools 映射。

桌宠当前状态：

- 优先解析官方 JSON 事件帧。
- 在 gateway 不可用时，保留文本兼容解析：终端进度条、工具名、命令、路径、搜索词、URL、memory 读写等。
- UI 用统一“小橘子状态镜像”展示正在执行命令、读写文件、搜索、浏览网页、操作电脑、写/读记忆、等待确认。
- 工具/工作流事件不再只作为一闪而过的状态：桌宠会把最近 80 条记录进聊天区顶部常驻折叠条，展开后可查看时间、事件名、摘要、命令/路径/错误等排查线索。
- 回复正文使用稳定流式块追加，生成中按正常 AI 聊天方式从左到右、从上到下写入；工具/工作流事件只更新折叠条，不再打断正文输出。
- `message.delta` 不再做累计快照识别或去重：桌宠按 Hermes 发来的实时增量直接追加，避免任何规则误吞中途生成。
- 小橘子状态/动画刷新只更新标题、主题、侧边栏和焦点，不再调用 `replayHistory()`，避免状态镜像把正在生成的正文、工具折叠记录或刚发送的主人消息清空。
- 桌宠维护本地 pending transcript 作为发送中保底；如果重启/切会话时本地缓存比 Hermes 官方 `state.db` 更新，会优先恢复本地显示，再继续让 Hermes 官方库作为长期来源。
- 工具/工作流记录也会写入会话历史中的 `toolUse`/`toolResult`，切会话或重启后可以重新灌回折叠记录，而不是只在 UI 里闪一下。
- provider/model 错误需要按 Hermes 官方 `/model <model> --provider <provider>` 处理；例如 DeepSeek 模型如果被 xAI provider 执行会得到 xAI 的 404，这属于 provider mismatch 诊断，不是桌宠自定义模型格式。

待继续：

- 在工具记录中显示更多官方事件细节：工具参数摘要、当前读写路径、等待中的 request id、失败原因。
- 区分“正在思考”“正在调用工具”“等待主人确认”“工具失败但可继续”等状态，让小橘子动画和状态气泡更贴近 Hermes 实时运行状态。
- 为长任务保留最近若干条工具进度，避免只看到最后一条状态。

## 语音模式

官方来源：

- `tui_gateway/server.py`：`voice.toggle` 对齐 `/voice on/off/tts/status`，`voice.record` 负责 VAD 有界录音和转写，`voice.tts` 调用 Hermes 官方 TTS。
- `hermes_cli/voice.py`：封装 `start_continuous` / `stop_continuous` / `speak_text`，并处理 TTS 播放时的录音反馈保护。
- `tools/voice_mode.py`、`tools/transcription_tools.py`、`tools/tts_tool.py`：音频捕获、STT provider、TTS provider 均由 Hermes 官方实现管理。

桌宠当前状态：

- 聊天框麦克风按钮调用官方 `voice.toggle on` 后再调用 `voice.record start/stop`，实现微信式“一句语音一条回复”。
- 收到 `voice.transcript` 后，小橘子把转写显示为语音消息，并按官方 TUI 行为自动提交给 Hermes 当前会话。
- 小喇叭按钮是桌宠本地“朗读回复”ON/OFF 开关：开关状态写入本地 `UserDefaults`，ON 时 TUI gateway、quick fallback、PTY 三种回复完成路径都会调用官方 `voice.tts` 朗读这一条，OFF 时只显示文字，不改 Hermes 全局 `/voice tts` 状态。
- 小橘子状态会跟随 `voice.status` 切换为正在听、正在听写、正在朗读。
- 朗读是明确的 ON/OFF 开关；语音输入当前采用“点一下开始，说完再点一下停止”的微信式交互。
- 聊天输入框内有语音状态文字，明确显示“点麦克风开始”“正在听”“正在转写”“朗读 ON/OFF”等状态，避免只靠按钮颜色判断。
- 麦克风开始录音前会确认官方 `voice.toggle on` 返回成功，再调用 `voice.record start`；录音后会短暂忽略 gateway 里滞后的 `idle` 事件，避免按钮刚进入红色录音态就被旧状态刷回关闭态。
- App 声明了 macOS 麦克风权限用途，首次使用语音输入时应由系统弹出授权请求；授权后 Hermes 官方录音链路才能稳定拿到音频。
- 如果官方 `voice.record` 返回错误，小橘子会把错误原因直接显示在聊天输入区的语音状态文字里，并同步到工具状态镜像，避免只看到按钮恢复。
- 如果官方 `voice.tts` 立即返回错误，小橘子会把常见英文错误翻成中文诊断显示；本机 Hermes 当前将 Edge TTS 声音切到 `zh-TW-HsiaoChenNeural`，并设置 `tts.edge.speed: 1.08`，中文朗读测试可正常生成音频。
- 已为本机 Hermes venv 补齐官方录音/本地转写依赖：`sounddevice`、`numpy`、`faster-whisper`；当前 `check_voice_requirements()` 返回 voice 可用。
- 本机 Hermes 已关闭 `voice.beep_enabled`。原因是 macOS PortAudio 播放提示音时可能报 `PaMacCore` / `OutputStream` 错误，并把底层日志喷进 gateway 输出；关闭 beep 不影响录音、STT 或 TTS，只是不播放开始/结束提示音。
- 桌宠调用 `voice.tts` 前会做显示/朗读分离：聊天区继续显示小橘子的完整回复，包括 `（耳朵抖了抖）`、`(小声嘀咕)`、工具/工作流和状态镜像；送给 TTS 的文本会过滤括号里的动作/状态旁白、代码块、Hermes 官方事件、JSON-RPC 状态、命令日志、工具/工作流记录和用户回显，避免朗读时把内部执行过程念出来。
- 本机 Hermes TTS 桌面播放做了两处小补丁：`tools/tts_tool.py` 在调用方显式传入 `.mp3` 输出路径时不再强制转成 `.ogg`，保留 macOS 更稳定的 MP3 播放；`hermes_cli/voice.py` 会读取 `text_to_speech_tool` 返回的真实 `file_path` 作为后备播放路径。默认未指定输出路径的 TTS 仍会生成 Hermes 平台投递所需的 voice-compatible `.ogg`。
- 小橘子会维护语音缓存：App 启动时扫一次，之后每 24 小时扫一次，菜单栏 Hermes 里也可以手动触发。清理范围只匹配 Hermes 自动生成的 `tts_*` 音频文件：`~/.hermes/audio_cache` 保留 7 天，`$TMPDIR/hermes_voice` 保留 24 小时；总量超过 300MB 时从最旧的自动缓存开始删到约 80% 上限。主人手动保存或改名的音频不会被自动清理。
- 修复朗读 ON 后再开语音可能闪退的问题：崩溃点在桌宠动画层 `AVPlayerLooper` 的快速切换；现在切换动画前先禁用旧 looper，并为新动画创建独立 queue player，同时语音工具记录不再额外触发工具状态动画。
- 朗读模式下，新回复开始调用官方 `voice.tts` 前会先打断上一段 Hermes TTS 播放；关闭朗读也会立即停止当前播放，避免多段语音叠在一起。
- 语音输入仍然使用 Hermes 的上下文、memory、模型、工具和权限确认，不绕开 Hermes 本体。
- 桌宠本体窗口增加可见性守护：截图里出现过“气泡还在但小橘子本体消失”的状态，所以显示循环现在会自动恢复窗口层级、透明度、content view、`AVPlayerLayer`、queue player/current item/queue 和播放状态；停顿时不再暂停并 seek 回素材透明首帧，并在非主人手动隐藏时把窗口拉回屏幕内。

当前可快速试的中文 Edge TTS 声线：

- `zh-TW-HsiaoChenNeural`：台湾普通话女声，友好、明亮，是当前默认声线。
- `zh-CN-XiaoyiNeural`：更轻快，适合作为小橘子的可爱少女音。
- `zh-CN-XiaoxiaoNeural`：更稳、更温柔，适合日常陪伴。
- `zh-TW-HsiaoYuNeural`：台湾普通话女声，可能出现繁体/台湾腔听感。
- `zh-CN-liaoning-XiaobeiNeural` / `zh-CN-shaanxi-XiaoniNeural`：方言女声，有地域口音，不适合作为默认但可以玩。

待继续：

- 做电话模式：连续听说、自动续听、打断朗读和更明确的回声抑制状态。
- 做语音设置页：展示 STT/TTS provider、依赖可用性、record key、silence threshold/duration、语音缓存大小/清理策略，并写入 Hermes 官方 `config.yaml`。
- 做单条消息朗读按钮和停止朗读按钮，而不仅是全局自动朗读开关。
- 评估长按说话；当前先保留点击开始/停止，因为它更适合先验证 Hermes 官方 VAD/STT 链路。
- 在 sudo/secret/permission 弹窗活跃时显式暂停语音输入。

## 官方工具对齐

- 小橘子不直接实现 Hermes 工具能力，而是读取本机 Hermes 官方源码和配置：
  - Slash 指令来自 `hermes_cli/commands.py` 的 `COMMAND_REGISTRY`。
  - 工具清单来自 `~/.hermes/hermes-agent/tools/*` 中真实的 `registry.register(...)`。
  - 媒体配置来自 `~/.hermes/config.yaml` 的 `image_gen`、`video_gen`、`tts`、`stt`。
- 能力区表达媒体/语音创作意图，而不是直接强制调用工具：
  - 图像创作需求交给 Hermes；Hermes 根据上下文自动决定是否调用 `image_generate`，并使用当前 `image_gen.provider/model`。
  - 视频创作需求交给 Hermes；Hermes 根据上下文自动决定是否调用 `video_generate`，并使用当前 `video_gen.provider/model`。
  - 语音创作需求交给 Hermes；Hermes 根据上下文自动决定是否调用 `text_to_speech`，并使用当前 `tts.provider/voice`。
- “工具”按钮会展示 Hermes 当前注册的 toolset 和工具名，用来逐项检查还有哪些需要做专用小橘子面板。
- 这些入口只生成面向 Hermes 的自然语言意图提示，真正的工具选择、调用、鉴权、产物生成和失败原因仍由 Hermes 本体负责；桌宠负责 UI、状态镜像、权限弹窗、附件和朗读过滤。

## 记忆策略

官方来源：

- `agent/memory_provider.py` / `website/docs/developer-guide/memory-provider-plugin.md`：记忆 provider 有 `prefetch`、`queue_prefetch`、`sync_turn`、`on_session_end`、`on_memory_write` 等生命周期。
- 官方内置长期记忆文件仍是 `~/.hermes/memories/USER.md` 和 `~/.hermes/memories/MEMORY.md`。

桌宠当前状态：

- 不替换 Hermes memory provider，不改官方 memory 源码。
- 主人明确 `/记住`、`请记住`、`帮我记住` 时直接写入官方 `USER.md`。
- 自动识别出的 USER/MEMORY 长期候选先进入 `core/hermes_memory_inbox.md`，主人确认后才写官方 memory。
- 候选箱支持按 USER/MEMORY/DAILY 筛选、编辑后写入、单条处理和批量处理。
- DAILY 候选只进入当天小橘子备忘录，用于工作日志和提醒候选，不污染长期 memory。

待继续：

- 对候选做去重、重要性分级和来源标记，减少重复记忆。
- 为长期项目、常用路径、个人偏好、任务完成记录建立更稳定的分类策略。
- 写入 Hermes 官方 memory 前展示更清楚的差异预览和撤销入口。
