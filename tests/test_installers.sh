#!/bin/bash

set -o pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PASS_COUNT=0
FAIL_COUNT=0

pass(){
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS  %s\n' "$1"
}

fail(){
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL  %s\n' "$1" >&2
}

assert_eq(){
  local actual="$1" expected="$2" name="$3"
  if [ "$actual" = "$expected" ]; then pass "$name"; else fail "$name (expected [$expected], got [$actual])"; fi
}

assert_contains(){
  local actual="$1" expected="$2" name="$3"
  case "$actual" in *"$expected"*) pass "$name" ;; *) fail "$name (missing [$expected] in [$actual])" ;; esac
}

assert_true(){
  local name="$1"; shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}

assert_false(){
  local name="$1"; shift
  if "$@"; then fail "$name"; else pass "$name"; fi
}

assert_file_contains(){
  local file="$1" expected="$2" name="$3"
  if grep -qF -- "$expected" "$ROOT/$file"; then pass "$name"; else fail "$name (missing [$expected])"; fi
}

assert_file_not_contains(){
  local file="$1" unwanted="$2" name="$3"
  if grep -qF -- "$unwanted" "$ROOT/$file"; then fail "$name (found [$unwanted])"; else pass "$name"; fi
}

assert_ascii_file(){
  local file="$1" name="$2"
  if LC_ALL=C tr -d '\11\12\15\40-\176' < "$ROOT/$file" | grep -q .; then fail "$name (contains non-ASCII bytes)"; else pass "$name"; fi
}

printf '%s\n' '== macOS behavior =='
if grep -qF 'INSTALLER_LIB_ONLY' "$ROOT/install.sh"; then
  INSTALLER_LIB_ONLY=1
  export INSTALLER_LIB_ONLY
  # shellcheck source=../install.sh
  . "$ROOT/install.sh"

  healthy_tool(){ printf '%s\n' 'healthy-tool 1.0.0'; }
  broken_tool(){ return 1; }
  assert_true 'healthy command is usable' command_ok healthy_tool
  assert_false 'broken command is not usable' command_ok broken_tool
  function_exists(){ type "$1" >/dev/null 2>&1; }
  assert_true 'PATH repair uses a tool health dispatcher' function_exists tool_ok
  assert_true 'Node architecture mapping helper exists' function_exists node_archive_arch

  codex(){ return 1; }
  assert_false 'broken Codex is not reported installed' codex_ok
  if type tool_ok >/dev/null 2>&1; then assert_false 'PATH repair rejects broken Codex' tool_ok codex; fi
  unset -f codex

  assert_true 'Hermes supports Apple Silicon macOS 12' hermes_supported_on_mac arm64 12
  assert_false 'Hermes rejects Intel Mac' hermes_supported_on_mac x86_64 14
  assert_false 'Hermes rejects old Apple Silicon macOS' hermes_supported_on_mac arm64 11
  assert_true 'Codex desktop supports Intel macOS 14' codex_app_supported_on_mac x86_64 14
  assert_true 'Codex desktop supports Apple Silicon macOS 14' codex_app_supported_on_mac arm64 14
  assert_false 'Codex desktop rejects macOS 13' codex_app_supported_on_mac arm64 13
  assert_true 'Codex desktop exposes an automatic installer' function_exists install_codex_desktop_app
  codex_desktop_app_installed(){ return 0; }
  desktop_detect_output=$(detect)
  assert_contains "$desktop_detect_output" 'ChatGPT 桌面 App（内含 Codex）—— 已装' 'macOS detection reports the merged ChatGPT/Codex desktop app'
  if function_exists node_archive_arch; then
    assert_eq "$(node_archive_arch arm64)" 'darwin-arm64' 'Node maps Apple Silicon correctly'
    assert_eq "$(node_archive_arch x86_64)" 'darwin-x64' 'Node maps Intel correctly'
    assert_false 'Node rejects unknown Mac architecture' node_archive_arch riscv64
  fi

  node_json='[{"version":"v26.5.0","lts":false},{"version":"v24.18.0","lts":"Krypton"},{"version":"v22.22.0","lts":"Jod"}]'
  node_version=$(printf '%s' "$node_json" | node_version_from_index)
  assert_eq "$node_version" 'v22.22.0' 'Node parser selects Node 22 LTS without matching the key name'

  obsidian_json='{"assets":[{"browser_download_url":"https://example.invalid/Obsidian-1.12.7.dmg"}]}'
  obsidian_url=$(printf '%s' "$obsidian_json" | obsidian_dmg_url_from_json)
  assert_eq "$obsidian_url" 'https://example.invalid/Obsidian-1.12.7.dmg' 'Obsidian parser accepts versioned DMG names'

  permission_hint=$(printf '%s' 'cp: Permission denied' | failure_hint_from_log)
  disk_hint=$(printf '%s' 'No space left on device' | failure_hint_from_log)
  platform_hint=$(printf '%s' 'Unsupported architecture' | failure_hint_from_log)
  assert_contains "$permission_hint" '权限' 'permission failures get an actionable hint'
  assert_contains "$disk_hint" '磁盘空间' 'disk failures get an actionable hint'
  assert_contains "$platform_hint" '系统或芯片' 'platform failures get an actionable hint'
