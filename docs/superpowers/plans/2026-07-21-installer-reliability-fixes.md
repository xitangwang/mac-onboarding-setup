# 安装器可靠性修复实施计划

> **供自动化执行代理使用：** 执行本计划时必须使用 `superpowers:subagent-driven-development` 或 `superpowers:executing-plans`，并按任务逐项验证。复选框表示实际完成状态。

**目标：** 让 macOS 和 Windows 安装器能够准确识别设备支持范围、选择正确的架构与版本、给出可执行的错误提示，并且不再把损坏或未完成的安装标记为成功。

**实现方式：** 保留现有四个分发文件，通过小型纯函数拆分命令健康检查、平台支持判断、版本信息解析和最终状态判定。新增一套 Shell 回归测试，实际执行 macOS 逻辑；由于当前电脑没有 Windows PowerShell，Windows 部分使用静态断言和代码结构检查。

**技术范围：** macOS 原生 Bash 3.2、Windows PowerShell 5.1、curl、winget、Node.js 官方发布信息，以及 Codex、Hermes、飞书 CLI、Obsidian 的官方安装入口。

## 全局约束

- 此前已经移除、且不在本项目范围内的工具集成不得重新出现。
- macOS 脚本必须兼容系统自带的 Bash 3.2。
- Windows 脚本必须兼容 Windows PowerShell 5.1。
- macOS 上的 Hermes 只支持 Apple Silicon 且系统版本不低于 macOS 12；Intel Mac 必须明确跳过。
- Codex 所在的新版桌面 App 只允许在 macOS 14 或更高版本上推荐。
- Windows 10/11 x64 与 ARM64 必须选择原生架构；32 位 Windows 必须明确停止。
- Mac 自动安装的 Node.js 使用兼容 macOS 11+ 的 Node 22 LTS，并验证 SHA-256。
- 只有 `--version` 成功退出并返回非空版本文本，才能判定命令安装成功。
- 安装或授权失败必须保留具体原因，并在最终状态中显示未完成。
- 不创建无关系统软件、Git 仓库或部署状态。

---

## 任务一：新增回归测试

**文件：**

- 新增：`tests/test_installers.sh`
- 测试对象：`install.sh`、`install.ps1`、`go.ps1`、`README.md`

**测试职责：**

- 验证损坏的命令不会被标记为成功。
- 验证 Mac 型号和系统版本支持矩阵。
- 验证 Node 与 Obsidian 当前发布信息解析。
- 验证 Windows ARM64、32 位系统、Node/npm、授权和最终状态保护。
- 验证启动器和 README 不再包含过期逻辑。

- [x] **先写能够复现问题的失败测试**

```bash
assert_false '损坏的 Codex 不得显示为已安装' codex_ok
assert_false 'Intel Mac 不支持 Hermes' hermes_supported_on_mac x86_64 14
assert_false 'macOS 13 不支持新版桌面 App' codex_app_supported_on_mac arm64 13
assert_eq "$(printf '%s' "$node_json" | node_version_from_index)" "v22.22.0"
assert_eq "$(printf '%s' "$obsidian_json" | obsidian_dmg_url_from_json)" "https://example/Obsidian-1.12.7.dmg"
```

- [x] **运行测试并确认旧代码确实失败**

执行：

```bash
bash tests/test_installers.sh
```

修复前结果：25 项失败，覆盖已经确认的主要问题。

- [x] **每完成一组修改后重新运行测试**

最终结果：51 项通过，0 项失败。

---

## 任务二：修复 Mac 命令检测和型号路由

**修改文件：** `install.sh`

**新增接口：**

- `command_version`
- `command_ok`
- `codex_ok`
- `lark_ok`
- `tool_ok`
- `hermes_supported_on_mac`
- `codex_app_supported_on_mac`
- `all_installed`

- [x] **把“命令存在”改成“命令真实可用”**

```bash
command_version(){ "$1" --version 2>/dev/null | head -1; }
command_ok(){ [ -n "$(command_version "$1")" ]; }
codex_ok(){ command_ok codex; }
lark_ok(){ command_ok lark-cli; }
```

- [x] **修复 PATH 中存在损坏命令时的错误跳过**

PATH 修复逻辑改用 `tool_ok`。即使 PATH 里已经存在同名命令，只要版本检测失败，脚本仍会继续寻找或安装健康版本。

- [x] **增加明确的平台支持判断**

```bash
hermes_supported_on_mac(){
  [ "${1:-}" = "arm64" ] && [ "${2:-0}" -ge 12 ]
}

codex_app_supported_on_mac(){
  [ "${2:-0}" -ge 14 ] && { [ "${1:-}" = "arm64" ] || [ "${1:-}" = "x86_64" ]; }
}
```

