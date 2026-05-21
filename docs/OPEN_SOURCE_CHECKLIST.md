# 开源前审查

## 本次审查结论

- 未发现明文 API key。
- 桌宠源码不包含个人 Hermes 灵魂内容或私有触发配置。
- 用户本机运行数据、Hermes 配置、Codex 配置、构建产物、签名包和大体积素材均应排除在 Git 外。
- README 和配置文档已说明他人如何安装、配置 Hermes、放置素材和运行桌宠。

## 已检查范围

```text
MOrangeCompanion/
MOrangeCompanion.xcodeproj/
docs/
release/
scripts/
README.md
CHANGELOG.md
LICENSE
.gitignore
```

## 发布前建议命令

```zsh
./scripts/secret-scan.sh
rg -n "sk-proj-[A-Za-z0-9_-]{20,}|sk-svcacct-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9_-]{20,}|xai-[A-Za-z0-9_-]{20,}|Bearer [A-Za-z0-9._-]{20,}" .
rg -n "/Users/|\\.env|\\.hermes|\\.codex" .
git status --short
```

## 不应提交

- `~/.hermes/`
- `~/.codex/`
- `.env` / `.env.*`
- `build/` / `DerivedData/`
- `.xcuserdata/`
- `.app` / `.xcarchive` / `.dmg` / `.zip`
- 私人日志、对话导出、截图中的密钥、未授权素材

## 允许保留

- 读取环境变量的代码。
- 文档中出现环境变量名称。
- `Package.resolved` 的 package checksum。
- 开源许可证、致谢和项目结构文档。
