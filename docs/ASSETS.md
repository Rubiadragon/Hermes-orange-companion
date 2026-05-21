# 小橘子素材规范

仓库保留可公开的轻量资源：App 图标、状态栏图标、提示音、小橘子参考图、聊天水印和交互预览图。大体积透明视频动画不提交到 Git，运行时从本机素材目录读取，发布时建议放进 GitHub Releases。

## 仓库内公开素材

```text
assets/morange/
├── README.md
├── chat-background/
│   └── morange-chat-watermark.png
├── reference/
│   └── morange-chibi-reference.png
└── interaction-previews/
    ├── morange-affection.png
    ├── morange-drag-behind.png
    ├── morange-drag-forward.png
    ├── morange-lifted.png
    ├── morange-poke.png
    ├── morange-pressed.png
    └── morange-puffed.png
```

这些文件可以随源码仓库上传，用于 README、文档、轻量预览和 UI 参考。

## 推荐运行目录

```text
~/Library/Application Support/morange-companion/
└── MOrangeAnimations/
    ├── morange-walk.mov
    ├── morange-idle.mov
    ├── morange-thinking.mov
    ├── morange-working.mov
    ├── morange-done.mov
    ├── morange-confused.mov
    ├── morange-sleepy.mov
    ├── morange-happy.mov
    ├── morange-poke.mov
    ├── morange-affection.mov
    ├── morange-puffed.mov
    ├── morange-held.mov
    ├── morange-drag-forward.mov
    ├── morange-drag-behind.mov
    ├── morange-lifted.mov
    └── morange-pressed.mov
```

## App 内资源

```text
MOrangeCompanion/
├── Assets.xcassets/
│   ├── AppIcon.appiconset/
│   ├── MenuBarIcon.imageset/
│   └── MorangeAssistantBubbleSticker.imageset/   # 可选：小橘子气泡透明贴纸
└── Sounds/
    ├── morange-soft.m4a
    ├── morange-done.m4a
    └── morange-confused.m4a
```

## 聊天气泡素材

聊天气泡主体由 AppKit 绘制，不建议用整张位图气泡替代，否则长回复、窗口缩放和深浅背景下容易变糊或拉伸。更推荐用 xAI 生成透明 PNG 装饰贴纸，再放入：

```text
MOrangeCompanion/Assets.xcassets/MorangeAssistantBubbleSticker.imageset/
```

素材建议：

- 尺寸：`96x96`、`192x192`、`288x288` 三档 PNG。
- 背景：透明。
- 内容：橘瓣、橘子叶、小尾巴缎带、手账贴纸、轻微纸纹，避免文字。
- 风格：Q 版、淡橘色、柔和描边，不要高对比照片或复杂背景。
- 用途：只作为小橘子左侧橘色气泡的低透明度角落装饰。

推荐提示词方向：

```text
transparent PNG sticker, cute chibi orange mascot chat bubble corner ornament,
small orange slice, tiny leaf, soft stationery style, warm orange palette,
clean outline, no text, no background, macOS app UI asset
```

## 搜索顺序

App 会按顺序搜索：

- `MORANGE_ASSETS_DIR/MOrangeAnimations`
- `MORANGE_ASSETS_DIR`
- `~/Library/Application Support/morange-companion/MOrangeAnimations`
- `~/Library/Application Support/morange-companion`
- App 相邻目录里的 `MOrangeAnimations`
- 当前工作目录里的 `MOrangeCompanion/MOrangeAnimations`
- 当前工作目录里的 `MOrangeAnimations`

## 环境变量

```zsh
export MORANGE_ASSETS_DIR="/path/to/morange-assets"
```

## 缺素材时

如果找不到对应 `.mov`，桌宠会保持 App 运行，但该动画不会显示。发布包可以选择：

- 源码仓库只内置轻量预览素材。
- GitHub Releases 附带 `MOrangeAnimations.zip` 透明动画包。
- App 首次启动时检查素材包，并引导用户放置到运行目录。

## 发布动画包

开发者可以从本机运行时素材目录生成 Release 附件：

```zsh
./scripts/package-release-assets.sh v0.1.0
```

脚本会输出：

```text
dist/release-assets/MOrangeAnimations-v0.1.0.zip
dist/release-assets/MOrangeAnimations-v0.1.0.zip.sha256
```

把 zip 上传到 GitHub Release。用户下载后解压到：

```zsh
mkdir -p "$HOME/Library/Application Support/morange-companion"
unzip "$HOME/Downloads/MOrangeAnimations-v0.1.0.zip" \
  -d "$HOME/Library/Application Support/morange-companion"
```
