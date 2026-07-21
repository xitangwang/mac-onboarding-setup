---
created: 2026-06-02 17:01:09 +0800
summary: 25 号航海 AI 工具一键部署脚本说明
last_change: 2026-07-21 — 标注制作者与 25 号航海使用说明
---

# 25 号航海 · AI 工具一键部署助手

> 制作者：[xitangwang](https://github.com/xitangwang)  
> 使用场景：25 号航海

这是我为 25 号航海制作的 AI 工具一键部署项目，面向零基础学员使用。它可以检测并安装 Codex、Hermes、飞书 CLI、Obsidian，同时明确告诉你哪些工具已真正可用、哪些还需要处理。

本项目负责安装流程、环境检测和中文提示；各软件本体均来自对应厂商的官方安装源。

“安装完成”只代表命令可以执行，不代表账号已经登录。脚本会把安装检查和登录授权分开提示。

## 一句话用法

### Mac

打开「终端」App，粘贴：

```bash
curl -fsSL https://raw.githubusercontent.com/xitangwang/mac-onboarding-setup/main/install.sh | bash
```

只检测、不安装：

```bash
curl -fsSL https://raw.githubusercontent.com/xitangwang/mac-onboarding-setup/main/install.sh | bash -s -- --check
```

### Windows

打开 Windows PowerShell 或 Windows Terminal，粘贴：

```powershell
irm https://raw.githubusercontent.com/xitangwang/mac-onboarding-setup/main/go.ps1 | iex
```

只检测、不安装：

```powershell
$env:CHECK_ONLY=1
irm https://raw.githubusercontent.com/xitangwang/mac-onboarding-setup/main/go.ps1 | iex
```

交互提示中：回车表示继续，`s` 表示跳过，`q` 表示退出。安装后建议重开终端再验证。

## 设备兼容范围

| 设备 | 支持情况 |
|---|---|
| Apple Silicon Mac，macOS 14+ | Codex CLI、Hermes、飞书 CLI 和新版桌面 App 均可走官方安装路径 |
| Apple Silicon Mac，macOS 12～13 | CLI 工具可安装；新版 Codex / ChatGPT 桌面 App 不支持 |
| Apple Silicon Mac，macOS 11 | Node 22 和飞书 CLI 可用；Hermes 与新版桌面 App 会明确跳过，Codex CLI 由官方安装器判断 |
| Intel Mac | Codex CLI 可安装；macOS 14+ 可用新版桌面 App；Hermes 官方不支持，会被脚本跳过 |
| Windows 10/11 x64 | 支持 Codex、Hermes、飞书 CLI；桌面 App 和 Obsidian 使用 Microsoft Store / winget |
| Windows ARM64 | 支持原生 ARM64；脚本通过 CIM 识别真实架构，并强制 Node/Codex 使用 ARM64 包 |
| 32 位 Windows 或 Windows 10 以前版本 | 当前主力 CLI 不支持，脚本会停止并说明原因 |

## 安装内容与方式

| 工具 | 安装方式 | 安装成功判定 |
|---|---|---|
| Codex | OpenAI 官方脚本 | `codex --version` 成功且有版本文本 |
| Hermes | Nous Research 官方脚本；Windows 依赖由安装器放在用户目录 | `hermes --version` 成功且有版本文本 |
| 飞书 CLI | 官方 `npx @larksuite/cli@latest install` | `lark-cli --version` 成功，同时存在官方 Agent Skills |
| Node.js | Mac 使用 Node 22 LTS 官方包并核对 SHA-256；Windows 使用 winget LTS | `node --version` 和 `npm --version` 都成功 |
| Obsidian | Mac 自动读取当前 GitHub DMG；Windows 使用 winget | 实际检测到应用或 winget 包 |
| ChatGPT 桌面 App（内含 Codex） | Mac 自动下载并安装官方 ChatGPT 桌面 App（内含 Codex）；Windows 使用 Microsoft Store | Mac 校验 DMG、OpenAI 代码签名、Bundle ID 和芯片架构后再复制安装 |

脚本不会因为 PATH 中存在一个同名但损坏的命令就显示成功。版本命令失败时会重新安装或明确报错。

## 登录与授权

- Codex：安装后按提示手动运行 `codex login`；无浏览器环境可使用 `codex login --device-auth`。
- 飞书 CLI：先运行初始化，再进入扫码或浏览器授权。两步分别检查返回码，取消或失败都会提示对应重试命令。
- Hermes：本脚本只安装本体和环境；模型/provider 后续按 Hermes 官方文档配置。

只检测模式和最终版本检查不会判断账号是否已经登录。

## 错误提示说明

脚本会尽量保留官方安装器的原始输出，并区分以下情况：

- 下载源、DNS、超时或代理认证失败。
- 系统版本或 CPU 架构不支持。
- 目录权限、PowerShell 执行策略、UAC 或公司设备策略。
- Microsoft Store / winget 不可用或被禁用。
- 磁盘空间不足、安装包校验失败或文件不完整。
- 命令文件存在，但 `--version` 实际执行失败。
- 飞书初始化失败、登录取消或授权失败。

如果流程末尾仍有必需项失败，脚本会显示“不能标记为全部就绪”，并设置非零状态；不会再把所有失败都写成“多半是网络”。

## 常见处理

### Mac 上 Node 或飞书 CLI 安装失败

脚本固定选择兼容 macOS 11+ 的 Node 22 LTS，并校验官方 SHA-256。如果仍失败，查看上方提示属于下载、校验、权限还是磁盘问题；也可手动安装 Node 22 LTS 后重开终端再运行。

### Windows 上 winget 返回非零代码

检查 Microsoft Store 的「应用安装程序」、公司策略、UAC 弹窗、代理和杀毒软件。Windows ARM64 应在检测信息中显示 `ARM64`；如果显示错误，请保留完整截图。

### Intel Mac 没有安装 Hermes

这是官方支持范围限制，不是网络错误。脚本会继续安装该机器受支持的 Codex、飞书 CLI 和 Obsidian。

### 命令存在但仍显示损坏

脚本实际执行了 `--version`。如果失败，常见原因是旧安装残留、架构不匹配、文件被杀毒软件隔离或依赖文件缺失；重新运行脚本会尝试覆盖修复。

## 项目文件

- `install.sh`：Mac 主安装器。
- `install.ps1`：Windows 主安装器。
- `go.ps1`：Windows ASCII/UTF-8 启动器，负责 TLS、下载内容校验和异常提示。
- `tests/test_installers.sh`：可重复运行的安装器回归测试。
- `docs/superpowers/plans/`：本轮可靠性修复的实施计划。
- `README.md`：本说明。

## 维护与验证

本地修改后至少运行：

```bash
bash tests/test_installers.sh
bash -n install.sh
bash install.sh --check
```

Windows 主脚本应另外在 Windows 10/11 x64 和 Windows ARM64 上各执行一次只检测模式，再做发布。

入口与来源：

- Codex：<https://github.com/openai/codex>
- Hermes：<https://hermes-agent.nousresearch.com/docs/>
- 飞书 CLI：<https://github.com/larksuite/cli>
- Obsidian：<https://obsidian.md/download>

`go.ps1`、`install.sh` 和各官方安装入口仍属于联网下载并执行代码。发布时应保护主分支写权限；Node 二进制已经增加 SHA-256 校验，其他上游官方安装脚本由对应厂商维护。
