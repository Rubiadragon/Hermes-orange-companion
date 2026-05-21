# 发布流程

这份文档记录小橘子桌宠从本地 Debug 包走向公开发布时需要做的事项。

## 本地验证

```zsh
./scripts/typecheck.sh
./scripts/secret-scan.sh
./scripts/build-debug.sh
./scripts/install-debug.sh
```

手动检查：

- 双击 `/Applications/小橘子桌宠.app` 能启动。
- 点击小橘子后能进入 Hermes / Codex 双入口。
- Hermes 对话列表、当前 session、模型和 slash 指令联想正常。
- 缺少动画素材时 App 不崩溃。
- 有动画素材时状态切换、拖拽、戳戳、贴贴、困惑音效正常。

## Release 构建

后续正式发布建议补充一个 Release 脚本，流程是：

```zsh
xcodebuild \
  -project MOrangeCompanion.xcodeproj \
  -scheme MOrangeCompanion \
  -configuration Release \
  -archivePath build/MOrangeCompanion.xcarchive \
  archive
```

然后进行签名、公证和打包：

```zsh
xcodebuild -exportArchive \
  -archivePath build/MOrangeCompanion.xcarchive \
  -exportPath dist \
  -exportOptionsPlist release/ExportOptions.plist
```

## 发布前清单

- 确认 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION` 已更新。
- 确认 README、CHANGELOG、素材说明和已知限制更新。
- 确认仓库不包含 `.env`、API key、用户私有记忆、Hermes 私人配置。
- 确认大体积 `.mov` 动画素材没有被提交。
- 确认 `release/appcast.xml` 使用小橘子自己的链接和签名。
- 确认 `LICENSE` 和 `docs/ACKNOWLEDGEMENTS.md` 保留必要开源信息。
- 确认 `./scripts/secret-scan.sh` 通过；泛关键词和高熵误报需要人工复核。

## v0.1.0 Release

首个公开版本建议使用：

- Tag：`v0.1.0`
- Title：`MOrange Companion v0.1.0 / 小橘子桌宠 v0.1.0`
- Source：GitHub 自动生成的 source code zip/tar.gz
- Asset：`MOrangeAnimations-v0.1.0.zip`

生成动画素材包：

```zsh
./scripts/package-release-assets.sh v0.1.0
```

上传到 GitHub Release 的附件：

```text
dist/release-assets/MOrangeAnimations-v0.1.0.zip
dist/release-assets/MOrangeAnimations-v0.1.0.zip.sha256
```

Release notes 建议：

````markdown
# MOrange Companion v0.1.0 / 小橘子桌宠 v0.1.0

首个公开版本。小橘子桌宠把 Hermes 和 Codex 变成 macOS 桌面入口，支持桌宠互动、聊天窗口、会话选择、模型切换、附件、语音按钮和本机工作区桥接。

## 安装

1. 下载源码或 clone 仓库。
2. 安装 Hermes CLI，并配置自己的 `~/.hermes/config.yaml` 和 `~/.hermes/.env`。
3. 用 Xcode 打开 `MOrangeCompanion.xcodeproj` 构建，或运行 `./scripts/build-debug.sh`。
4. 下载 `MOrangeAnimations-v0.1.0.zip`，解压到：

```text
~/Library/Application Support/morange-companion/MOrangeAnimations/
```

## Included

- 小橘子 README 首页图和公开轻量素材。
- Hermes / Codex 双入口。
- 会话列表、模型状态、slash 指令联想和工具状态镜像。
- 戳戳、贴贴、气鼓鼓、拖拽等桌宠交互动画。

## Notes

本仓库不包含 API key、私有 Hermes 配置、私有 memory 或本地工作区内容。原项目来源与许可证说明见 `docs/ACKNOWLEDGEMENTS.md`。
````

## Appcast

`release/appcast.xml` 是 Sparkle 更新源模板。正式启用自动更新前，需要补齐：

- zip 下载地址
- `sparkle:edSignature`
- 文件长度
- 版本号
- 最低 macOS 版本
