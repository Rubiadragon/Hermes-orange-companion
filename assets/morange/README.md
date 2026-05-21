# MOrange Assets / 小橘子素材

这个目录保存仓库内可公开、轻量的小橘子素材，用于 README、文档预览、聊天背景和交互说明。

## Included

- `chat-background/morange-chat-watermark.png`：聊天 UI 和文档可用的小橘子透明贴图。
- `reference/morange-chibi-reference.png`：小橘子 Q 版参考形象。
- `interaction-previews/*.png`：戳戳、贴贴、气鼓鼓、拖拽等交互状态的透明预览图。

## Runtime Animations

运行时透明 `.mov` 动画文件体积较大，不建议直接提交到源码仓库。完整动画包已经作为 GitHub Release 附件提供：

- Release 页面：https://github.com/Rubiadragon/Hermes-orange-companion/releases/tag/v0.1.0
- 完整动画包：https://github.com/Rubiadragon/Hermes-orange-companion/releases/download/v0.1.0/MOrangeAnimations-v0.1.0.zip
- SHA256：https://github.com/Rubiadragon/Hermes-orange-companion/releases/download/v0.1.0/MOrangeAnimations-v0.1.0.zip.sha256

下载后解压到：

```text
~/Library/Application Support/morange-companion/MOrangeAnimations/
```

用户可以这样安装 Release 动画包：

```zsh
mkdir -p "$HOME/Library/Application Support/morange-companion"
unzip "$HOME/Downloads/MOrangeAnimations-v0.1.0.zip" \
  -d "$HOME/Library/Application Support/morange-companion"
```

开发者可以这样重新打包动画：

```zsh
./scripts/package-release-assets.sh v0.1.0
```

具体命名和搜索顺序见 `docs/ASSETS.md`。