else
  fail 'install.sh supports side-effect-free library loading'
fi

assert_file_contains 'install.sh' 'SHASUMS256.txt' 'Node archive checksum is verified'
assert_file_contains 'install.sh' '[ -d "/Applications/ChatGPT.app" ]' 'macOS recognizes the current ChatGPT desktop app'
assert_file_contains 'install.sh' 'https://persistent.oaistatic.com/codex-app-prod/ChatGPT.dmg' 'macOS uses the official OpenAI desktop DMG'
assert_file_contains 'install.sh' 'hdiutil verify "$dmg"' 'macOS verifies the OpenAI desktop DMG'
assert_file_contains 'install.sh' 'TeamIdentifier=2DC432GLL2' 'macOS verifies the OpenAI signing team'
assert_file_contains 'install.sh' 'com.openai.codex' 'macOS verifies the current desktop bundle identifier'
assert_file_not_contains 'install.sh' '打开 Codex App 下载页？' 'macOS no longer stops at the Codex download page'
installed_branch=$(awk '/if all_installed; then/{found=1} found{print} found && /return 0/{exit}' "$ROOT/install.sh")
assert_contains "$installed_branch" 'do_clients' 'macOS still offers desktop installation when CLI tools are already ready'
assert_file_not_contains 'install.sh' 'universal\.dmg' 'Obsidian does not depend on obsolete universal.dmg naming'
assert_file_not_contains 'install.sh' 'https://www.google.com' 'network precheck only uses actual dependencies'
assert_file_contains 'install.sh' '飞书初始化失败' 'macOS reports Lark initialization failure'
assert_file_contains 'install.sh' '安装检查通过，不代表已经登录' 'installed-only path does not imply authentication'

