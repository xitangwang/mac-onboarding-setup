# ============================================================
#   航海家 · AI 工具一键部署助手 (Windows / PowerShell)
#   检测 -> 安装 -> 授权，全程中文引导，给零基础新手用
#
#   工具：Codex / Hermes / 飞书CLI / Obsidian
#   安装：CLI 走各家官方 PowerShell 安装器；依赖/桌面 App 走 winget；脚本内不含任何密钥
#
#   用法（在 PowerShell 里粘贴这一行；确保中文不乱码）：
#     irm https://raw.githubusercontent.com/xitangwang/mac-onboarding-setup/main/go.ps1 | iex
#   只检测不安装：先 $env:CHECK_ONLY=1; 再跑上面那行
# ============================================================

try { chcp 65001 > $null 2>&1; [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'Continue'

# ---------- 输出（纯文本标记，避免乱码）----------
function Say($m){ Write-Host $m }
function Ok($m){ Write-Host "[OK] $m" -ForegroundColor Green }
function Warn($m){ Write-Host "[!]  $m" -ForegroundColor Yellow }
function Bad($m){ Write-Host "[X]  $m" -ForegroundColor Red }
function Step($m){ Write-Host ""; Write-Host ">> $m" -ForegroundColor Cyan }
function Hr(){ Write-Host "--------------------------------------------" }

function Format-Elapsed($started){
  $span = (Get-Date) - $started
  if($span.TotalHours -ge 1){ return ("{0}小时{1}分{2}秒" -f [int]$span.TotalHours,$span.Minutes,$span.Seconds) }
  if($span.TotalMinutes -ge 1){ return ("{0}分{1}秒" -f [int]$span.TotalMinutes,$span.Seconds) }
  return ("{0}秒" -f [Math]::Max(0,[int]$span.TotalSeconds))
}
function Format-Bytes($bytes){
  if($bytes -ge 1GB){ return ("{0:N2} GB" -f ($bytes / 1GB)) }
  if($bytes -ge 1MB){ return ("{0:N1} MB" -f ($bytes / 1MB)) }
  if($bytes -ge 1KB){ return ("{0:N1} KB" -f ($bytes / 1KB)) }
  return ("$bytes B")
}
function Invoke-DownloadWithProgress {
  param(
    [Parameter(Mandatory=$true)][string]$Url,
    [Parameter(Mandatory=$true)][string]$Destination,
    [Parameter(Mandatory=$true)][string]$Name
  )
  $request=$null; $response=$null; $input=$null; $output=$null; $downloadFailed=$false
  $received=[long]0; $total=[long]-1; $started=Get-Date
  try {
    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.AllowAutoRedirect = $true
    $request.UserAgent = 'Mozilla/5.0 NavigatorInstaller/1.0'
    $request.Timeout = 30000
    $request.ReadWriteTimeout = 30000
    $request.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
    if($request.Proxy){ $request.Proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials }
    $response = $request.GetResponse()
    $total = [long]$response.ContentLength
    $input = $response.GetResponseStream()
    $output = New-Object System.IO.FileStream($Destination,[System.IO.FileMode]::Create,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None)
    $buffer = New-Object byte[] 65536
    while(($read = $input.Read($buffer,0,$buffer.Length)) -gt 0){
      $output.Write($buffer,0,$read)
      $received += $read
      $elapsed = Format-Elapsed $started
      if($total -gt 0){
        $percent = [Math]::Min(100,[int](($received * 100) / $total))
        $status = "$(Format-Bytes $received) / $(Format-Bytes $total)（$percent%），已用时 $elapsed"
        Write-Progress -Activity "下载 $Name" -Status $status -PercentComplete $percent
      } else {
        Write-Progress -Activity "下载 $Name" -Status "已下载 $(Format-Bytes $received)，已用时 $elapsed" -PercentComplete -1
      }
    }
    if($total -gt 0 -and $received -ne $total){ throw "下载不完整：应为 $total 字节，实际 $received 字节。" }
    Say "  $Name 下载完成：$(Format-Bytes $received)，耗时 $(Format-Elapsed $started)"
  } catch {
    $downloadFailed=$true
    throw
  } finally {
    if($output){ $output.Dispose() }
    if($input){ $input.Dispose() }
    if($response){ $response.Dispose() }
    if($downloadFailed){ Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue }
    Write-Progress -Activity "下载 $Name" -Completed
  }
}
function Invoke-NativeWithProgress($filePath,$argumentList,$activity){
  $started=Get-Date
  $process=$null
  try {
    $process = Start-Process -FilePath $filePath -ArgumentList $argumentList -PassThru -NoNewWindow -ErrorAction Stop
    while(-not $process.WaitForExit(1000)){
      Write-Progress -Activity $activity -Status "仍在运行，已用时 $(Format-Elapsed $started)；如有 UAC 窗口请确认" -PercentComplete -1
    }
    $process.WaitForExit()
    Say "  $activity 已结束，耗时 $(Format-Elapsed $started)，返回码 $($process.ExitCode)"
    return [int]$process.ExitCode
  } catch {
    Warn "$activity 启动失败：$_"
    return 1
  } finally {
    Write-Progress -Activity $activity -Completed
  }
}

# ---------- 状态记录 ----------
$script:INSTALLED=@(); $script:SKIPPED=@(); $script:FAILED=@()
$global:LASTEXITCODE = 0

# ---------- 工具函数 ----------
function Has($cmd){ return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }
function Cmd-Version($cmd){
  try {
    $resolved = Get-Command $cmd -ErrorAction Stop
    $path = $resolved.Path
    if([string]::IsNullOrWhiteSpace($path)){ $path = $resolved.Source }
    if(-not [string]::IsNullOrWhiteSpace($path) -and "$path" -notmatch '\.ps1$'){
      $out = & $path --version 2>$null | Select-Object -First 1
      if($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace("$out")){ return "$out" }
    }
  } catch {}
  try {
    $out = cmd /d /c "$cmd --version" 2>$null | Select-Object -First 1
    if($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace("$out")){ return "$out" }
  } catch {}
  return ""
}
function Cmd-Usable($cmd){ return (-not [string]::IsNullOrWhiteSpace((Cmd-Version $cmd))) }
function File-Version($path){
  try {
    if([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path $path)){ return "" }
    $out = & $path --version 2>$null | Select-Object -First 1
    if($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace("$out")){ return "$out" }
  } catch {}
  return ""
}
function Lark-SkillsOk {
  if([string]::IsNullOrWhiteSpace($env:USERPROFILE)){ return $false }
  return (Test-Path (Join-Path $env:USERPROFILE ".agents\skills\lark-shared\SKILL.md"))
}
# Node 是否真可用：node 和 npm 都要在（飞书 CLI 要 npm）
function Node-Ok { return ((Cmd-Usable 'node') -and (Cmd-Usable 'npm')) }
function Path-HasEntry($pathValue, $dir){
  if([string]::IsNullOrWhiteSpace($pathValue) -or [string]::IsNullOrWhiteSpace($dir)){ return $false }
  $trim = @([char]92,[char]47)
  $needle = $dir.Trim().TrimEnd($trim)
  foreach($p in ($pathValue -split ';')){
    $raw = $p.Trim().TrimEnd($trim)
    $expanded = [System.Environment]::ExpandEnvironmentVariables($raw).TrimEnd($trim)
    if($raw -ieq $needle -or $expanded -ieq $needle){ return $true }
  }
  return $false
}
function Get-UserPathRaw {
  try {
    $v = (Get-ItemProperty -Path "HKCU:\Environment" -Name Path -ErrorAction Stop).Path
    if($null -ne $v){ return "$v" }
  } catch {}
  return [System.Environment]::GetEnvironmentVariable("Path","User")
}
function Get-MachinePathRaw {
  return [System.Environment]::GetEnvironmentVariable("Path","Machine")
}
function Path-AlreadyConfigured($dir){
  return ((Path-HasEntry $env:Path $dir) -or (Path-HasEntry (Get-UserPathRaw) $dir) -or (Path-HasEntry (Get-MachinePathRaw) $dir))
}
function Set-UserPathRaw($value){
  try {
    if(Get-ItemProperty -Path "HKCU:\Environment" -Name Path -ErrorAction SilentlyContinue){
      Set-ItemProperty -Path "HKCU:\Environment" -Name Path -Value $value -ErrorAction Stop
    } else {
      New-ItemProperty -Path "HKCU:\Environment" -Name Path -Value $value -PropertyType ExpandString -Force -ErrorAction Stop | Out-Null
    }
  } catch {
    [System.Environment]::SetEnvironmentVariable("Path",$value,"User")
  }
}
function Add-UserPathEntry($dir){
  if([string]::IsNullOrWhiteSpace($dir) -or -not (Test-Path $dir)){ return $false }
  if(-not (Path-HasEntry $env:Path $dir)){ $env:Path = "$dir;$env:Path" }
  $u=Get-UserPathRaw
  if(-not (Path-HasEntry $u $dir)){
    if([string]::IsNullOrWhiteSpace($u)){ Set-UserPathRaw $dir }
    else { Set-UserPathRaw "$dir;$u" }
  }
  return $true
}
# Codex 官方 Windows 安装器默认放这里；有时装好了但当前 PowerShell PATH 没刷新。
function Codex-BinDir { return (Join-Path $env:LOCALAPPDATA "Programs\OpenAI\Codex\bin") }
function Ensure-CodexPath {
  $bin = Codex-BinDir
  $exe = Join-Path $bin "codex.exe"
  if(-not (Test-Path $exe)){ return $false }
  return (Add-UserPathEntry $bin)
}
function Codex-Ok { return (Cmd-Usable 'codex') }
function Get-WindowsArch {
  try {
    $value = (Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).Architecture
    if($value -eq 12){ return 'ARM64' }
    if($value -eq 9){ return 'X64' }
  } catch {}
  $raw = if($env:PROCESSOR_ARCHITEW6432){ $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
  if($raw -match 'ARM64'){ return 'ARM64' }
  if($raw -match 'AMD64'){ return 'X64' }
  return 'x86'
}
function Codex-FallbackArchitecture {
  if((Get-WindowsArch) -eq 'ARM64'){ return 'Arm64' }
  return 'X64'
}
function Install-CodexOfficial {
  $installer = Invoke-RestMethod https://chatgpt.com/codex/install.ps1 -ErrorAction Stop
  $nativeArch = Get-WindowsArch
  if($nativeArch -eq 'x86'){ throw "Codex 需要 64 位 Windows，当前系统是 32 位。" }
  # x64 PowerShell 在 Windows ARM 上可能把 OSArchitecture 报成 X64；ARM64 时强制改为真实架构。
  if($nativeArch -eq 'ARM64'){
    Warn "检测到 Windows ARM64；将强制 Codex 官方安装器使用原生 ARM64 包，避免装成 x64 仿真版。"
    $needle = '$architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture'
    if(-not $installer.Contains($needle)){ throw "Codex 官方安装器结构变化，无法安全应用 ARM64 兼容补丁。" }
    $installer = $installer.Replace($needle, '$architecture = "Arm64"')
  }
  $oldNonInteractive = $env:CODEX_NON_INTERACTIVE
  try {
    $env:CODEX_NON_INTERACTIVE = '1'
    Invoke-Expression $installer
  } finally {
    if($null -eq $oldNonInteractive){ Remove-Item Env:\CODEX_NON_INTERACTIVE -ErrorAction SilentlyContinue }
    else { $env:CODEX_NON_INTERACTIVE = $oldNonInteractive }
  }
}
function Repair-CodexSandboxSetup {
  $bin = Codex-BinDir
  $codex = Join-Path $bin "codex.exe"
  if(-not (Test-Path $codex)){ return $false }
  $dst = Join-Path $bin "codex-windows-sandbox-setup.exe"
  if(Test-Path $dst){ return $true }

  $candidates = @()
  $current = Join-Path $env:LOCALAPPDATA "openai-codex\current"
  $candidates += (Join-Path $current "codex-resources\codex-windows-sandbox-setup.exe")
  $candidates += (Join-Path (Split-Path -Parent $bin) "codex-resources\codex-windows-sandbox-setup.exe")
  try {
    $item = Get-Item -LiteralPath $bin -Force -ErrorAction Stop
    foreach($target in @($item.Target)){
      if(-not [string]::IsNullOrWhiteSpace($target)){
        $candidates += (Join-Path (Split-Path -Parent $target) "codex-resources\codex-windows-sandbox-setup.exe")
      }
    }
  } catch {}

  foreach($src in $candidates){
    if(Test-Path $src){
      Copy-Item -LiteralPath $src -Destination $dst -Force
      return (Test-Path $dst)
    }
  }

  try {
    $verText = (& $codex --version 2>$null | Select-Object -First 1)
    if("$verText" -notmatch '([0-9]+\.[0-9]+\.[0-9]+)'){ return $false }
    $ver = $Matches[1]
    $target = if((Codex-FallbackArchitecture) -eq 'Arm64'){ 'aarch64-pc-windows-msvc' } else { 'x86_64-pc-windows-msvc' }
    $assetName = "codex-windows-sandbox-setup-$target.exe"
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/openai/codex/releases/tags/rust-v$ver" -UseBasicParsing -ErrorAction Stop
    $asset = $release.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
    if($null -eq $asset -or [string]::IsNullOrWhiteSpace("$($asset.digest)")){ return $false }
    Invoke-DownloadWithProgress -Url $asset.browser_download_url -Destination $dst -Name "Codex sandbox 辅助程序"
    $expected = "$($asset.digest)" -replace '^sha256:',''
    $actual = (Get-FileHash -LiteralPath $dst -Algorithm SHA256 -ErrorAction Stop).Hash
    if($actual.ToLowerInvariant() -ne $expected.ToLowerInvariant()){
      Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
      return $false
    }
    return (Test-Path $dst)
  } catch { return $false }
}
function Codex-Ready { return ((Codex-Ok) -and (Repair-CodexSandboxSetup)) }
# 是否课程主力命令行工具都已装齐：这里不再卡 Obsidian / 桌面 App，避免明明 CLI 全绿却继续问安装。
function All-Installed { return ( (Codex-Ok) -and (Cmd-Usable 'hermes') -and (Cmd-Usable 'lark-cli') -and (Lark-SkillsOk) -and (Node-Ok) ) }

function Refresh-Path {
  $m=[System.Environment]::GetEnvironmentVariable("Path","Machine")
  $u=[System.Environment]::GetEnvironmentVariable("Path","User")
  $current = $env:Path
  $seen = @{}
  $merged = @()
  $trim = @([char]92,[char]47)
  foreach($source in @($m,$u,$current)){
    foreach($entry in ("$source" -split ';')){
      $entry = $entry.Trim()
      if([string]::IsNullOrWhiteSpace($entry)){ continue }
      $key = [System.Environment]::ExpandEnvironmentVariables($entry).TrimEnd($trim).ToLowerInvariant()
      if(-not $seen.ContainsKey($key)){
        $seen[$key] = $true
        $merged += $entry
      }
    }
  }
  $env:Path = ($merged -join ';')
}

# 回车=继续 / s=跳过(返回 $false) / q=退出
function Ask($prompt){
  $ans = Read-Host "$prompt  [回车=继续 / s=跳过 / q=退出]"
  if($ans -ieq 's'){ return $false }
  if($ans -ieq 'q'){ Say ""; Say "已退出。随时可重新运行，已装好的会自动跳过。"; exit 0 }
  return $true
}

function Ensure-PowerShellCliPolicy {
  try {
    $machinePolicy = Get-ExecutionPolicy -Scope MachinePolicy -ErrorAction SilentlyContinue
    $userPolicy = Get-ExecutionPolicy -Scope UserPolicy -ErrorAction SilentlyContinue
    if($machinePolicy -ne 'Undefined' -or $userPolicy -ne 'Undefined'){
      Warn "这台电脑的 PowerShell 执行策略由系统/公司策略管理，脚本不能自动修改。若 lark-cli 报无法加载 .ps1，请截图发群里。"
      return
    }
    $current = Get-ExecutionPolicy -ErrorAction SilentlyContinue
    if($current -in @('Restricted','AllSigned')){
      Warn "当前 PowerShell 禁止运行 npm 生成的 .ps1 命令启动脚本，可能导致 lark-cli 明明装了却报 UnauthorizedAccess。"
      Say "  这一步只修改「当前用户」的 PowerShell 策略为 RemoteSigned，不需要管理员；它允许本机生成的命令启动脚本运行。"
      if(Ask "按回车修复 PowerShell 命令启动策略？"){
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
        Ok "PowerShell 命令启动策略已修复"
      }
    }
  } catch { Warn "PowerShell 命令启动策略修复失败：$_" }
}

function Existing-CommandFile($dirs, $files){
  foreach($dir in $dirs){
    if([string]::IsNullOrWhiteSpace($dir)){ continue }
    foreach($file in $files){
      try { $path = Join-Path $dir $file -ErrorAction Stop } catch { continue }
      if(Test-Path $path){ return $path }
    }
  }
  return $null
}
function Command-VersionOrFile($command, $dirs, $files){
  $ver = Cmd-Version $command
  if($ver){ return $ver }
  $found = Existing-CommandFile $dirs $files
  if($found){
    Add-UserPathEntry (Split-Path -Parent $found) | Out-Null
    $ver = File-Version $found
    if($ver){ return $ver }
  }
  return ""
}
function Npm-BinDirs {
  $dirs = @()
  if(Has 'npm'){
    try {
      $prefixOutput = @(cmd /d /c "npm config get prefix" 2>$null)
      $npmRc = $LASTEXITCODE
      $prefix = ($prefixOutput | Select-Object -First 1)
      if($npmRc -eq 0 -and -not [string]::IsNullOrWhiteSpace($prefix)){
        $prefix = $prefix.Trim()
        if([System.IO.Path]::IsPathRooted($prefix)){ $dirs += $prefix }
      }
    } catch {}
  }
  if(-not [string]::IsNullOrWhiteSpace($env:APPDATA)){ $dirs += (Join-Path $env:APPDATA "npm") }
  return ($dirs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}
function Node-BinDirs {
  $dirs = @()
  if(-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)){ $dirs += (Join-Path $env:ProgramFiles "nodejs") }
  $pf86=[System.Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
  if(-not [string]::IsNullOrWhiteSpace($pf86)){ $dirs += (Join-Path $pf86 "nodejs") }
  return ($dirs | Select-Object -Unique)
}
function Git-BinDirs {
  $dirs = @()
  if(-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)){
    $dirs += (Join-Path $env:ProgramFiles "Git\cmd")
    $dirs += (Join-Path $env:ProgramFiles "Git\bin")
  }
  if(-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)){ $dirs += (Join-Path $env:LOCALAPPDATA "Programs\Git\cmd") }
  return ($dirs | Select-Object -Unique)
}
function Hermes-BinDir { return (Join-Path $env:LOCALAPPDATA "hermes\hermes-agent\venv\Scripts") }
function Repair-PathForTool($display, $command, $dirs, $files){
  if(Cmd-Usable $command){ return $null }
  $found = Existing-CommandFile $dirs $files
  if(-not $found){ return $null }
  $dir = Split-Path -Parent $found
  if(Path-AlreadyConfigured $dir){
    Refresh-Path
    if(-not (Path-HasEntry $env:Path $dir)){ $env:Path = "$dir;$env:Path" }
    if(Cmd-Usable $command){
      Say ""
      Hr
      Say "PATH 检查：$display"
      Ok "$display 环境已配置，当前脚本窗口已刷新：$command 可用了"
      Say ""
      return $true
    }
    Say ""
    Hr
    Say "PATH 检查：$display"
    Warn "$display 本体已安装，PATH 也已经包含：$dir"
    Warn "只是当前脚本窗口暂时没识别到；如果你新开终端能运行 $command，就不用再修复，脚本会继续往下走。"
    Say ""
    return $false
  }
  Say ""
  Hr
  Say "PATH 修复：$display"
  Warn "检测到 $display 本体已安装在：$dir"
  Warn "但当前 PowerShell 找不到「$command」命令，说明 PATH（命令查找目录）缺少这一项。"
  if(-not (Ask "按回车配置 PATH，让现在和新开的 PowerShell 都能找到 $command？")){ return $false }
  Add-UserPathEntry $dir | Out-Null
  Refresh-Path
  if(Cmd-Usable $command){
    Ok "$display 环境已补好：$command 可用了"
    Say ""
    return $true
  }
  Warn "$display 的 PATH 已写入，但当前窗口仍没识别；关掉 PowerShell 重开后再试 $command --version。"
  Say ""
  return $false
}
function Ensure-PathRepairs {
  $touched = $false
  foreach($spec in @(
    @{d='Codex (CLI)'; c='codex'; dirs=@(Codex-BinDir); files=@('codex.exe')},
    @{d='Hermes (CLI)'; c='hermes'; dirs=@(Hermes-BinDir); files=@('hermes.exe','hermes.cmd')},
    @{d='Node.js / npm'; c='node'; dirs=(Node-BinDirs); files=@('node.exe')},
    @{d='npm'; c='npm'; dirs=(Node-BinDirs); files=@('npm.cmd')},
    @{d='Git'; c='git'; dirs=(Git-BinDirs); files=@('git.exe')},
    @{d='飞书 CLI'; c='lark-cli'; dirs=(Npm-BinDirs); files=@('lark-cli.cmd','lark-cli.ps1')}
  )){
    $r = Repair-PathForTool $spec.d $spec.c $spec.dirs $spec.files
    if($null -ne $r){ $touched = $true }
  }
  if($touched){ Hr }
}

# ---------- 环境检测 ----------
$OSInfo = try { Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch { $null }
$OSVer  = [System.Environment]::OSVersion.Version
$Build  = if($OSInfo -and $OSInfo.BuildNumber){ [int]$OSInfo.BuildNumber } else { $OSVer.Build }
$Arch   = Get-WindowsArch
$WinName= if($OSInfo -and $OSInfo.Caption){ $OSInfo.Caption } else { "Windows" }
function Core-PlatformSupported {
  return ([Environment]::Is64BitOperatingSystem -and $Build -ge 10240 -and $Arch -in @('X64','ARM64'))
}

# ---------- winget 就绪检查 + 自动修复 ----------
function Ensure-Winget {
  if(Has 'winget'){ return $true }
  Warn "没检测到 winget（Windows 的「应用安装程序」），尝试自动注册……"
  try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop } catch {}
  Start-Sleep -Seconds 2
  if(Has 'winget'){ Ok "winget 已就绪"; return $true }
  Warn "winget 还是不可用。请打开 Microsoft Store 搜「应用安装程序 / App Installer」装一下，再重跑本脚本。"
  Say  "  商店链接：https://apps.microsoft.com/detail/9nblggh4nns1"
  return $false
}

function Winget-Install($id, $name, $architecture=''){
  if(-not (Ensure-Winget)){ return $false }
  Say "  正在用 winget 安装 $name；下面会显示下载 / 安装进度，请留意可能弹出的 UAC 窗口……"
  $wingetArgs = @('install','-e','--id',$id,'--accept-source-agreements','--accept-package-agreements')
  if($architecture -eq 'arm64'){ $wingetArgs += @('--architecture','arm64') }
  $rc = Invoke-NativeWithProgress 'winget' $wingetArgs "$name 安装"
  $script:LAST_WINGET_CODE = $rc
  Refresh-Path
  if($rc -ne 0 -and $rc -ne -1978335189){
    Warn "winget 安装 $name 返回码 $rc。可能是 Store/公司策略、UAC、网络、架构或软件源问题；下面会执行实际版本检查。"
  }
  return ($rc -eq 0 -or $rc -eq -1978335189)
}

function Pkg-Installed($id){
  if(-not (Has 'winget')){ return $false }
  $out = (winget list --id $id -e --accept-source-agreements 2>$null | Out-String)
  return ($out -match [regex]::Escape($id))
}

# ---------- 网络检测 ----------
function Test-Url($url){
  try { Invoke-WebRequest -Uri $url -TimeoutSec 8 -UseBasicParsing -ErrorAction Stop | Out-Null; return $true } catch {}
  try {
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "Mozilla/5.0")
    $wc.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
    if($wc.Proxy){ $wc.Proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials }
    $wc.DownloadString($url) | Out-Null
    return $true
  } catch { return $false }
}
function Test-AnyUrl($urls){
  foreach($url in $urls){ if(Test-Url $url){ return $true } }
  return $false
}
function Check-Network {
  Hr; Say "先检查实际下载源（仅提醒，不把所有失败都归为网络）"; Hr
  $checks = @(
    @{n='GitHub Raw'; u='https://raw.githubusercontent.com/xitangwang/mac-onboarding-setup/main/go.ps1'},
    @{n='Codex 官方安装源'; u='https://chatgpt.com/codex/install.ps1'},
    @{n='Hermes 官方安装源'; u='https://hermes-agent.nousresearch.com/install.ps1'},
    @{n='Node.js 官方源'; u='https://nodejs.org/dist/index.json'},
    @{n='npm / 飞书 CLI 源'; u='https://registry.npmjs.org/@larksuite%2fcli'},
    @{n='Obsidian 官网'; u='https://obsidian.md/download'}
  )
  foreach($check in $checks){
    if(Test-Url $check.u){ Ok "$($check.n) 可访问" }
    else { Warn "$($check.n) 当前不可访问；只影响使用该源的工具，后续会保留实际错误。" }
  }
}

# ---------- 检测清单 ----------
function Detect {
  Hr; Say "先看看你这台电脑现在的安装情况"; Hr
  Say "  本机：$WinName (build $Build) / $Arch"
  if(-not [Environment]::Is64BitProcess){ Warn "你开的是 32 位 PowerShell。建议关掉、用开始菜单里普通的「Windows PowerShell」或「终端」重开，否则有些工具可能装不上。" }
  if(-not [Environment]::Is64BitOperatingSystem -or $Arch -eq 'x86'){
    Bad "检测到 32 位 Windows：Codex、Hermes 和飞书 CLI 的当前版本都需要 64 位系统，本机无法完成主力工具安装。"
  } elseif($Build -lt 10240){
    Bad "当前 Windows 版本早于 Windows 10，不在这套工具的支持范围内。"
  }
  Say "  命令行工具(CLI)=终端里用、功能最全；桌面 App=图形界面、更直观。两者不冲突、可以都装。"
  Say "  >> 命令行工具（CLI）"
  if(Codex-Ok){ Ok "Codex (CLI) 已装" } else { Bad "Codex (CLI) 未装" }
  if(Cmd-Usable 'hermes'){ Ok "Hermes (CLI) 已装" } else { Bad "Hermes (CLI) 未装" }
  if(Cmd-Usable 'lark-cli'){ Ok "飞书 CLI 已装" } else { Bad "飞书 CLI 未装" }
  if(Lark-SkillsOk){ Ok "飞书官方 Agent Skills 已装" } else { Warn "飞书官方 Agent Skills 未补齐（装飞书 CLI 时会一起补）" }
  Say "  >> 桌面 App / 知识库（后面安装步骤会用 winget 自动判断 / 安装）"
  Say "  -- 下面是依赖，不用单独管 --"
  if(Node-Ok){ Ok "Node.js $(Cmd-Version 'node') / npm $(Cmd-Version 'npm')" }
  elseif((Has 'node') -or (Has 'npm')){ Warn "Node 或 npm 命令存在但不能正常执行（装飞书 CLI 前会修复）" }
  else { Warn "Node.js / npm 没有（装飞书 CLI 时自动装）" }
  if(Cmd-Usable 'git'){ Ok "Git 已就绪" } else { Say "  -- Git 未就绪；Hermes 官方安装器会按用户目录自行处理，不要求预装系统 Git" }
}

# ---------- 工作区 ----------
function Default-WorkspacePath {
  foreach($drive in @('D:','E:','F:')){
    $root = "$drive\"
    if(Test-Path $root){ return (Join-Path $root "AI-Workspace") }
  }
  return (Join-Path $env:USERPROFILE "AI-Workspace")
}
function Setup-Workspace {
  Step "先建一个工作区（你的知识库文件夹）"
  Say "给一个固定的文件夹放知识库 + AI 工作区，以后 Obsidian 和 AI 都在这里干活——选个你以后不会乱动的位置。"
  Say "  建议放到 C 盘以外的数据盘，C 盘通常空间小；也别放在 OneDrive 同步的「文档」里（同步大文件容易出问题、路径还会变）。"
  $default = Default-WorkspacePath
  Say "  直接回车用默认：$default"
  Say "  或粘贴你想要的完整路径（例如 D:\AI-Workspace、E:\AI-Workspace）："
  $inp = Read-Host "工作区路径"
  if([string]::IsNullOrWhiteSpace($inp)){ $script:WORKSPACE = $default } else { $script:WORKSPACE = $inp }
  try {
    New-Item -ItemType Directory -Force -Path $script:WORKSPACE -ErrorAction Stop | Out-Null
    Set-Location $script:WORKSPACE -ErrorAction Stop
    Ok "工作区：$script:WORKSPACE（已进入，后面装的工具都以这里为工作目录）"
    return $true
  } catch {
    Bad "工作区创建或进入失败：$script:WORKSPACE"
    Warn "可能原因：路径格式错误、目录不可写、磁盘只读或空间不足。原始错误：$_"
    $script:FAILED += "工作区（路径或权限）"
    return $false
  }
}

# ---------- 各 CLI 安装 ----------
function Do-Codex {
  Step "Codex —— OpenAI 的 AI 终端（命令行）"
  if(Codex-Ok){
    if(Repair-CodexSandboxSetup){ Ok "已安装，Windows sandbox 辅助程序已就绪" }
    else {
      Ok "Codex 主命令已安装"
      Warn "Windows sandbox 辅助程序未补齐；启动 Codex 时可能无法创建隔离环境。"
      $script:FAILED+="Codex Windows sandbox 辅助程序"
    }
    $script:SKIPPED+="Codex"
    return
  }
  if(-not (Ask "现在安装 Codex？")){ $script:SKIPPED+="Codex"; return }
  Say "  正在下载安装（官方 PowerShell 安装器）……"
  $ok=$true
  $started=Get-Date
  try { Install-CodexOfficial } catch { $ok=$false; Warn "安装过程报错：$_" }
  Say "  Codex 官方安装器已结束，耗时 $(Format-Elapsed $started)"
  Refresh-Path
  Ensure-CodexPath | Out-Null
  $codexExe = Join-Path (Codex-BinDir) "codex.exe"
  $codexVer = Command-VersionOrFile 'codex' @(Codex-BinDir) @('codex.exe')
  if($codexVer){
    if(Repair-CodexSandboxSetup){ Ok "Codex 安装成功，Windows sandbox 辅助程序已就绪" }
    else {
      Ok "Codex 主命令安装成功"
      Warn "Windows sandbox 辅助程序未补齐；启动 Codex 时可能无法创建隔离环境。"
      $script:FAILED+="Codex Windows sandbox 辅助程序"
    }
    $script:INSTALLED+="Codex"
  }
  elseif(-not $ok){ Bad "Codex 安装失败：可能是下载源、代理/TLS、权限、磁盘空间、系统架构或官方安装器变化。原始错误见上方。"; $script:FAILED+="Codex（安装失败）" }
  elseif(Test-Path $codexExe){
    Bad "Codex 文件存在，但直接执行 $codexExe --version 仍失败；这不是单纯 PATH 问题。"
    Say "  请保留上方安装器错误；常见原因包括文件不完整、杀毒软件隔离、架构不匹配或权限问题。"
    $script:FAILED+="Codex（文件存在但不可执行）"
  }
  else {
    Bad "Codex 安装后仍没识别到命令。"
    Say "  请截图发到群里；也可以先手动检查：$env:LOCALAPPDATA\Programs\OpenAI\Codex\bin\codex.exe --version"
    $script:FAILED+="Codex（安装后命令未识别）"
  }
}

function Do-Hermes {
  Step "Hermes Agent —— 能成长的 AI 助手"
  if(Cmd-Usable 'hermes'){ Ok "已安装"; $script:SKIPPED+="Hermes"; return }
  if(-not (Ask "现在安装 Hermes？（会自动装 Git/Python/Node 等依赖，耗时几分钟）")){ $script:SKIPPED+="Hermes"; return }
  Say "  正在装 Hermes：官方安装器会实时输出当前阶段；无法计算总百分比时请看阶段文字和耗时。"
  Warn "卡在某一步（如 Installing managed uv）超过 10 分钟完全不动 = 网络/Cloudflare 拦了下载：按 Ctrl+C 中断，先跳过 Hermes，换干净网络/IP 再单独装。"
  $ok=$true
  $started=Get-Date
  try {
    $installer = Invoke-RestMethod https://hermes-agent.nousresearch.com/install.ps1 -ErrorAction Stop
    $installerBlock = [ScriptBlock]::Create("$installer")
    & $installerBlock -SkipSetup
  } catch { $ok=$false; Warn "安装过程报错：$_" }
  Say "  Hermes 官方安装器已结束，耗时 $(Format-Elapsed $started)"
  Refresh-Path
  Add-UserPathEntry (Hermes-BinDir) | Out-Null
  if(Cmd-Usable 'hermes'){ Ok "Hermes 安装成功"; $script:INSTALLED+="Hermes" }
  elseif(-not $ok){ Bad "Hermes 安装失败：可能是 GitHub/uv/Python/Node 下载、代理、权限、磁盘空间或杀毒软件拦截。原始错误见上方。"; $script:FAILED+="Hermes（安装失败）" }
  else { Bad "Hermes 安装器结束后 hermes --version 仍失败；不能仅按 PATH 问题标记为成功。"; $script:FAILED+="Hermes（安装后不可用）" }
}

function Install-Node {
  if(Node-Ok){ return $true }
  Warn "飞书 CLI 需要可执行的 Node.js 和 npm，正在用 winget 安装 Node.js LTS。"
  $nodeArch = ''
  if((Get-WindowsArch) -eq 'ARM64'){ $nodeArch = 'arm64' }
  Winget-Install 'OpenJS.NodeJS.LTS' 'Node.js LTS' $nodeArch | Out-Null
  Refresh-Path
  foreach($dir in (Node-BinDirs)){ Add-UserPathEntry $dir | Out-Null }
  if(Node-Ok){ Ok "Node / npm 安装成功：$(Cmd-Version 'node') / npm $(Cmd-Version 'npm')"; return $true }
  Warn "Node 安装后，node --version 或 npm --version 仍失败。winget 返回码：$script:LAST_WINGET_CODE。"
  Warn "请检查 Microsoft Store/公司策略、UAC、代理、杀毒软件和系统架构；也可手动安装 Node.js LTS 后重开 PowerShell。"
  return $false
}

function Ensure-BaseDeps {
  Hr; Say "先检查飞书 CLI 的基础依赖（Node / npm）"; Hr
  Say "  Hermes 官方安装器会在当前用户目录管理 Git、Python 和 Node，不要求预装系统级 Git，也不需要管理员权限。"
  if(Node-Ok){ Ok "Node.js / npm —— 已就绪（$(Cmd-Version 'node') / npm $(Cmd-Version 'npm')）" }
  elseif(-not (Install-Node)){ Warn "Node / npm 尚未就绪；飞书 CLI 步骤会给出最终处理结果。" }
}

function Do-Larkcli {
  Step "飞书 CLI —— 让 AI 直接读写你的飞书表格 / 文档"
  if(-not (Node-Ok)){
    if(-not (Install-Node)){
      Bad "Node 自动安装失败：请检查上方 winget 返回码、Store/公司策略、UAC、网络、权限和架构；或手动安装 Node.js LTS。"
      $script:FAILED+="Node.js（飞书 CLI 依赖）"
      $script:SKIPPED+="飞书 CLI（缺 Node）"; return
    }
  }
  if(Cmd-Usable 'lark-cli'){
    Ok "已检测到飞书 CLI：$(Cmd-Version 'lark-cli')"
    Say "  为了补齐官方 AI Agent Skills，这一步会再运行一次官方安装器（已装好的会自动升级/跳过）。"
  }
  if(-not (Ask "现在安装 / 补齐飞书 CLI + 官方 AI Agent Skills？")){ $script:SKIPPED+="飞书 CLI"; return }
  Say "  通过官方安装器安装：CLI 本体 + 飞书官方 AI Agent Skills 会一起装好……"
  $rc=Invoke-NativeWithProgress 'cmd.exe' @('/d','/c','npx --yes @larksuite/cli@latest install') '飞书 CLI 安装'
  Refresh-Path
  foreach($dir in (Npm-BinDirs)){ Add-UserPathEntry $dir | Out-Null }
  if((Cmd-Usable 'lark-cli') -and (Lark-SkillsOk)){ Ok "飞书 CLI + 官方 Agent Skills 安装成功"; $script:INSTALLED+="飞书 CLI（含官方 Agent Skills）" }
  elseif(Cmd-Usable 'lark-cli'){
    Warn "飞书 CLI 已可用，但官方 Agent Skills 没检测到；本次仍未完整安装。"
    $script:FAILED+="飞书 Agent Skills"
  }
  elseif($rc -ne 0){
    Bad "飞书 CLI 安装失败（npm 返回 $rc）。可能是 npm/二进制下载源、代理、权限、磁盘空间、杀毒软件或架构问题；请保留上方原始输出。"
    $script:FAILED+="飞书 CLI（安装失败）"
  }
  else {
    Bad "安装器返回成功，但 lark-cli --version 仍失败；不能仅按 PATH 问题标记为成功。"
    $script:FAILED+="飞书 CLI（安装后不可用）"
  }
}

function Do-Obsidian {
  Step "Obsidian —— 你的 AI 第二大脑 / 知识库（核心）"
  if(Pkg-Installed 'Obsidian.Obsidian'){ Ok "已安装"; $script:SKIPPED+="Obsidian"; return }
  if(-not (Ask "现在安装 Obsidian（核心知识库）？")){ $script:SKIPPED+="Obsidian"; return }
  Winget-Install 'Obsidian.Obsidian' 'Obsidian' | Out-Null
  if(Pkg-Installed 'Obsidian.Obsidian'){ Ok "Obsidian 安装成功"; $script:INSTALLED+="Obsidian"; return }
  Warn "Obsidian 自动安装未完成。可能是 winget/Store 策略、UAC、网络、权限或软件源问题；手动下载：https://obsidian.md/download"
  Start-Process "https://obsidian.md/download" 2>$null
  $script:FAILED+="Obsidian（请手动装）"
}

# ---------- 授权 / 登录 ----------
function Auth-Phase {
  Hr; Say "第二步：一个个带你登录 / 授权"; Hr
  Say "每个工具会打开浏览器或问你几个问题，跟着走就行。脚本不碰你的任何密码。"

  if(Cmd-Usable 'codex'){
    Step "1) Codex OAuth（用你的 ChatGPT 账号）"
    Say "脚本不自动打开 OAuth 登录。需要官方账号登录时，之后手动运行：codex login"
    Say "  远程/无浏览器环境可用：codex login --device-auth"
  }
  if(Cmd-Usable 'lark-cli'){
    Step "2) 配置并授权 飞书 CLI"
    if(Ask "现在配置并授权飞书 CLI？"){
      cmd /d /c "lark-cli config init --new"
      if($LASTEXITCODE -ne 0){
        Warn "飞书初始化失败，未继续登录。稍后手动运行：lark-cli config init --new"
        $script:FAILED += "飞书初始化"
      } else {
        cmd /d /c "lark-cli auth login --recommend"
        if($LASTEXITCODE -ne 0){
          Warn "飞书授权失败或被取消。稍后手动运行：lark-cli auth login --recommend"
          $script:FAILED += "飞书授权"
        } else { Ok "飞书初始化和授权流程已完成" }
      }
    }
  }
  if(Cmd-Usable 'hermes'){
    Step "3) Hermes —— 装好就行，先不用配"
    Ok "Hermes 命令行已就绪（hermes --version 能看到版本就成）。"
    Say "  Hermes 的模型 / provider 配置请按 Hermes 官方文档进行。"
  }
}

# ---------- 图形界面：桌面客户端 ----------
function Do-Clients {
  Say ""
  Say "1) Codex 桌面 App（图形界面，需 ChatGPT 账号）"
  if(Pkg-Installed '9PLM9XGG6VKS'){ Ok "Codex 桌面 App 已安装" }
  elseif(Ask "现在装 Codex 桌面 App？（走 Microsoft 商店）"){
    if(Ensure-Winget){
      Say "  正在从 Microsoft Store 安装 Codex App；winget 会显示可用的下载 / 安装进度……"
      $storeArgs=@('install','-e','--id','9PLM9XGG6VKS','-s','msstore','--accept-source-agreements','--accept-package-agreements')
      $storeRc=Invoke-NativeWithProgress 'winget' $storeArgs 'Codex 桌面 App 安装'
      if($storeRc -eq 0){ Ok "Codex 桌面 App 安装成功（开始菜单搜 Codex 打开）"; $script:INSTALLED+="Codex 桌面 App" }
      else { Warn "Codex App 没装成功（商店源可能要登录或网络问题）。可去 Microsoft Store 搜 Codex 手动装。" }
    }
  }

  Say ""
  Say "2) Hermes 桌面 App（图形界面，比命令行友好；和命令行 Hermes 共享同一份配置）"
  if(Cmd-Usable 'hermes'){
    Say "  你已装命令行 Hermes，可用官方命令 hermes desktop 构建并打开桌面 App（首次几分钟，会显示实时输出和耗时）。"
    if(Ask "现在构建并打开 Hermes 桌面 App？（完成后脚本再继续）"){
      $desktopRc=Invoke-NativeWithProgress 'cmd.exe' @('/d','/c','hermes desktop') 'Hermes 桌面 App 构建'
      if($desktopRc -eq 0){ Ok "Hermes 桌面 App 构建流程已结束；如成功会自动打开。" }
      else { Warn "Hermes 桌面 App 构建失败（返回码 $desktopRc）；可去 https://hermes-agent.nousresearch.com/desktop 下载安装包。" }
    }
  } elseif(Ask "下载并运行 Hermes 桌面 App 安装包？"){
    $exe=Join-Path $env:TEMP ("Hermes-Setup-{0}.exe" -f [guid]::NewGuid().ToString('N'))
    Say "  正在下载（官方源，约 8MB）……"
    try {
      Invoke-DownloadWithProgress -Url "https://hermes-assets.nousresearch.com/Hermes-Setup.exe" -Destination $exe -Name "Hermes 桌面 App"
      $signature = Get-AuthenticodeSignature -LiteralPath $exe
      if($signature.Status -ne 'Valid'){ throw "安装包数字签名无效：$($signature.Status)" }
      Start-Process $exe -Wait
      Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue
      Say "  Hermes 桌面安装器已关闭；如已完成安装，可从开始菜单打开。"
    } catch {
      Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue
      Warn "Hermes 桌面安装包下载或签名验证失败：可能是网络、代理/TLS、权限、磁盘空间或安全软件拦截。可手动下载：https://hermes-agent.nousresearch.com/desktop；原始错误：$_"
    }
  }
}

# ---------- 小结 ----------
function Summary {
  Hr; Say "安装小结"; Hr
  if($script:INSTALLED.Count -gt 0){ Ok "本次新装好："; $script:INSTALLED | ForEach-Object { Say "    - $_" } }
  if($script:SKIPPED.Count  -gt 0){ Say "跳过 / 本来就有："; $script:SKIPPED | ForEach-Object { Say "    - $_" } }
  if($script:FAILED.Count   -gt 0){ Bad "还没搞定（需处理）："; $script:FAILED | ForEach-Object { Say "    - $_" }; Say "  把上面这几行截图发到群里。" }
}

function Show-FinalCheck {
  Hr; Say "最后确认：逐个检查命令是否能用"; Hr
  $codexVer = Command-VersionOrFile 'codex' @(Codex-BinDir) @('codex.exe')
  if($codexVer){ Ok "Codex 可用：$codexVer" }
  else {
    Bad "Codex 未识别"
    Say "  修复命令（复制这一行重跑新版一键脚本）："
    Say '  irm https://raw.githubusercontent.com/xitangwang/mac-onboarding-setup/main/go.ps1 | iex'
  }
  $hermesVer = Cmd-Version 'hermes'
  if($hermesVer){ Ok "Hermes 可用：$hermesVer" } else { Bad "Hermes 未识别" }
  $larkVer = Cmd-Version 'lark-cli'
  if($larkVer){ Ok "飞书 CLI 可用：$larkVer" } else { Bad "飞书 CLI 未识别" }
  if(Lark-SkillsOk){ Ok "飞书官方 Agent Skills 已就绪" } else { Bad "飞书官方 Agent Skills 未补齐" }
  if(Node-Ok){ Ok "Node / npm 可用：$(Cmd-Version 'node') / npm $(Cmd-Version 'npm')" } else { Bad "Node 或 npm 不可用" }
  Say "  以上只验证本机命令，不代表 Codex / 飞书账号已经登录。"
}

# ---------- 主流程 ----------
function Banner {
  Say "============================================"
  Say "   航海家 · AI 工具一键部署助手 (Windows)"
  Say "============================================"
}

function Main {
  if($env:CHECK_ONLY -eq '1'){
    Banner; Check-Network; Detect; Say ""; Say "（这是只检测模式，没有安装任何东西；也没有检查账号是否已登录）"
    if(All-Installed){ $global:LASTEXITCODE = 0 } else { $global:LASTEXITCODE = 1 }
    return
  }
  Clear-Host
  Banner
  Say "这个脚本帮你检测、安装、并带你登录 6/6 大课要用的工具。"
  Say "工具都从各家官方源下载，脚本里不含任何密钥。"
  Say "按提示回车即可；不想装某个就输 s 跳过；想退出输 q。"
  Check-Network
  Ensure-PowerShellCliPolicy
  Ensure-PathRepairs
  Detect
  if(-not (Core-PlatformSupported)){
    Hr
    if(-not [Environment]::Is64BitOperatingSystem -or $Arch -eq 'x86'){
      Bad "32 位 Windows 无法安装当前版本的 Codex、Hermes 和飞书 CLI；请更换 64 位 Windows 10/11 设备。"
    } else {
      Bad "当前系统不在支持范围内：需要 64 位 Windows 10/11（x64 或 ARM64）。"
    }
    $global:LASTEXITCODE = 1
    return
  }
  if(All-Installed){
    if(-not (Repair-CodexSandboxSetup)){
      Warn "Codex 可运行，但 Windows sandbox 辅助程序未补齐。"
      $script:FAILED += "Codex Windows sandbox 辅助程序"
    }
    Hr; Ok "安装检查通过，不代表已经登录：主力命令行工具无需重新安装。"
    Say "  已确认：Codex / Hermes / 飞书 CLI + 官方 Agent Skills / Node.js 可以执行。"
    Say "  Obsidian 和桌面 App 属于图形界面补充；需要时再单独装，不再卡住主流程。"
    Show-FinalCheck
    if(Ask "进入登录 / 授权检查？"){ Auth-Phase }
    Summary
    if($script:FAILED.Count -gt 0){
      Hr; Bad "安装本体可用，但仍有未完成项。"
      $global:LASTEXITCODE = 1
    } else {
      Hr; Ok "安装检查结束；请按上方提示完成账号登录。"
      $global:LASTEXITCODE = 0
    }
    return
  }
  Hr; Say "第一步：逐个检查并安装"; Hr
  if(-not (Ask "开始安装流程？")){ Say "好的，下次再来。已装好的不会重复装。"; return }
  if(-not (Setup-Workspace)){ Summary; $global:LASTEXITCODE = 1; return }
  Ensure-BaseDeps
  Do-Codex
  Do-Hermes
  Do-Larkcli
  Do-Obsidian
  Do-Clients
  Ensure-PowerShellCliPolicy
  Ensure-PathRepairs
  Say ""
  if(Ask "进入第二步：登录授权？"){ Auth-Phase }
  Summary
  Show-FinalCheck
  if($script:FAILED.Count -gt 0 -or -not (All-Installed)){
    Hr; Bad "流程结束，但仍有必需项未完成；本次不能标记为全部就绪。"
    Say "请处理上面的具体错误后重跑；已验证可用的工具会自动跳过。"
    $global:LASTEXITCODE = 1
  } else {
    Hr; Ok "安装流程完成；命令均已通过版本检测。"
    Say "建议重开 PowerShell，再运行各工具的 --version，并按上方提示确认账号登录。"
    $global:LASTEXITCODE = 0
  }
}

if($env:INSTALLER_LIB_ONLY -ne '1'){ Main }