- [x] **修复各型号的行为**

- Intel Mac：明确跳过 Hermes CLI 与桌面 App，不再下载不受支持的版本。
- Apple Silicon、macOS 12 以下：跳过 Hermes。
- macOS 14 以下：不再推荐无法运行的新版 Codex/ChatGPT 桌面 App。
- 未知架构：明确报错，不再一律当作 Intel。
- 在 Hermes 不受支持的 Mac 上，最终完成条件不会强制要求 Hermes。

---

## 任务三：修复 Mac 的 Node 和 Obsidian 安装

**修改文件：** `install.sh`

**新增接口：**

- `node_version_from_index`
- `node_archive_arch`
- `obsidian_dmg_url_from_json`
- `obsidian_installed`

- [x] **修复 Node 版本解析错误**

旧逻辑会把 `version` 字段名中的字母 `v` 也匹配出来，生成包含换行的错误版本号。新逻辑只解析 Node 22 的真实版本值：

```bash
node_version_from_index(){
  tr '{' '\n' |
    sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\(v22\.[0-9.]*\)".*/\1/p' |
    head -1
}
```

- [x] **固定使用兼容旧 Mac 的 Node 22 LTS**

当前实时解析结果为 `v22.23.1`。Node 安装包根据 `arm64` 或 `x86_64` 选择对应的官方归档，未知架构直接停止。

- [x] **增加 Node 安装包校验**

```bash
expected=$(awk -v f="$archive" '$2 == f { print $1; exit }' SHASUMS256.txt)
actual=$(shasum -a 256 "$archive_path" | awk '{print $1}')
[ -n "$expected" ] && [ "$actual" = "$expected" ]
```

下载使用唯一临时目录；解压后必须同时通过 `node --version` 和 `npm --version`。

- [x] **修复 Obsidian 文件名匹配**

新逻辑从 GitHub 发布信息中的 `browser_download_url` 提取任意版本化 `.dmg`，不再依赖已经失效的固定文件名。

- [x] **完善 Obsidian 安装结果**

- 区分发布信息读取失败、DMG 下载失败、挂载失败、App 缺失和目录权限失败。
- `/Applications` 不可写时，自动安装到当前用户的 `~/Applications`。
- 使用唯一临时目录，安装结束后清理。

---

## 任务四：修复 Mac 错误提示、授权和最终状态

**修改文件：** `install.sh`

- [x] **增加错误分类函数**

`failure_hint_from_log` 能识别并提示：

- 权限不足。
- 磁盘空间不足。
- 系统或芯片不支持。
- 校验失败。
- 代理认证失败。
- DNS 解析失败。
- 下载超时。
- 未分类安装器错误。

- [x] **把网络预检改为真实依赖源**

现在检查 GitHub Raw、Codex、Hermes、Node.js、npm/飞书 CLI、Obsidian 六个实际入口。预检失败只影响对应工具，不会再声称整台电脑都无法安装。

- [x] **先下载再运行远程安装器**

`run_downloaded_installer` 会验证下载内容非空且有脚本头，保留官方输出和退出码，再根据日志给出错误分类。

- [x] **验证工作区创建结果**

`mkdir` 或 `cd` 失败时立即停止安装，并提示路径、权限、只读磁盘或空间问题。

- [x] **分别检查飞书初始化和授权**

初始化失败时不再继续登录；初始化和登录失败分别给出可复制的重试命令。

- [x] **修复虚假成功状态**

- 已安装快速路径明确提示“安装检查通过，不代表已经登录”。
- 仍然提供登录/授权步骤。
- 必需项失败或被跳过时返回非零状态。
- 只检测模式不会安装，也不会声称已经登录。

---

## 任务五：修复 Windows 架构、Node、授权和完成状态

**修改文件：** `install.ps1`

**新增接口：**

- `Get-WindowsArch`
- `Core-PlatformSupported`
- 改进后的 `Node-Ok`
- 支持架构参数的 `Winget-Install`

- [x] **通过 CIM 识别真实 Windows 架构**

```powershell
function Get-WindowsArch {
  try {
    $value = (Get-CimInstance Win32_Processor -ErrorAction Stop |
      Select-Object -First 1).Architecture
    if($value -eq 12){ return 'ARM64' }
    if($value -eq 9){ return 'X64' }
  } catch {}

  $raw = if($env:PROCESSOR_ARCHITEW6432){
    $env:PROCESSOR_ARCHITEW6432
  } else {
    $env:PROCESSOR_ARCHITECTURE
  }

  if($raw -match 'ARM64'){ return 'ARM64' }
  if($raw -match 'AMD64'){ return 'X64' }
  return 'x86'
}
```

