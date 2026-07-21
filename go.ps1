# ============================================================
#  Navigator AI - one-click bootstrap for Windows (pure ASCII)
#
#  Why this file exists:
#  The real installer (install.ps1) contains Chinese text. On older
#  Windows PowerShell, piping a UTF-8 script straight into `iex` can
#  garble those characters. This tiny launcher is ASCII-only, so it
#  never garbles. It forces the console to UTF-8, then downloads and
#  runs install.ps1 with an explicit UTF-8 decode. End result: the
#  student only pastes one clean line:
#
#     irm https://raw.githubusercontent.com/xitangwang/mac-onboarding-setup/main/go.ps1 | iex
#
#  Detect-only mode: set $env:CHECK_ONLY=1 before running the line above.
# ============================================================

$ErrorActionPreference = 'Stop'
try { chcp 65001 > $null 2>&1 } catch {}
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$ProgressPreference = 'SilentlyContinue'
$global:LASTEXITCODE = 0
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}

$installers = @(
    'https://github.com/xitangwang/mac-onboarding-setup/raw/main/install.ps1',
    'https://raw.githubusercontent.com/xitangwang/mac-onboarding-setup/main/install.ps1'
)

try {
    $code = $null
    $lastDownloadError = $null
    foreach ($installer in $installers) {
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Encoding = [System.Text.Encoding]::UTF8
            $wc.Headers.Add('User-Agent', 'Mozilla/5.0')
            $wc.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
            if ($wc.Proxy) { $wc.Proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials }
            $candidate = $wc.DownloadString($installer)
            if([string]::IsNullOrWhiteSpace($candidate)){ throw "empty response" }
            if($candidate.Length -lt 1000 -or $candidate -notmatch 'function Main'){
                throw "downloaded content is not the expected installer"
            }
            $code = $candidate
            break
        }
        catch { $lastDownloadError = $_ }
    }
    if (-not $code) { throw "download failed: $lastDownloadError" }
}
catch {
    Write-Host ""
    Write-Host "[X] Download failed - cannot reach the installer." -ForegroundColor Red
    Write-Host "    Browser access is not enough if PowerShell does not use the same proxy." -ForegroundColor Yellow
    Write-Host "    Also check TLS 1.2, DNS, company firewall, and whether GitHub Raw is blocked." -ForegroundColor Yellow
    Write-Host "    Detail: $_" -ForegroundColor DarkYellow
    $global:LASTEXITCODE = 1
    return
}

try {
    Invoke-Expression $code
}
catch {
    Write-Host ""
    Write-Host "[X] Installer execution failed." -ForegroundColor Red
    Write-Host "    This can be caused by a script format change, PowerShell policy, permissions, or a blocked child download." -ForegroundColor Yellow
    Write-Host "    Detail: $_" -ForegroundColor DarkYellow
    $global:LASTEXITCODE = 1
    return
}