printf '%s\n' '== Windows static guards =='
assert_file_contains 'install.ps1' 'function Get-WindowsArch' 'Windows has native architecture detection'
assert_file_contains 'install.ps1' 'Get-CimInstance Win32_Processor' 'Windows architecture detection uses CIM'
assert_file_contains 'install.ps1' "if((Get-WindowsArch) -eq 'ARM64')" 'Windows ARM64 is handled explicitly'
assert_file_contains 'install.ps1' "'--architecture','arm64'" 'Node winget install requests ARM64 explicitly'
assert_file_contains 'install.ps1' "function Node-Ok { return ((Cmd-Usable 'node') -and (Cmd-Usable 'npm')) }" 'Windows executes Node and npm health checks'
assert_file_contains 'install.ps1' '$current = $env:Path' 'Windows PATH refresh preserves process-only entries'
npm_dirs_branch=$(awk '/^function Npm-BinDirs /{found=1} found{print} found && /^}/{exit}' "$ROOT/install.ps1")
assert_contains "$npm_dirs_branch" '$npmRc -eq 0' 'Windows ignores npm prefix output when npm exits unsuccessfully'
assert_contains "$npm_dirs_branch" '[System.IO.Path]::IsPathRooted' 'Windows only accepts an absolute npm prefix path'
command_file_branch=$(awk '/^function Existing-CommandFile/{found=1} found{print} found && /^}/{exit}' "$ROOT/install.ps1")
assert_contains "$command_file_branch" 'catch { continue }' 'Windows skips malformed command directory candidates'
assert_file_contains 'install.ps1' '32 位 Windows' '32-bit Windows gets an explicit unsupported message'
assert_file_contains 'install.ps1' '飞书初始化失败' 'Windows reports Lark initialization failure'
assert_file_contains 'install.ps1' '飞书授权失败' 'Windows reports Lark authorization failure'
assert_file_contains 'install.ps1' '$script:FAILED+="飞书 Agent Skills"' 'missing Windows Lark skills remain a failure'
assert_file_contains 'install.ps1' '$script:FAILED+="Codex Windows sandbox 辅助程序"' 'missing Codex sandbox helper remains a failure'
assert_file_contains 'install.ps1' '$global:LASTEXITCODE = 1' 'Windows exposes incomplete final status'
assert_file_contains 'install.ps1' 'Get-FileHash' 'downloaded Codex sandbox helper is checksum verified'
assert_file_contains 'install.ps1' 'Get-AuthenticodeSignature' 'downloaded Windows desktop installer is signature verified'
assert_file_not_contains 'install.ps1' '17763' 'Windows does not enforce an unsupported hard-coded Codex build cutoff'
assert_file_not_contains 'install.ps1' "Winget-Install 'Git.Git'" 'Hermes is allowed to manage its own Git dependency'
assert_file_not_contains 'install.ps1' '$exe="$env:TEMP\Hermes-Setup.exe"' 'Windows desktop download uses a unique temporary file'
assert_file_not_contains 'install.sh' 'local dmg="/tmp/Hermes-Setup.dmg"' 'macOS desktop download uses a unique temporary file'

printf '%s\n' '== bootstrap and documentation =='
assert_file_contains 'go.ps1' 'Tls12' 'Windows bootstrap enables TLS 1.2'
assert_file_contains 'go.ps1' "-notmatch 'function Main'" 'Windows bootstrap validates downloaded installer content'
assert_file_contains 'go.ps1' 'Installer execution failed' 'Windows bootstrap reports execution failure'
assert_file_contains 'go.ps1' 'Start-Transcript' 'Windows bootstrap automatically records a diagnostic log'
assert_file_contains 'go.ps1' 'Read-Host' 'Windows bootstrap pauses after a fatal failure'
assert_ascii_file 'go.ps1' 'Windows bootstrap remains ASCII-safe for legacy PowerShell'
assert_file_contains 'README.md' 'cmd /k powershell' 'Windows one-click command keeps the parent window open'
assert_file_not_contains 'README.md' '有 Homebrew 就自动装' 'README removes stale Homebrew behavior'
assert_file_not_contains 'README.md' '组长速查.md' 'README does not list missing group-lead guide'
assert_file_not_contains 'README.md' '直播大纲.md' 'README does not list missing livestream guide'
assert_file_contains 'README.md' 'Intel Mac' 'README documents Intel Mac limitations'
assert_file_contains 'README.md' 'Windows ARM64' 'README documents Windows ARM64 support'
assert_file_contains 'README.md' 'Mac 自动下载并安装官方 ChatGPT 桌面 App（内含 Codex）' 'README documents automatic Codex desktop installation'

printf '\nAssertions: %s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