- [x] **修复 Windows ARM64 安装**

- 当真实系统是 ARM64 时，强制 Codex 官方安装器选择 `Arm64`。
- Node 的 winget 参数增加 `--architecture arm64`。
- Codex sandbox 辅助程序按 ARM64 资产下载并验证 SHA-256。

- [x] **明确拦截不支持的系统**

32 位 Windows 或 Windows 10 以前版本会停止，并说明当前 Codex、Hermes、飞书 CLI 需要 64 位 Windows 10/11。

- [x] **执行 Node/npm 健康检查**

```powershell
function Node-Ok {
  return ((Cmd-Usable 'node') -and (Cmd-Usable 'npm'))
}
```

不再因为 PATH 中存在损坏的 shim 文件就显示成功。

- [x] **让 Hermes 管理自己的 Windows 依赖**

移除安装流程中不必要的系统级 Git winget 安装。Hermes 官方安装器自行在当前用户目录管理 Git、Python 和 Node，降低 UAC 和公司设备策略造成的失败。

- [x] **保留 PowerShell 当前进程 PATH**

`Refresh-Path` 会合并系统 PATH、用户 PATH 和当前进程 PATH，不再丢失仅存在于当前会话的路径。

- [x] **修复 Windows 飞书状态**

- 初始化和授权分别检查 `$LASTEXITCODE`。
- 飞书 CLI 可用但 Agent Skills 缺失时仍判定为失败。

- [x] **修复 Windows 最终状态**

- 工作区失败立即停止。
- Codex sandbox 辅助程序缺失仍属于未完成。
- 安装不完整时设置 `$global:LASTEXITCODE = 1`。
- 最终检查包含 Codex、Hermes、飞书 CLI、Agent Skills、Node 和 npm，并明确说明未验证账号登录。

---

## 任务六：加固 Windows 启动器并同步说明文档

**修改文件：**

- `go.ps1`
- `README.md`

- [x] **增强 `go.ps1` 下载兼容性**

启用 TLS 1.2，兼容较旧的 Windows PowerShell：

```powershell
[Net.ServicePointManager]::SecurityProtocol =
  [Net.ServicePointManager]::SecurityProtocol -bor
  [Net.SecurityProtocolType]::Tls12
```

- [x] **验证下载内容**

下载结果必须达到合理长度，并包含 `function Main`。HTML 登录页、代理提示页或空响应不会再直接进入 `Invoke-Expression`。

- [x] **捕获启动器执行异常**

下载失败和执行失败分别提示 TLS、DNS、代理、公司防火墙、PowerShell 策略、权限和子下载问题，并设置非零状态。

- [x] **校验 Windows 桌面安装包**

Hermes Windows 安装包使用唯一临时文件，并通过 `Get-AuthenticodeSignature` 验证数字签名后才运行。

- [x] **更新 README**

README 已补充：

- Apple Silicon、Intel Mac、Windows x64、Windows ARM64 和 32 位 Windows 的兼容矩阵。
- Node 22 LTS、Obsidian 自动安装和 Hermes Intel 限制。
- winget、UAC、Store/公司策略、代理、权限和磁盘问题。
- 安装状态与账号登录状态的区别。
- 当前真实文件清单和验证命令。

---

## 任务七：最终需求审计

- [x] **逐项复核最初发现的问题**

已覆盖：Node 解析、Node 版本、校验和、Obsidian 文件名、损坏命令误报、Intel/旧 Mac 路由、Windows ARM64/32 位、Node/npm 检测、飞书授权、网络与错误分类、工作区失败、最终状态、启动器校验和 README 过期内容。

- [x] **执行完整自动验证**

```bash
bash tests/test_installers.sh
bash -n install.sh
bash install.sh --check
```

验证结果：

- 回归测试：51 项通过，0 项失败。
- Bash 语法检查通过。
- `install.ps1` 与 `go.ps1` 的括号、引号和代码块结构检查通过。
- Node 当前实时选择：`v22.23.1`。
- Obsidian 当前实时地址：`Obsidian-1.12.7.dmg`。
- 六个官方安装入口均返回 HTTP 200。
- 本机损坏的 Codex 被正确标红，只检测模式返回状态码 1。
- 此前要求移除的相关内容没有残留。

- [x] **记录验证边界**

当前电脑没有 Windows PowerShell，因此 Windows 部分完成了静态回归和结构检查，但尚未在真实 Windows x64、Windows ARM64 设备上执行。正式公开分发前，应在这两类设备上各运行一次只检测模式和一次完整安装流程。
