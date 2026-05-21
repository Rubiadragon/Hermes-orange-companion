# 项目结构

小橘子桌宠按“源码、公开素材、文档、发布、脚本”几个区域维护，避免把构建产物、密钥、私有工作区和临时文件混进仓库。

```text
.
├── MOrangeCompanion/
│   ├── MOrangeCompanionApp.swift          # App 入口、菜单栏和启动项
│   ├── MOrangeCompanionController.swift   # 桌宠控制器和动画状态配置
│   ├── WalkerCharacter.swift              # 桌宠窗口、动作、交互和聊天窗口
│   ├── AgentSession.swift                 # Hermes session、会话库和指令同步
│   ├── CodexSession.swift                 # Codex session、会话库和配置同步
│   ├── CompanionSession.swift             # 本地陪聊兼容层
│   ├── HermesBridge.swift                 # Hermes 配置、记忆、备忘录和工作区桥接
│   ├── TerminalView.swift                 # 输入框、快捷按钮、指令联想
│   ├── PopoverTheme.swift                 # 聊天窗口主题
│   ├── CharacterContentView.swift         # 桌宠渲染视图
│   ├── ShellEnvironment.swift             # CLI 环境和二进制查找
│   ├── Assets.xcassets/                   # App 图标、状态栏图标
│   ├── Sounds/                            # 小橘子提示音
│   ├── Info.plist
│   └── MOrangeCompanion.entitlements
├── MOrangeCompanion.xcodeproj/
├── assets/
│   └── morange/
├── docs/
│   ├── ASSETS.md
│   ├── CONFIGURATION.md
│   ├── CAPABILITIES.md
│   ├── HERMES_ALIGNMENT.md
│   ├── MEMORY_STRATEGY.md
│   ├── OPEN_SOURCE_CHECKLIST.md
│   ├── RELEASE.md
│   ├── ACKNOWLEDGEMENTS.md
│   ├── designs/
│   └── images/
├── release/
│   └── appcast.xml
├── scripts/
│   ├── typecheck.sh
│   ├── build-debug.sh
│   ├── install-debug.sh
│   ├── secret-scan.sh
│   └── clean.sh
├── README.md
├── CHANGELOG.md
├── LICENSE
├── .gitignore
└── .gitattributes
```

## 维护规则

- `MOrangeCompanion/` 只放会被 Xcode 编译或打包的文件。
- `assets/morange/` 放可公开上传的小橘子轻量素材、参考图和交互预览。
- `docs/images/` 放 README 和文档用图片，不放运行时大视频。
- `docs/designs/` 放 UI 原型或手稿，不进入 App bundle。
- `release/` 放发布元数据，不放构建产物。
- `scripts/` 放可重复执行的本地脚本。
- `build/`、`dist/`、`.xcarchive`、`.app`、`.dmg`、`.zip` 都视为生成物，不提交。

## 命名规则

- 工程、源码目录、target 使用 `MOrangeCompanion`。
- App 显示名使用 `小橘子桌宠`。
- Bundle identifier 使用 `com.rubiadragon.morangecompanion`。
- 素材前缀使用 `morange-`。
