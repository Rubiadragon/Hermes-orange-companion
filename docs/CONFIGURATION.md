# 配置与使用

本文说明如何在一台新 Mac 上配置小橘子桌宠。

## 1. 安装依赖

- 安装 Xcode。
- 安装 Hermes CLI，并确保下面任一路径可执行：
  - `~/.local/bin/hermes`
  - `/opt/homebrew/bin/hermes`
  - `/usr/local/bin/hermes`
- 可选安装 Codex CLI；没有 Codex 时，Hermes 入口仍可使用。

## 2. 配置 Hermes

桌宠读取本机 Hermes 配置，不在仓库内保存密钥。

常用文件：

```text
~/.hermes/config.yaml
~/.hermes/.env
~/.hermes/memories/USER.md
~/.hermes/memories/MEMORY.md
```

模型 provider、API key、语音、图像和视频等配置应放在 Hermes 自己的配置系统中。不要把任何 key 写入本仓库。

## 3. 配置工作区

默认工作区：

```text
~/Documents/Hermes小橘子
```

桌宠会在工作区里使用这些普通目录：

```text
core/
projects/
projects/daily-notes/
normal-images/
normal-videos/
scripts/
```

需要改路径时设置：

```zsh
export MORANGE_HERMES_CWD="$HOME/Documents/Hermes小橘子"
```

如果从 Finder 双击启动 App，shell 里的临时 `export` 不一定会被继承。正式使用时建议把路径写入 LaunchAgent、zsh profile 后从终端启动，或保持默认工作区。

## 4. 配置素材

推荐素材目录：

```text
~/Library/Application Support/morange-companion/MOrangeAnimations/
```

可用环境变量覆盖素材根目录：

```zsh
export MORANGE_ASSETS_DIR="$HOME/Library/Application Support/morange-companion"
```

素材命名见 [ASSETS.md](ASSETS.md)。

## 5. 构建运行

```zsh
./scripts/typecheck.sh
./scripts/build-debug.sh
./scripts/install-debug.sh
```

`install-debug.sh` 会覆盖安装到：

```text
/Applications/小橘子桌宠.app
```

## 6. 密钥安全

- 仓库不需要 API key。
- `.env`、`.env.*`、`.hermes/`、`.codex/`、`local/` 默认被 `.gitignore` 排除。
- 发布前运行：

```zsh
./scripts/secret-scan.sh
```

Generic secret references 可能会列出代码里读取环境变量的地方，这是正常的；重点关注 High Confidence Secret Shapes 是否为 `No matches`。
