#!/usr/bin/env bash
set -euo pipefail

SELF="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")"
MARKER='__GPM_MANAGER_EMBEDDED_POWERSHELL_PAYLOAD_BELOW__'
TMP_DIR="${XDG_RUNTIME_DIR:-/tmp}/github-pages-manager-single-${USER:-user}-$$"
PS1_FILE="$TMP_DIR/github-pages-manager-linux.ps1"

install_pwsh_if_missing() {
  if command -v pwsh >/dev/null 2>&1; then
    return 0
  fi

  echo "[info] PowerShell Core (pwsh) yok. Kurulum deneniyor..."

  if ! command -v sudo >/dev/null 2>&1; then
    echo "[hata] sudo bulunamadi. Once PowerShell Core'u manuel kurman gerekiyor."
    exit 1
  fi

  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
  fi

  sudo apt update
  sudo apt install -y wget apt-transport-https software-properties-common gpg ca-certificates

  UBUNTU_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-noble}}"
  case "$UBUNTU_CODENAME" in
    noble|wilma|xia) MS_VER="24.04" ;;
    jammy|vera|victoria|virginia|vanessa) MS_VER="22.04" ;;
    focal|una|uma|ulyssa|ulyana) MS_VER="20.04" ;;
    *) MS_VER="24.04" ;;
  esac

  DEB="/tmp/packages-microsoft-prod.deb"
  wget -q "https://packages.microsoft.com/config/ubuntu/${MS_VER}/packages-microsoft-prod.deb" -O "$DEB"
  sudo dpkg -i "$DEB"
  sudo apt update
  sudo apt install -y powershell

  if ! command -v pwsh >/dev/null 2>&1; then
    echo "[hata] pwsh kurulamadı."
    exit 1
  fi
}

cleanup() {
  rm -rf "$TMP_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

install_pwsh_if_missing
mkdir -p "$TMP_DIR"

awk -v marker="$MARKER" '
  found { print }
  $0 == marker { found = 1 }
' "$SELF" > "$PS1_FILE"

if [ ! -s "$PS1_FILE" ]; then
  echo "[hata] Gömülü PowerShell payload çıkarılamadı. Dosya bozulmuş olabilir."
  exit 1
fi

chmod +x "$PS1_FILE"
export BAT_FILE="$SELF"
exec pwsh -NoProfile -ExecutionPolicy Bypass -File "$PS1_FILE" "$@"

exit 0
__GPM_MANAGER_EMBEDDED_POWERSHELL_PAYLOAD_BELOW__
#!/usr/bin/env pwsh

$ErrorActionPreference = "Stop"

function Test-GpmLinux {
    return (($PSVersionTable.Platform -eq "Unix") -or ($IsLinux -eq $true))
}

function Get-GpmPowerShellCommand {
    if (Test-GpmLinux) {
        $pwsh = Get-Command "pwsh" -ErrorAction SilentlyContinue

        if ($null -ne $pwsh) {
            return $pwsh.Source
        }
    }

    $powershell = Get-Command "powershell" -ErrorAction SilentlyContinue

    if ($null -ne $powershell) {
        return $powershell.Source
    }

    $fallbackPwsh = Get-Command "pwsh" -ErrorAction SilentlyContinue

    if ($null -ne $fallbackPwsh) {
        return $fallbackPwsh.Source
    }

    return "powershell"
}

function Get-GpmCurlCommand {
    if (Test-GpmLinux) {
        $curl = Get-Command "curl" -ErrorAction SilentlyContinue

        if ($null -ne $curl) {
            return $curl.Source
        }

        return $null
    }

    $curlExe = Get-Command "curl.exe" -ErrorAction SilentlyContinue

    if ($null -ne $curlExe) {
        return $curlExe.Source
    }

    return $null
}

if (Test-GpmLinux) {
    if ([string]::IsNullOrWhiteSpace($env:BAT_FILE)) {
        $env:BAT_FILE = $PSCommandPath
    }

    $script:GpmHome = [Environment]::GetFolderPath("UserProfile")
    if ([string]::IsNullOrWhiteSpace($script:GpmHome)) { $script:GpmHome = $HOME }

    $script:GpmDataRoot = $env:XDG_DATA_HOME
    if ([string]::IsNullOrWhiteSpace($script:GpmDataRoot)) { $script:GpmDataRoot = Join-Path $script:GpmHome ".local/share" }

    $script:GpmConfigRoot = $env:XDG_CONFIG_HOME
    if ([string]::IsNullOrWhiteSpace($script:GpmConfigRoot)) { $script:GpmConfigRoot = Join-Path $script:GpmHome ".config" }

    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) { $env:APPDATA = $script:GpmDataRoot }
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { $env:LOCALAPPDATA = $script:GpmDataRoot }
    if ([string]::IsNullOrWhiteSpace($env:TEMP)) { $env:TEMP = [System.IO.Path]::GetTempPath() }
    if ([string]::IsNullOrWhiteSpace($env:TMP)) { $env:TMP = [System.IO.Path]::GetTempPath() }
}

try {
    $script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [Console]::InputEncoding = $script:Utf8NoBom
    [Console]::OutputEncoding = $script:Utf8NoBom
    $OutputEncoding = $script:Utf8NoBom
}
catch {
}

function Set-ConsoleVisualProfile {
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class GpmConsoleFont {
    [StructLayout(LayoutKind.Sequential)]
    public struct COORD {
        public short X;
        public short Y;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CONSOLE_FONT_INFOEX {
        public uint cbSize;
        public uint nFont;
        public COORD dwFontSize;
        public int FontFamily;
        public int FontWeight;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string FaceName;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetStdHandle(int nStdHandle);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetCurrentConsoleFontEx(IntPtr consoleOutput, bool maximumWindow, ref CONSOLE_FONT_INFOEX consoleCurrentFontEx);
}
"@ -ErrorAction SilentlyContinue

        $handle = [GpmConsoleFont]::GetStdHandle(-11)

        foreach ($height in @(32, 30, 28, 26, 24, 22)) {
            $font = New-Object GpmConsoleFont+CONSOLE_FONT_INFOEX
            $font.cbSize = [Runtime.InteropServices.Marshal]::SizeOf([type]"GpmConsoleFont+CONSOLE_FONT_INFOEX")
            $font.nFont = 0
            $font.dwFontSize = New-Object GpmConsoleFont+COORD
            $font.dwFontSize.X = 0
            $font.dwFontSize.Y = [int16]$height
            $font.FontFamily = 54
            $font.FontWeight = 400
            $font.FaceName = "Consolas"

            if ([GpmConsoleFont]::SetCurrentConsoleFontEx($handle, $false, [ref]$font)) {
                break
            }
        }
    }
    catch {
    }

    try {
        mode con: cols=100 lines=30 | Out-Null
    }
    catch {
    }
}

Set-ConsoleVisualProfile

$AppVersion = "2.0.6"
$UpdateManifestUrl = "https://raw.githubusercontent.com/vengeance3355/github-pages-manager-updates/main/latest.json"
$ErrorReportRepo = "vengeance3355/github-pages-manager-updates"
$TelemetryKeyId = "1271c5d9cd164324"
$TelemetryPublicKey = "PFJTQUtleVZhbHVlPjxNb2R1bHVzPnlERlVabnlhMGpac2diQ1d4NnBPNXJ0aCtZVmJBSm5VelNxVW13OG1OWjh0RVNZMXBJaWRqRXZ2YVBVMHoyUHd1SlFFSTVBUHIrNnFmeHJSVzB5ZHZPY2l4VFJsdkViNmttZkRwR2ZKZGVoWWp4R0hRWWRwRVUrM1hQT3d3RXJsemRVQkpOOXJTWDBUL2YxeGtRenhsSGVUNTRKUDlFMnpOb1dLbTRYU3g2VG1vSURqeW9FcXJLSnFOVnU2M2Z5SHltVnU3aW50OGhUNkFNaFBsUHV1akl5c3Q0M25GWDU2M2dMaENSakttdzNBbSt6QU8veTNyMUE4bWwwRExMRlQ3bXZyM2tudllQWTdEZE9WUUQ4V2VNTlMyMEJOUlF5a2kxclpFYlUxYldkcE1Oc2xVTW9kK1VGRHg5MGFxZmU3UWJSTVdKS3g2cjBDSzhhVGFNSzhGUT09PC9Nb2R1bHVzPjxFeHBvbmVudD5BUUFCPC9FeHBvbmVudD48L1JTQUtleVZhbHVlPg=="
$StoreDir = Join-Path $env:APPDATA "GithubPagesPublisher"
$DbPath = Join-Path $StoreDir "repos.json"
$WorktreesDir = Join-Path $StoreDir "worktrees"
$UpdateCheckCachePath = Join-Path $StoreDir "update-check.json"
$UpdateApplyDiagPath = Join-Path (Join-Path $StoreDir "updates") "apply-update-last.json"
$UpdateApplyReportCachePath = Join-Path (Join-Path $StoreDir "updates") "apply-update-report-last.json"
$ClientStatusCachePath = Join-Path $StoreDir "client-status.json"
$ClientStatusDiagPath = Join-Path $StoreDir "client-status-last.json"
$ClientStatusSchemaVersion = 3
$HttpTimeoutSeconds = 5
$AdminConfigPath = Join-Path (Join-Path $env:APPDATA "GithubPagesPublisherAdmin") "admin.json"
$LocalMapFile = ".gh-pages-publisher.json"
$StartupDiagPath = Join-Path $StoreDir "startup-last.json"
$TelemetryQueueDir = Join-Path $StoreDir "telemetry-queue"
$TelemetryWorkerPath = Join-Path $StoreDir "client-status-worker.ps1"
$TelemetryWorkerLockPath = Join-Path $StoreDir "client-status-worker.lock"
$script:ReturnToMain = $false
$script:GhUser = $null
$script:LastOpenedDeviceLoginUrl = $null
$script:IsSendingErrorReport = $false
$script:IsSendingClientStatus = $false

function Write-ThemeLine($text = "", $color = "Gray") {
    Write-Host $text -ForegroundColor $color
}

function Write-ThemeValue($label, $value) {
    Write-Host ("[sys] {0,-12}: " -f $label) -ForegroundColor DarkGray -NoNewline
    Write-Host $value -ForegroundColor Green
}

function Format-GpmDateTime($value) {
    if ([string]::IsNullOrWhiteSpace([string]$value)) {
        return "bilinmiyor"
    }

    $text = ([string]$value).Trim()

    try {
        if ($text -match '(Z|[+-]\d{2}:\d{2})$') {
            return ([DateTimeOffset]::Parse($text, [Globalization.CultureInfo]::InvariantCulture)).ToLocalTime().ToString("dd.MM.yyyy HH:mm:ss")
        }

        return ([DateTime]::Parse($text, [Globalization.CultureInfo]::InvariantCulture)).ToString("dd.MM.yyyy HH:mm:ss")
    }
    catch {
        return $text
    }
}

function Write-MenuItem($key, $text) {
    Write-Host ("  [{0}] " -f $key) -ForegroundColor Cyan -NoNewline
    Write-Host $text -ForegroundColor White
}

function Write-SectionTitle($text) {
    Write-Host ("+-- {0} -----------------------------------+" -f $text) -ForegroundColor DarkCyan
}

function Write-StatusInfo($message) {
    Write-Host ("[info] {0}" -f $message) -ForegroundColor DarkCyan
}

function Write-StatusOk($message) {
    Write-Host ("[ ok ] {0}" -f $message) -ForegroundColor Green
}

function Write-StatusWarn($message) {
    Write-Host ("[warn] {0}" -f $message) -ForegroundColor Yellow
}

function Write-KeyPrompt($label = "secim") {
    Write-Host ("> {0}:" -f $label) -ForegroundColor Green
}

function Write-MenuFrame($title, [scriptblock]$body) {
    Write-Host ("+-- {0} -----------------------------------+" -f $title) -ForegroundColor DarkCyan
    & $body
    Write-Host "+---------------------------------------------------+" -ForegroundColor DarkCyan
}

function Write-BoxMessage($title, $message, $color) {
    Write-Host ""
    Write-Host "+-- $title ----------------------------------------" -ForegroundColor $color
    foreach ($line in ([string]$message -split "`r?`n")) {
        Write-Host "| " -ForegroundColor $color -NoNewline
        Write-Host $line -ForegroundColor White
    }
    Write-Host "+--------------------------------------------------" -ForegroundColor $color
}

function Ensure-Storage {
    if (!(Test-Path $StoreDir)) {
        New-Item -ItemType Directory -Path $StoreDir -Force | Out-Null
    }

    if (!(Test-Path $DbPath)) {
        [System.IO.File]::WriteAllText($DbPath, "[]", [System.Text.UTF8Encoding]::new($false))
        return
    }

    $current = ""

    try {
        $current = [System.IO.File]::ReadAllText($DbPath)
    }
    catch {
        $current = ""
    }

    if ([string]::IsNullOrWhiteSpace($current)) {
        [System.IO.File]::WriteAllText($DbPath, "[]", [System.Text.UTF8Encoding]::new($false))
    }
}

function Header {
    Clear-Host
    Write-Host "+==================================================+" -ForegroundColor Cyan
    Write-Host "|  GITHUB PAGES MANAGER                            |" -ForegroundColor Cyan
    Write-Host "|  yayin node // update bridge // issue uplink     |" -ForegroundColor DarkCyan
    Write-Host "+==================================================+" -ForegroundColor Cyan
    Write-Host ""
}

function Read-KeyChoice($allowedKeys) {
    while ($true) {
        $key = [Console]::ReadKey($true).KeyChar.ToString()

        if ($allowedKeys -contains $key) {
            Write-Host $key
            return $key
        }
    }
}

function After-Action {
    Write-Host ""
    Write-MenuItem "1" "Ana menu"
    Write-MenuItem "2" "Kapat"
    Write-Host ""

    $choice = Read-KeyChoice @("1", "2")

    if ($choice -eq "2") {
        exit 0
    }

    $script:ReturnToMain = $true
}

function After-Publish($siteUrl) {
    Write-Host ""
    Write-MenuItem "1" "Ana menu"
    Write-MenuItem "2" "Kapat"
    Write-MenuItem "3" "Siteyi ac"
    Write-Host ""

    $choice = Read-KeyChoice @("1", "2", "3")

    if ($choice -eq "2") {
        exit 0
    }

    if ($choice -eq "3") {
        Start-Process $siteUrl
        $script:ReturnToMain = $true
        return
    }

    $script:ReturnToMain = $true
}

function Pause-Back {
    Write-Host ""
    Write-MenuItem "0" "Geri"
    Write-Host ""

    Read-KeyChoice @("0") | Out-Null
}

function Get-FriendlyErrorSummary($message) {
    $text = [string]$message
    $lower = $text.ToLowerInvariant()

    if ($lower -match "sha256|hash|dogrulama") {
        return "Guncelleme dosyasi dogrulanamadi. Dosya bozuk, eski cache veya yanlis release olabilir."
    }

    if ($lower -match "auth|login|token|credential|giris|yetki") {
        return "GitHub girisi veya yetkisiyle ilgili bir sorun var."
    }

    if ($lower -match "push|commit|remote|git ") {
        return "Git/GitHub yukleme islemi tamamlanamadi."
    }

    if ($lower -match "repo.*sil|delete_repo|silinemedi") {
        return "Repo silme islemi tamamlanamadi."
    }

    if ($text.Length -gt 160) {
        return $text.Substring(0, 160) + "..."
    }

    return $text
}

function Show-Error($message) {
    $summary = Get-FriendlyErrorSummary $message
    Write-BoxMessage "error signal" $summary "Red"
    Submit-ErrorReport $message

    if ($summary -ne [string]$message) {
        Write-Host ""
        Write-MenuItem "1" "Teknik detayi goster"
        Write-MenuItem "0" "Devam"
        Write-Host ""

        $choice = Read-KeyChoice @("1", "0")

        if ($choice -eq "1") {
            Write-BoxMessage "technical detail" $message "DarkRed"
        }
    }
}

function Invoke-JsonUrl($url) {
    if ([string]::IsNullOrWhiteSpace($url)) {
        throw "URL bos geldi."
    }

    $oldProtocol = [Net.ServicePointManager]::SecurityProtocol
    $lastError = $null

    try {
        [Net.ServicePointManager]::SecurityProtocol = $oldProtocol -bor [Net.SecurityProtocolType]::Tls12
        $headers = @{
            "User-Agent" = "GitHubPagesManager"
            "Cache-Control" = "no-cache"
        }
        $uri = [UriBuilder]$url
        $separator = ""

        if (![string]::IsNullOrWhiteSpace($uri.Query)) {
            $separator = "&"
            $uri.Query = $uri.Query.TrimStart("?") + $separator + "_=" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        }
        else {
            $uri.Query = "_=" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        }

        $response = Invoke-RestMethod -Uri $uri.Uri.AbsoluteUri -Headers $headers -TimeoutSec $HttpTimeoutSeconds -UseBasicParsing

        if ($response -is [string]) {
            $jsonText = $response.TrimStart([char]0xFEFF)
            return ($jsonText | ConvertFrom-Json)
        }

        return $response
    }
    catch {
        $lastError = $_.Exception.Message
    }
    finally {
        [Net.ServicePointManager]::SecurityProtocol = $oldProtocol
    }

    $curl = Get-GpmCurlCommand

    if ($null -ne $curl) {
        $oldCurlPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"

        try {
            $curlArgs = @("--location", "--silent", "--show-error", "--fail")
            if (!(Test-GpmLinux)) { $curlArgs += "--ssl-no-revoke" }
            $curlArgs += @(
                "--max-time", $HttpTimeoutSeconds,
                "--header", "User-Agent: GitHubPagesManager",
                "--header", "Cache-Control: no-cache",
                $url
            )
            $curlOutput = & $curl @curlArgs 2>&1
            $curlCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $oldCurlPreference
        }

        if ($curlCode -eq 0 -and ![string]::IsNullOrWhiteSpace(($curlOutput -join [Environment]::NewLine))) {
            $jsonText = ($curlOutput -join [Environment]::NewLine).TrimStart([char]0xFEFF)
            return ($jsonText | ConvertFrom-Json)
        }

        throw "URL okunamadi. PowerShell: $lastError Curl: $($curlOutput -join [Environment]::NewLine)"
    }

    throw "URL okunamadi. PowerShell: $lastError"
}

function Get-CacheBustedUrl($url) {
    if ([string]::IsNullOrWhiteSpace($url)) {
        return $url
    }

    try {
        $uri = [UriBuilder]$url

        if (![string]::IsNullOrWhiteSpace($uri.Query)) {
            $uri.Query = $uri.Query.TrimStart("?") + "&_=" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        }
        else {
            $uri.Query = "_=" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        }

        return $uri.Uri.AbsoluteUri
    }
    catch {
        return $url
    }
}

function Get-GitHubBranchHeadSha($repoFullName, $branchName) {
    if ([string]::IsNullOrWhiteSpace($repoFullName) -or [string]::IsNullOrWhiteSpace($branchName)) {
        return $null
    }

    $apiUrl = "https://api.github.com/repos/$repoFullName/branches/$branchName"
    $oldProtocol = [Net.ServicePointManager]::SecurityProtocol

    try {
        [Net.ServicePointManager]::SecurityProtocol = $oldProtocol -bor [Net.SecurityProtocolType]::Tls12
        $response = Invoke-RestMethod -Uri $apiUrl -Headers @{
            "User-Agent" = "GitHubPagesManager"
            "Cache-Control" = "no-cache"
        } -TimeoutSec $HttpTimeoutSeconds -UseBasicParsing

        if ($null -ne $response -and $null -ne $response.commit -and ![string]::IsNullOrWhiteSpace($response.commit.sha)) {
            return $response.commit.sha
        }
    }
    catch {
    }
    finally {
        [Net.ServicePointManager]::SecurityProtocol = $oldProtocol
    }

    return $null
}

function Get-PinnedManifestUrl($manifestUrl) {
    if ([string]::IsNullOrWhiteSpace($manifestUrl)) {
        return $null
    }

    if ($manifestUrl -match '^https?://raw\.githubusercontent\.com/([^/]+)/([^/]+)/main/(.+)$') {
        $repoFullName = "$($matches[1])/$($matches[2])"
        $manifestPath = $matches[3]
        $headSha = Get-GitHubBranchHeadSha $repoFullName "main"

        if (![string]::IsNullOrWhiteSpace($headSha)) {
            return "https://raw.githubusercontent.com/$repoFullName/$headSha/$manifestPath"
        }
    }

    return $null
}

function Get-RawMainManifestInfo($manifestUrl) {
    if ([string]::IsNullOrWhiteSpace($manifestUrl)) {
        return $null
    }

    if ($manifestUrl -match '^https?://raw\.githubusercontent\.com/([^/]+)/([^/]+)/main/(.+)$') {
        return [PSCustomObject]@{
            RepoFullName = "$($matches[1])/$($matches[2])"
            Path = $matches[3]
        }
    }

    return $null
}

function Get-HeadShaFromRawUrl($url) {
    if ([string]::IsNullOrWhiteSpace($url)) {
        return $null
    }

    if ($url -match '^https?://raw\.githubusercontent\.com/[^/]+/[^/]+/([0-9a-fA-F]{40})/') {
        return $matches[1].ToLowerInvariant()
    }

    return $null
}

function Get-UpdateManifest($manifestUrl) {
    $cache = Get-UpdateCheckCache
    $rawInfo = Get-RawMainManifestInfo $manifestUrl

    if ($null -ne $rawInfo) {
        $headSha = Get-GitHubBranchHeadSha $rawInfo.RepoFullName "main"

        if ([string]::IsNullOrWhiteSpace($headSha)) {
            if ($null -ne $cache -and $null -ne $cache.Manifest) {
                return [PSCustomObject]@{
                    Manifest = $cache.Manifest
                    SourceUrl = $cache.SourceUrl
                    HeadSha = $cache.HeadSha
                    FromCache = $true
                }
            }
        }
        elseif ($null -ne $cache -and $null -ne $cache.Manifest -and [string]$cache.HeadSha -eq [string]$headSha) {
            return [PSCustomObject]@{
                Manifest = $cache.Manifest
                SourceUrl = $cache.SourceUrl
                HeadSha = $headSha
                FromCache = $true
            }
        }
        else {
            $pinnedManifestUrl = "https://raw.githubusercontent.com/$($rawInfo.RepoFullName)/$headSha/$($rawInfo.Path)"

            try {
                $manifest = Invoke-JsonUrl $pinnedManifestUrl

                if ($null -ne $manifest) {
                    return [PSCustomObject]@{
                        Manifest = $manifest
                        SourceUrl = $pinnedManifestUrl
                        HeadSha = $headSha
                        FromCache = $false
                    }
                }
            }
            catch {
            }
        }
    }

    $pinnedManifestUrl = Get-PinnedManifestUrl $manifestUrl

    if (![string]::IsNullOrWhiteSpace($pinnedManifestUrl)) {
        try {
            $manifest = Invoke-JsonUrl $pinnedManifestUrl

            if ($null -ne $manifest) {
                return [PSCustomObject]@{
                    Manifest = $manifest
                    SourceUrl = $pinnedManifestUrl
                    HeadSha = Get-HeadShaFromRawUrl $pinnedManifestUrl
                    FromCache = $false
                }
            }
        }
        catch {
        }
    }

    $fallbackManifest = Invoke-JsonUrl $manifestUrl

    return [PSCustomObject]@{
        Manifest = $fallbackManifest
        SourceUrl = $manifestUrl
        HeadSha = Get-HeadShaFromRawUrl $manifestUrl
        FromCache = $false
    }
}

function Get-UpdateCheckCache {
    if (!(Test-Path -LiteralPath $UpdateCheckCachePath)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $UpdateCheckCachePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Save-UpdateCheckCache($manifestUrl, $manifestSourceUrl, $manifest) {
    if ($null -eq $manifest) {
        return
    }

    Ensure-Storage

    $cache = [PSCustomObject]@{
        CheckedAt = (Get-Date).ToUniversalTime().ToString("o")
        ManifestUrl = $manifestUrl
        SourceUrl = $manifestSourceUrl
        HeadSha = Get-HeadShaFromRawUrl $manifestSourceUrl
        Manifest = $manifest
    }

    $json = $cache | ConvertTo-Json -Depth 30
    [System.IO.File]::WriteAllText($UpdateCheckCachePath, $json, [System.Text.UTF8Encoding]::new($false))
}

function Save-UrlToFile($url, $outFile) {
    if ([string]::IsNullOrWhiteSpace($url)) {
        throw "Indirme URL'i bos geldi."
    }

    $oldProtocol = [Net.ServicePointManager]::SecurityProtocol
    $lastError = $null
    $downloadUrl = Get-CacheBustedUrl $url

    try {
        [Net.ServicePointManager]::SecurityProtocol = $oldProtocol -bor [Net.SecurityProtocolType]::Tls12
        $headers = @{
            "User-Agent" = "GitHubPagesManager"
            "Cache-Control" = "no-cache"
        }
        Invoke-WebRequest -Uri $downloadUrl -OutFile $outFile -Headers $headers -TimeoutSec $HttpTimeoutSeconds -UseBasicParsing
        return
    }
    catch {
        $lastError = $_.Exception.Message
    }
    finally {
        [Net.ServicePointManager]::SecurityProtocol = $oldProtocol
    }

    $curl = Get-GpmCurlCommand

    if ($null -ne $curl) {
        $oldCurlPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"

        try {
            $curlArgs = @("--location", "--silent", "--show-error", "--fail")
            if (!(Test-GpmLinux)) { $curlArgs += "--ssl-no-revoke" }
            $curlArgs += @(
                "--max-time", $HttpTimeoutSeconds,
                "--header", "User-Agent: GitHubPagesManager",
                "--header", "Cache-Control: no-cache",
                "--output", $outFile,
                $downloadUrl
            )
            $curlOutput = & $curl @curlArgs 2>&1
            $curlCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $oldCurlPreference
        }

        if ($curlCode -eq 0 -and (Test-Path $outFile)) {
            return
        }

        throw "Dosya indirilemedi. PowerShell: $lastError Curl: $($curlOutput -join [Environment]::NewLine)"
    }

    throw "Dosya indirilemedi. PowerShell: $lastError"
}

function Get-ManifestNotes($manifest) {
    if ($null -eq $manifest) {
        return @()
    }

    $rawNotes = $manifest.notes

    if ($null -eq $rawNotes) {
        $rawNotes = $manifest.releaseNotes
    }

    if ($null -eq $rawNotes) {
        return @()
    }

    $notes = @()

    foreach ($note in @($rawNotes)) {
        if (![string]::IsNullOrWhiteSpace([string]$note)) {
            $notes += ([string]$note).Trim()
        }
    }

    return $notes
}

function Get-CategorizedManifestNotes($manifest) {
    $result = [ordered]@{}

    if ($null -eq $manifest -or $null -eq $manifest.categorizedNotes) {
        return $result
    }

    foreach ($category in @("Added", "Fixed", "Changed", "Security", "Internal")) {
        $items = @()
        $rawItems = $manifest.categorizedNotes.$category

        foreach ($item in @($rawItems)) {
            if (![string]::IsNullOrWhiteSpace([string]$item)) {
                $items += ([string]$item).Trim()
            }
        }

        if ($items.Count -gt 0) {
            $result[$category] = $items
        }
    }

    return $result
}

function Write-ManifestNotes($manifest) {
    $categorized = Get-CategorizedManifestNotes $manifest

    if ($categorized.Count -gt 0) {
        foreach ($category in $categorized.Keys) {
            Write-Host "$category" -ForegroundColor Cyan

            foreach ($note in @($categorized[$category])) {
                Write-Host "  - $note"
            }

            Write-Host ""
        }

        return
    }

    $notes = @(Get-ManifestNotes $manifest)

    if ($notes.Count -eq 0) {
        Write-Host "- Not yok."
    }
    else {
        foreach ($note in $notes) {
            Write-Host "- $note"
        }
    }
}

function Get-EffectiveUpdateManifestUrl {
    if (![string]::IsNullOrWhiteSpace($UpdateManifestUrl) -and $UpdateManifestUrl -notmatch '^__.*__$') {
        return $UpdateManifestUrl
    }

    $envUrl = [Environment]::GetEnvironmentVariable("GITHUB_PAGES_MANAGER_UPDATE_MANIFEST", "User")

    if ([string]::IsNullOrWhiteSpace($envUrl)) {
        $envUrl = [Environment]::GetEnvironmentVariable("GITHUB_PAGES_MANAGER_UPDATE_MANIFEST", "Process")
    }

    if (![string]::IsNullOrWhiteSpace($envUrl)) {
        return $envUrl.Trim()
    }

    if (Test-Path $AdminConfigPath) {
        try {
            $adminConfig = Get-Content -LiteralPath $AdminConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

            if (![string]::IsNullOrWhiteSpace($adminConfig.RepoFullName)) {
                return "https://raw.githubusercontent.com/$($adminConfig.RepoFullName)/main/latest.json"
            }
        }
        catch {
        }
    }

    return $null
}

function Get-LocalAdminManifest {
    $manifestPath = Join-Path (Join-Path (Join-Path $env:APPDATA "GithubPagesPublisherAdmin") "update-repo") "latest.json"

    if (!(Test-Path $manifestPath)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Get-LocalAdminReleaseRoot {
    return (Join-Path (Join-Path $env:APPDATA "GithubPagesPublisherAdmin") "update-repo")
}

function Get-RepoFullNameFromRawUrl($url) {
    if ([string]::IsNullOrWhiteSpace($url)) {
        return $null
    }

    if ($url -match 'https?://raw\.githubusercontent\.com/([^/]+)/([^/]+)/') {
        return "$($matches[1])/$($matches[2])"
    }

    return $null
}

function Get-EffectiveErrorReportRepo {
    if (![string]::IsNullOrWhiteSpace($ErrorReportRepo) -and $ErrorReportRepo -notmatch '^__.*__$') {
        return $ErrorReportRepo
    }

    $envRepo = [Environment]::GetEnvironmentVariable("GITHUB_PAGES_MANAGER_ERROR_REPO", "User")

    if ([string]::IsNullOrWhiteSpace($envRepo)) {
        $envRepo = [Environment]::GetEnvironmentVariable("GITHUB_PAGES_MANAGER_ERROR_REPO", "Process")
    }

    if (![string]::IsNullOrWhiteSpace($envRepo)) {
        return $envRepo.Trim()
    }

    if (Test-Path $AdminConfigPath) {
        try {
            $adminConfig = Get-Content -LiteralPath $AdminConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

            if (![string]::IsNullOrWhiteSpace($adminConfig.RepoFullName)) {
                return $adminConfig.RepoFullName
            }
        }
        catch {
        }
    }

    $localManifest = Get-LocalAdminManifest

    if ($null -ne $localManifest -and ![string]::IsNullOrWhiteSpace($localManifest.errorReportRepo)) {
        return $localManifest.errorReportRepo
    }

    $manifestUrl = Get-EffectiveUpdateManifestUrl
    $repoFromUrl = Get-RepoFullNameFromRawUrl $manifestUrl

    if (![string]::IsNullOrWhiteSpace($repoFromUrl)) {
        return $repoFromUrl
    }

    return $null
}

function Get-ErrorCategory($message) {
    $text = ([string]$message).ToLowerInvariant()

    if ($text -match "self-update|apply-update|update diagnostic|update diagnosis|stale-after-ok|supervisor|guncelleme supervisor|guncelleme uygulan|guncelleme hedef|yeniden acilamadi|linux sh|manifest.*paket|manifest.*guncelleme") {
        return "update"
    }

    if ($text -match "asset|asset yolu|asset path|dosya yolu|kok-relative|buyuk/kucuk harf|github pages.*calismayacak") {
        return "asset"
    }

    if ($text -match "sha256|hash|dogrulama|download|indir") {
        return "hash"
    }

    if ($text -match "auth|login|token|credential|giris|yetki|scope|delete_repo") {
        return "auth"
    }

    if ($text -match "repo.*sil|silinemedi|delete") {
        return "delete"
    }

    if ($text -match "push|commit|remote|git ") {
        return "git"
    }

    if ($text -match "publish|yayin|pages|repo olustur") {
        return "publish"
    }

    if ($text -match "update|guncelle|manifest") {
        return "update"
    }

    return "unknown"
}

function Get-ErrorSignature($message, $category) {
    $normalized = ([string]$message).ToLowerInvariant()
    $normalized = $normalized -replace 'https?://\S+', '<url>'
    $normalized = $normalized -replace '[a-f0-9]{32,64}', '<hash>'
    $normalized = $normalized -replace '\b\d{4}-\d{2}-\d{2}[t\s]\d{2}:\d{2}:\d{2}\b', '<date>'
    $normalized = $normalized -replace '\d+', '<n>'
    $normalized = $normalized -replace '\s+', ' '
    $seed = "$category|$AppVersion|$normalized"
    $sha = [System.Security.Cryptography.SHA256]::Create()

    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($seed)
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash).Replace("-", "").Substring(0, 16)).ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-ShortSha256($seed) {
    $sha = [System.Security.Cryptography.SHA256]::Create()

    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$seed)
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash).Replace("-", "").Substring(0, 16)).ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-ClientId($activeGhUser) {
    $seed = (@($env:COMPUTERNAME, $env:USERDOMAIN, $env:USERNAME, $activeGhUser) | ForEach-Object {
        ([string]$_).Trim().ToLowerInvariant()
    }) -join "|"
    return Get-ShortSha256 $seed
}

function Get-TelemetryKeyFromManifest($manifest) {
    if ($null -eq $manifest -or $null -eq $manifest.telemetry) {
        return $null
    }

    if (![string]::IsNullOrWhiteSpace($manifest.telemetry.keyId) -and ![string]::IsNullOrWhiteSpace($manifest.telemetry.publicKey)) {
        return [PSCustomObject]@{
            KeyId = [string]$manifest.telemetry.keyId
            PublicKey = [string]$manifest.telemetry.publicKey
        }
    }

    return $null
}

function Get-EffectiveTelemetryKeyInfo {
    if (![string]::IsNullOrWhiteSpace($TelemetryKeyId) -and ![string]::IsNullOrWhiteSpace($TelemetryPublicKey)) {
        return [PSCustomObject]@{
            KeyId = $TelemetryKeyId
            PublicKey = $TelemetryPublicKey
        }
    }

    $cache = Get-UpdateCheckCache
    $cacheKey = $null

    if ($null -ne $cache -and $null -ne $cache.Manifest) {
        $cacheKey = Get-TelemetryKeyFromManifest $cache.Manifest
    }

    if ($null -ne $cacheKey) {
        return $cacheKey
    }

    $localManifest = Get-LocalAdminManifest
    $localKey = Get-TelemetryKeyFromManifest $localManifest

    if ($null -ne $localKey) {
        return $localKey
    }

    return $null
}

function Test-TelemetryEncryptionAvailable {
    return $null -ne (Get-EffectiveTelemetryKeyInfo)
}

function Protect-TelemetryPayload($payload) {
    $keyInfo = Get-EffectiveTelemetryKeyInfo

    if ($null -eq $keyInfo) {
        return $null
    }

    $publicXml = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($keyInfo.PublicKey))
    $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider 2048
    $aes = [System.Security.Cryptography.Aes]::Create()

    try {
        $rsa.FromXmlString($publicXml)
        $aes.KeySize = 256
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.GenerateKey()
        $aes.GenerateIV()

        $json = $payload | ConvertTo-Json -Depth 30 -Compress
        $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $encryptor = $aes.CreateEncryptor()
        $cipherBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
        $encryptedKey = $rsa.Encrypt($aes.Key, $false)

        return [PSCustomObject]@{
            schemaVersion = 1
            kind = "gpm-encrypted-telemetry"
            keyId = $keyInfo.KeyId
            clientId = $payload.clientId
            payloadKind = $payload.kind
            algorithm = "RSA-PKCS1+A256-CBC"
            encryptedKey = [Convert]::ToBase64String($encryptedKey)
            iv = [Convert]::ToBase64String($aes.IV)
            ciphertext = [Convert]::ToBase64String($cipherBytes)
            createdAt = (Get-Date).ToUniversalTime().ToString("s") + "Z"
        }
    }
    finally {
        if ($null -ne $aes) {
            $aes.Dispose()
        }

        if ($null -ne $rsa) {
            $rsa.Dispose()
        }
    }
}

function New-EncryptedTelemetryBody($payload) {
    $envelope = Protect-TelemetryPayload $payload

    if ($null -eq $envelope) {
        return $null
    }

    $json = $envelope | ConvertTo-Json -Depth 20
    $lines = @(
        "## GPM Encrypted Telemetry",
        "",
        "- Kind: $($payload.kind)",
        "- Client ID: gpm-client:$($payload.clientId)",
        "- Key ID: $($envelope.keyId)",
        "",
        '```json',
        $json,
        '```'
    )

    return ($lines -join [Environment]::NewLine)
}

function Get-RegisteredRepoTelemetry {
    $repoItems = New-Object System.Collections.ArrayList

    try {
        $repos = @(Load-Db)

        foreach ($repo in $repos) {
            if ($null -eq $repo) {
                continue
            }

            [void]$repoItems.Add([PSCustomObject]@{
                fullName = [string]$repo.FullName
                siteUrl = [string]$repo.SiteUrl
                repoUrl = [string]$repo.RepoUrl
                localPath = [string]$repo.LocalPath
                updatedAt = [string]$repo.UpdatedAt
            })
        }
    }
    catch {
    }

    return @($repoItems.ToArray())
}

function New-TelemetryPayload($kind, $activeGhUser, $clientId, $actionName = "app-open", $actionRepo = "", $actionSite = "") {
    $windowsUser = $env:USERNAME

    if (![string]::IsNullOrWhiteSpace($env:USERDOMAIN)) {
        $windowsUser = "$env:USERDOMAIN\$env:USERNAME"
    }

    $nowUtc = (Get-Date).ToUniversalTime().ToString("s") + "Z"
    $cleanAction = ([string]$actionName).Trim()

    if ([string]::IsNullOrWhiteSpace($cleanAction)) {
        $cleanAction = "app-open"
    }

    return [PSCustomObject]@{
        schemaVersion = 1
        kind = $kind
        clientId = $clientId
        timestamp = (Get-Date).ToString("s")
        utc = $nowUtc
        lastSeenUtc = $nowUtc
        appVersion = $AppVersion
        computer = $env:COMPUTERNAME
        windowsUser = $windowsUser
        githubUser = $activeGhUser
        workingDirectory = (Get-Location).Path
        batPath = $env:BAT_FILE
        action = $cleanAction
        actionRepo = [string]$actionRepo
        actionSiteUrl = [string]$actionSite
        repos = @(Get-RegisteredRepoTelemetry)
    }
}

function Ensure-IssueLabels($repoFullName, $labels) {
    foreach ($label in @($labels)) {
        if ([string]::IsNullOrWhiteSpace($label)) {
            continue
        }

        $color = "ededed"

        if ($label -eq "gpm-error") {
            $color = "d73a4a"
        }
        elseif ($label -eq "gpm-telemetry") {
            $color = "5319e7"
        }
        elseif ($label -match "^gpm-v") {
            $color = "0366d6"
        }
        elseif ($label -match "hash|update") {
            $color = "fbca04"
        }
        elseif ($label -match "auth|delete") {
            $color = "b60205"
        }

        Invoke-GhSilent @("label", "create", $label, "--repo", $repoFullName, "--color", $color, "--force") | Out-Null
    }
}

function Test-CanManageIssueLabels($repoFullName) {
    if ([string]::IsNullOrWhiteSpace($repoFullName)) {
        return $false
    }

    $result = Invoke-GhSilent @("api", "repos/$repoFullName", "--jq", ".permissions.push")

    if ($result.Code -ne 0) {
        return $false
    }

    return ([string]$result.Output).Trim().ToLowerInvariant() -eq "true"
}

function Find-ExistingErrorIssue($repoFullName, $signature) {
    if ([string]::IsNullOrWhiteSpace($signature)) {
        return $null
    }

    $signatureLabel = "gpm-sig-$signature"
    $result = Invoke-GhSilent @(
        "issue", "list",
        "--repo", $repoFullName,
        "--state", "open",
        "--label", $signatureLabel,
        "--json", "number,title,url"
    )

    if ($result.Code -eq 0 -and ![string]::IsNullOrWhiteSpace($result.Output)) {
        try {
            $issues = @($result.Output | ConvertFrom-Json)
            $issue = $issues | Select-Object -First 1

            if ($null -ne $issue) {
                return $issue
            }
        }
        catch {
        }
    }

    $result = Invoke-GhSilent @(
        "issue", "list",
        "--repo", $repoFullName,
        "--state", "open",
        "--label", "gpm-error",
        "--search", "gpm-signature:$signature",
        "--json", "number,title,url"
    )

    if ($result.Code -ne 0 -or [string]::IsNullOrWhiteSpace($result.Output)) {
        return $null
    }

    try {
        $issues = @($result.Output | ConvertFrom-Json)
        return ($issues | Select-Object -First 1)
    }
    catch {
    }

    $result = Invoke-GhSilent @(
        "issue", "list",
        "--repo", $repoFullName,
        "--state", "open",
        "--limit", "100",
        "--json", "number,title,url,body"
    )

    if ($result.Code -ne 0 -or [string]::IsNullOrWhiteSpace($result.Output)) {
        return $null
    }

    try {
        $issues = @($result.Output | ConvertFrom-Json)
        return ($issues | Where-Object {
            $null -ne $_.body -and ([string]$_.body).Contains("gpm-signature:$signature")
        } | Select-Object -First 1)
    }
    catch {
        return $null
    }
}

function Sanitize-PublicErrorText($text, $activeGhUser = $null) {
    $value = [string]$text

    foreach ($secret in @($env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA, $env:TEMP, $env:TMP, $env:USERNAME, $env:COMPUTERNAME, $activeGhUser)) {
        if ([string]::IsNullOrWhiteSpace($secret)) {
            continue
        }

        $value = $value -replace [regex]::Escape($secret), "<redacted>"
    }

    $value = $value -replace '([A-Za-z]:\\Users\\)[^\\\r\n"]+', '$1<redacted>'
    $value = $value -replace '(?i)(token|authorization|password|secret|private[_-]?key)\s*[:=]\s*\S+', '$1=<redacted>'

    return $value
}

function New-ErrorReportBody($message, $clientId, $safeMessage) {

    $lines = @(
        "## Hata Raporu",
        "",
        "- Tarih: $((Get-Date).ToString("s"))",
        "- UTC: $((Get-Date).ToUniversalTime().ToString("s"))Z",
        "- Uygulama surumu: $AppVersion",
        "- Client ID: gpm-client:$clientId",
        "",
        "## Siniflandirma",
        "",
        "- Kategori: $script:CurrentErrorCategory",
        "- Imza: gpm-signature:$script:CurrentErrorSignature",
        "",
        "## Hata",
        "",
        '```text',
        ([string]$safeMessage),
        '```'
    )

    if ($null -ne $script:LastAssetValidationIssues -and @($script:LastAssetValidationIssues).Count -gt 0) {
        $lines += @(
            "",
            "## Teknik Detay",
            "",
            "Asset yolu kontrolunde bulunan sorunlar:",
            ""
        )

        foreach ($issue in @($script:LastAssetValidationIssues)) {
            $lines += "- $issue"
        }
    }

    return ($lines -join [Environment]::NewLine)
}

function Get-UpdateReportCache {
    try {
        if (!(Test-Path -LiteralPath $UpdateApplyReportCachePath)) {
            return $null
        }

        return Get-Content -LiteralPath $UpdateApplyReportCachePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Save-UpdateReportCache($signature, $status, $targetVersion, $resultText = "") {
    try {
        $cacheDir = Split-Path -Parent $UpdateApplyReportCachePath

        if (![string]::IsNullOrWhiteSpace($cacheDir) -and !(Test-Path -LiteralPath $cacheDir)) {
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        }

        $cache = [PSCustomObject]@{
            SchemaVersion = 1
            Signature = [string]$signature
            Status = [string]$status
            TargetVersion = [string]$targetVersion
            Result = [string]$resultText
            ReportedAt = (Get-Date).ToUniversalTime().ToString("o")
        }

        [System.IO.File]::WriteAllText($UpdateApplyReportCachePath, ($cache | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
    }
    catch {
    }
}

function Get-UpdateDiagnosticReportStatus($diag) {
    if ($null -eq $diag) {
        return ""
    }

    $status = [string]$diag.Status

    if ([string]::IsNullOrWhiteSpace($status)) {
        return ""
    }

    if ($status -eq "ok") {
        if (![string]::IsNullOrWhiteSpace([string]$diag.TargetVersion) -and [string]$diag.TargetVersion -ne [string]$AppVersion) {
            return "stale-after-ok"
        }

        return ""
    }

    if ($status -match "failed|launching|started|restart-failed|copy-retry|verify-failed") {
        return $status
    }

    return ""
}

function Get-UpdateDiagnosticSummary($diag, $reportStatus) {
    $message = [string]$diag.Message

    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = "Guncelleme tanisi sorunlu bir durum bildirdi."
    }

    if ($reportStatus -eq "stale-after-ok") {
        return "Update target dogrulanmis gorunuyor ama eski BAT surumu acildi. Kullanici farkli/eski kopyayi aciyor olabilir."
    }

    return "Self-update diagnosis: $reportStatus - $message"
}

function Get-UpdateDiagnosticSignature($diag, $reportStatus, $safeSummary) {
    $seed = @(
        "update-diagnostic",
        $AppVersion,
        [string]$reportStatus,
        [string]$diag.Status,
        [string]$diag.TargetVersion,
        [string]$diag.ExpectedHash,
        [string]$diag.ExpectedSize,
        [string]$safeSummary
    ) -join "|"

    return Get-ShortSha256 $seed
}

function New-UpdateDiagnosticPayload($diag, $reportStatus, $clientId, $activeGhUser) {
    return [PSCustomObject]@{
        schemaVersion = 1
        kind = "update-diagnostic"
        clientId = $clientId
        timestamp = (Get-Date).ToString("s")
        utc = (Get-Date).ToUniversalTime().ToString("s") + "Z"
        appVersion = $AppVersion
        reportStatus = [string]$reportStatus
        githubUser = $activeGhUser
        batPath = $env:BAT_FILE
        workingDirectory = (Get-Location).Path
        powershellVersion = $PSVersionTable.PSVersion.ToString()
        os = [Environment]::OSVersion.VersionString
        diagnostic = $diag
    }
}

function New-UpdateDiagnosticReportBody($diag, $reportStatus, $clientId, $safeSummary, $safeDetails, $encryptedBody) {
    $lines = @(
        "## GPM Update Diagnostic",
        "",
        "- Tarih: $((Get-Date).ToString("s"))",
        "- UTC: $((Get-Date).ToUniversalTime().ToString("s"))Z",
        "- Uygulama surumu: $AppVersion",
        "- Client ID: gpm-client:$clientId",
        "- Update status: $reportStatus",
        "- Hedef surum: $([string]$diag.TargetVersion)",
        "",
        "## Ozet",
        "",
        '```text',
        ([string]$safeSummary),
        '```',
        "",
        "## Maskeli Tani",
        "",
        '```json',
        ([string]$safeDetails),
        '```'
    )

    if (![string]::IsNullOrWhiteSpace($encryptedBody)) {
        $lines += @(
            "",
            "## Sifreli Detay",
            "",
            $encryptedBody
        )
    }
    else {
        $lines += @(
            "",
            "## Sifreli Detay",
            "",
            "Encrypted telemetry payload olusturulamadi; sadece maskeli tani eklendi."
        )
    }

    return ($lines -join [Environment]::NewLine)
}

function Submit-UpdateDiagnosticReport($diag, $reportStatus) {
    if ($script:IsSendingErrorReport) {
        return
    }

    if ($null -eq $diag -or [string]::IsNullOrWhiteSpace([string]$reportStatus)) {
        return
    }

    $script:IsSendingErrorReport = $true

    try {
        if (!(Command-Exists "gh")) {
            Write-StatusWarn "Update tanisi GitHub'a gonderilemedi: GitHub CLI bulunamadi."
            return
        }

        $repoFullName = Get-EffectiveErrorReportRepo

        if ([string]::IsNullOrWhiteSpace($repoFullName)) {
            Write-StatusWarn "Update tanisi GitHub'a gonderilemedi: issue reposu ayarlanmamis."
            return
        }

        $activeGhUser = $script:GhUser

        if ([string]::IsNullOrWhiteSpace($activeGhUser)) {
            $activeGhUser = Get-ActiveGitHubUser
        }

        $clientId = Get-ClientId $activeGhUser
        $summary = Get-UpdateDiagnosticSummary $diag $reportStatus
        $safeSummary = Sanitize-PublicErrorText $summary $activeGhUser
        $safeDetails = Sanitize-PublicErrorText (($diag | ConvertTo-Json -Depth 12) -join [Environment]::NewLine) $activeGhUser
        $signature = Get-UpdateDiagnosticSignature $diag $reportStatus $safeSummary
        $cache = Get-UpdateReportCache

        if ($null -ne $cache -and [string]$cache.Signature -eq [string]$signature) {
            return
        }

        $payload = New-UpdateDiagnosticPayload $diag $reportStatus $clientId $activeGhUser
        $encryptedBody = New-EncryptedTelemetryBody $payload
        $labels = @("gpm-error", "gpm-update", "gpm-v$AppVersion", "gpm-sig-$signature", "gpm-client-$clientId")
        $canManageLabels = Test-CanManageIssueLabels $repoFullName

        if ($canManageLabels) {
            Ensure-IssueLabels $repoFullName $labels
        }

        $reportsDir = Join-Path $StoreDir "update-reports"
        New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null

        $bodyPath = Join-Path $reportsDir ("update-diagnostic-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".md")
        [System.IO.File]::WriteAllText($bodyPath, (New-UpdateDiagnosticReportBody $diag $reportStatus $clientId $safeSummary $safeDetails $encryptedBody), [System.Text.UTF8Encoding]::new($false))

        $script:CurrentErrorCategory = "update"
        $script:CurrentErrorSignature = $signature
        $existingIssue = Find-ExistingErrorIssue $repoFullName $signature
        $title = "[Auto Error][update] $((Get-Date).ToString("yyyy-MM-dd HH:mm")) - self-update - $reportStatus"

        if ($null -ne $existingIssue) {
            $result = Invoke-GhSilent @(
                "issue", "comment", [string]$existingIssue.number,
                "--repo", $repoFullName,
                "--body-file", $bodyPath
            )
        }
        elseif (!$canManageLabels) {
            $result = Invoke-GhSilent @(
                "issue", "create",
                "--repo", $repoFullName,
                "--title", $title,
                "--body-file", $bodyPath
            )
        }
        else {
            $result = Invoke-GhSilent @(
                "issue", "create",
                "--repo", $repoFullName,
                "--title", $title,
                "--body-file", $bodyPath,
                "--label", ($labels -join ",")
            )
        }

        if ($result.Code -eq 0) {
            Save-UpdateReportCache $signature $reportStatus ([string]$diag.TargetVersion) $result.Output
        }
        else {
            Write-StatusWarn "Update tanisi GitHub'a gonderilemedi."
            Write-ThemeValue "yerel rapor" $bodyPath
        }
    }
    catch {
        try {
            Write-StatusWarn "Update tanisi hazirlanamadi."
            Write-Host $_.Exception.Message
        }
        catch {
        }
    }
    finally {
        $script:IsSendingErrorReport = $false
    }
}

function Submit-PendingUpdateDiagnostic {
    $diag = Get-UpdateApplyDiagnostic
    $reportStatus = Get-UpdateDiagnosticReportStatus $diag

    if ([string]::IsNullOrWhiteSpace($reportStatus)) {
        return
    }

    Submit-UpdateDiagnosticReport $diag $reportStatus
}

function Submit-ErrorReport($message) {
    if ($script:IsSendingErrorReport) {
        return
    }

    if ([string]::IsNullOrWhiteSpace([string]$message)) {
        return
    }

    $script:IsSendingErrorReport = $true

    try {
        if (!(Command-Exists "gh")) {
            return
        }

        $repoFullName = Get-EffectiveErrorReportRepo

        if ([string]::IsNullOrWhiteSpace($repoFullName)) {
            return
        }

        $activeGhUser = $script:GhUser

        if ([string]::IsNullOrWhiteSpace($activeGhUser)) {
            $activeGhUser = Get-ActiveGitHubUser
        }

        $clientId = Get-ClientId $activeGhUser
        $safeMessage = Sanitize-PublicErrorText $message $activeGhUser
        $category = Get-ErrorCategory $message
        $signature = Get-ErrorSignature $safeMessage $category
        $script:CurrentErrorCategory = $category
        $script:CurrentErrorSignature = $signature
        $labels = @("gpm-error", "gpm-$category", "gpm-v$AppVersion", "gpm-sig-$signature", "gpm-client-$clientId")
        $canManageLabels = Test-CanManageIssueLabels $repoFullName

        if ($canManageLabels) {
            Ensure-IssueLabels $repoFullName $labels
        }

        $safeTitleText = ([string]$safeMessage -replace "`r", " " -replace "`n", " ").Trim()

        if ($safeTitleText.Length -gt 70) {
            $safeTitleText = $safeTitleText.Substring(0, 70)
        }

        if ([string]::IsNullOrWhiteSpace($safeTitleText)) {
            $safeTitleText = "Bilinmeyen hata"
        }

        $title = "[Auto Error][$category] $((Get-Date).ToString("yyyy-MM-dd HH:mm")) - $env:USERNAME - $safeTitleText"
        $reportsDir = Join-Path $StoreDir "error-reports"
        New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null

        $bodyPath = Join-Path $reportsDir ("error-report-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".md")
        [System.IO.File]::WriteAllText($bodyPath, (New-ErrorReportBody $message $clientId $safeMessage), [System.Text.UTF8Encoding]::new($false))

        Write-Host ""
        Write-StatusInfo "Hata raporu GitHub'a gonderiliyor..."

        $existingIssue = Find-ExistingErrorIssue $repoFullName $signature

        if ($null -ne $existingIssue) {
            $result = Invoke-GhSilent @(
                "issue", "comment", [string]$existingIssue.number,
                "--repo", $repoFullName,
                "--body-file", $bodyPath
            )
        }
        elseif (!$canManageLabels) {
            $result = Invoke-GhSilent @(
                "issue", "create",
                "--repo", $repoFullName,
                "--title", $title,
                "--body-file", $bodyPath
            )
        }
        else {
            $result = Invoke-GhSilent @(
                "issue", "create",
                "--repo", $repoFullName,
                "--title", $title,
                "--body-file", $bodyPath,
                "--label", ($labels -join ",")
            )
        }

        if ($result.Code -eq 0) {
            Write-StatusOk "Hata raporu gonderildi."
        }
        else {
            Write-StatusWarn "Hata raporu GitHub'a gonderilemedi."
            Write-Host $result.Output
            Write-ThemeValue "yerel rapor" $bodyPath
        }
    }
    catch {
        try {
            Write-StatusWarn "Hata raporu hazirlanamadi."
            Write-Host $_.Exception.Message
        }
        catch {
        }
    }
    finally {
        $script:IsSendingErrorReport = $false
    }
}

function Get-ClientStatusSignature($activeGhUser) {
    return Get-ClientId $activeGhUser
}

function Get-ClientStatusCache {
    if (!(Test-Path -LiteralPath $ClientStatusCachePath)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $ClientStatusCachePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Save-ClientStatusCache($signature, $activeGhUser) {
    Ensure-Storage

    $cache = [PSCustomObject]@{
        SchemaVersion = $ClientStatusSchemaVersion
        SentAt = (Get-Date).ToUniversalTime().ToString("o")
        Signature = $signature
        Version = $AppVersion
        GitHubUser = $activeGhUser
        Computer = $env:COMPUTERNAME
        WindowsUser = "$env:USERDOMAIN\$env:USERNAME"
    }

    $json = $cache | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($ClientStatusCachePath, $json, [System.Text.UTF8Encoding]::new($false))
}

function Save-ClientStatusDiagnostic($status, $detail = "") {
    try {
        Ensure-Storage

        $diagnostic = [PSCustomObject]@{
            SchemaVersion = 1
            CheckedAt = (Get-Date).ToUniversalTime().ToString("o")
            Status = [string]$status
            Detail = [string]$detail
            Version = $AppVersion
            HasEmbeddedTelemetryKey = (![string]::IsNullOrWhiteSpace($TelemetryKeyId) -and ![string]::IsNullOrWhiteSpace($TelemetryPublicKey))
            HasCachedTelemetryKey = ($null -ne (Get-TelemetryKeyFromManifest ((Get-UpdateCheckCache).Manifest)))
            HasLocalManifestTelemetryKey = ($null -ne (Get-TelemetryKeyFromManifest (Get-LocalAdminManifest)))
        }

        $json = $diagnostic | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($ClientStatusDiagPath, $json, [System.Text.UTF8Encoding]::new($false))
    }
    catch {
    }
}

function Test-ClientStatusCacheFresh($signature, $activeGhUser) {
    $cache = Get-ClientStatusCache

    if ($null -eq $cache) {
        return $false
    }

    if ([int]($cache.SchemaVersion) -ne [int]$ClientStatusSchemaVersion) {
        return $false
    }

    if ([string]$cache.Signature -ne [string]$signature) {
        return $false
    }

    if ([string]$cache.Version -ne [string]$AppVersion) {
        return $false
    }

    if ([string]$cache.GitHubUser -ne [string]$activeGhUser) {
        return $false
    }

    try {
        $sentAt = [DateTimeOffset]::Parse([string]$cache.SentAt)
        return (([DateTimeOffset]::UtcNow - $sentAt).TotalMinutes -lt 60)
    }
    catch {
        return $false
    }
}

function Queue-ClientStatusEvent($actionName = "app-open", $actionRepo = "", $actionSite = "") {
    try {
        Ensure-Storage

        if (!(Test-Path -LiteralPath $TelemetryQueueDir)) {
            New-Item -ItemType Directory -Path $TelemetryQueueDir -Force | Out-Null
        }

        $cleanAction = ([string]$actionName).Trim()

        if ([string]::IsNullOrWhiteSpace($cleanAction)) {
            $cleanAction = "app-open"
        }

        $event = [PSCustomObject]@{
            SchemaVersion = 1
            QueuedAt = (Get-Date).ToUniversalTime().ToString("o")
            AppVersion = $AppVersion
            Computer = $env:COMPUTERNAME
            WindowsUser = "$env:USERDOMAIN\$env:USERNAME"
            WorkingDirectory = (Get-Location).Path
            BatPath = $env:BAT_FILE
            Action = $cleanAction
            ActionRepo = [string]$actionRepo
            ActionSiteUrl = [string]$actionSite
        }

        $path = Join-Path $TelemetryQueueDir ("usage-" + (Get-Date -Format "yyyyMMdd-HHmmss") + "-" + ([Guid]::NewGuid().ToString("N")) + ".json")
        $json = $event | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
        return $path
    }
    catch {
        return $null
    }
}

function Clear-ClientStatusQueue {
    try {
        if (!(Test-Path -LiteralPath $TelemetryQueueDir)) {
            return
        }

        Get-ChildItem -LiteralPath $TelemetryQueueDir -Filter "*.json" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    catch {
    }
}

function Start-ClientStatusWorker($actionName = "app-open", $actionRepo = "", $actionSite = "") {
    try {
        Queue-ClientStatusEvent $actionName $actionRepo $actionSite | Out-Null

        $keyInfo = Get-EffectiveTelemetryKeyInfo

        if ($null -eq $keyInfo) {
            Save-ClientStatusDiagnostic "no-key" "Telemetry public key bulunamadi."
            return
        }

        $repoFullName = Get-EffectiveErrorReportRepo

        if ([string]::IsNullOrWhiteSpace($repoFullName)) {
            Save-ClientStatusDiagnostic "no-repo" "Telemetry issue reposu ayarlanmamis."
            return
        }

        Ensure-Storage

        if (Test-Path -LiteralPath $TelemetryWorkerLockPath) {
            $lockAgeSeconds = ((Get-Date) - (Get-Item -LiteralPath $TelemetryWorkerLockPath).LastWriteTime).TotalSeconds

            if ($lockAgeSeconds -lt 120) {
                Save-ClientStatusDiagnostic "worker-running" "Telemetry worker zaten calisiyor."
                return
            }

            Remove-Item -LiteralPath $TelemetryWorkerLockPath -Force -ErrorAction SilentlyContinue
            Save-ClientStatusDiagnostic "worker-timeout" "Eski telemetry worker kilidi zaman asimina ugradi; yeni worker baslatiliyor."
        }

        $workerConfig = [PSCustomObject]@{
            SchemaVersion = 1
            StoreDir = $StoreDir
            QueueDir = $TelemetryQueueDir
            LockPath = $TelemetryWorkerLockPath
            DiagPath = $ClientStatusDiagPath
            CachePath = $ClientStatusCachePath
            DbPath = $DbPath
            WorkDir = (Join-Path $StoreDir "client-status")
            RepoFullName = $repoFullName
            AppVersion = $AppVersion
            BatPath = [string]$env:BAT_FILE
            KeyId = [string]$keyInfo.KeyId
            PublicKey = [string]$keyInfo.PublicKey
            ClientStatusSchemaVersion = $ClientStatusSchemaVersion
        }

        $configJson = $workerConfig | ConvertTo-Json -Depth 10 -Compress
        $configB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($configJson))

        $lock = [PSCustomObject]@{
            StartedAt = (Get-Date).ToUniversalTime().ToString("o")
            AppVersion = $AppVersion
        }
        [System.IO.File]::WriteAllText($TelemetryWorkerLockPath, ($lock | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))

        $workerScript = @'
$ErrorActionPreference = "Stop"
$env:GH_PROMPT_DISABLED = "1"
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$configJson = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("__CONFIG_B64__"))
$config = $configJson | ConvertFrom-Json

function Save-Diagnostic($status, $detail = "") {
    try {
        $diagnostic = [PSCustomObject]@{
            SchemaVersion = 1
            CheckedAt = (Get-Date).ToUniversalTime().ToString("o")
            Status = [string]$status
            Detail = [string]$detail
            Version = [string]$config.AppVersion
            HasEmbeddedTelemetryKey = (![string]::IsNullOrWhiteSpace([string]$config.KeyId) -and ![string]::IsNullOrWhiteSpace([string]$config.PublicKey))
            HasCachedTelemetryKey = $false
            HasLocalManifestTelemetryKey = $false
        }

        $json = $diagnostic | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText([string]$config.DiagPath, $json, $script:Utf8NoBom)
    }
    catch {
    }
}

function Command-Exists($name) {
    return $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

function Invoke-GhSilent($argsList) {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = @()
    $code = 1

    try {
        $output = & gh @argsList 2>&1
        $code = $LASTEXITCODE
    }
    catch {
        $output = @($_.Exception.Message)
        $code = 1
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }

    return [PSCustomObject]@{
        Code = $code
        Output = ($output -join [Environment]::NewLine)
    }
}

function Get-ActiveGitHubUser {
    $result = Invoke-GhSilent @("api", "user", "--jq", ".login")

    if ($result.Code -ne 0 -or [string]::IsNullOrWhiteSpace($result.Output)) {
        return $null
    }

    return $result.Output.Trim()
}

function Get-ShortSha256($seed) {
    $sha = [System.Security.Cryptography.SHA256]::Create()

    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$seed)
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash).Replace("-", "").Substring(0, 16)).ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-ClientId($activeGhUser) {
    $seed = (@($env:COMPUTERNAME, $env:USERDOMAIN, $env:USERNAME, $activeGhUser) | ForEach-Object {
        ([string]$_).Trim().ToLowerInvariant()
    }) -join "|"
    return Get-ShortSha256 $seed
}

function Get-RegisteredRepos {
    $repoItems = New-Object System.Collections.ArrayList

    try {
        if (!(Test-Path -LiteralPath ([string]$config.DbPath))) {
            return @()
        }

        $raw = [System.IO.File]::ReadAllText([string]$config.DbPath, [System.Text.Encoding]::UTF8)

        if ([string]::IsNullOrWhiteSpace($raw)) {
            return @()
        }

        $repos = @($raw | ConvertFrom-Json)

        foreach ($repo in $repos) {
            if ($null -eq $repo) {
                continue
            }

            [void]$repoItems.Add([PSCustomObject]@{
                fullName = [string]$repo.FullName
                siteUrl = [string]$repo.SiteUrl
                repoUrl = [string]$repo.RepoUrl
                localPath = [string]$repo.LocalPath
                updatedAt = [string]$repo.UpdatedAt
            })
        }
    }
    catch {
    }

    return @($repoItems.ToArray())
}

function Get-QueuedEvents {
    $items = New-Object System.Collections.ArrayList

    try {
        if (!(Test-Path -LiteralPath ([string]$config.QueueDir))) {
            return @()
        }

        foreach ($file in @(Get-ChildItem -LiteralPath ([string]$config.QueueDir) -Filter "*.json" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)) {
            try {
                $raw = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
                $event = $raw | ConvertFrom-Json
                $event | Add-Member -NotePropertyName QueueFile -NotePropertyValue $file.FullName -Force
                [void]$items.Add($event)
            }
            catch {
            }
        }
    }
    catch {
    }

    return @($items.ToArray())
}

function New-TelemetryPayload($kind, $activeGhUser, $clientId, $event, $repos) {
    $windowsUser = [string]$event.WindowsUser

    if ([string]::IsNullOrWhiteSpace($windowsUser)) {
        $windowsUser = $env:USERNAME

        if (![string]::IsNullOrWhiteSpace($env:USERDOMAIN)) {
            $windowsUser = "$env:USERDOMAIN\$env:USERNAME"
        }
    }

    $timestamp = [string]$event.QueuedAt

    if ([string]::IsNullOrWhiteSpace($timestamp)) {
        $timestamp = (Get-Date).ToString("s")
    }

    $workingDirectory = [string]$event.WorkingDirectory

    if ([string]::IsNullOrWhiteSpace($workingDirectory)) {
        $workingDirectory = (Get-Location).Path
    }

    $batPath = [string]$event.BatPath

    if ([string]::IsNullOrWhiteSpace($batPath)) {
        $batPath = [string]$config.BatPath
    }

    $nowUtc = (Get-Date).ToUniversalTime().ToString("s") + "Z"
    $actionName = ([string]$event.Action).Trim()

    if ([string]::IsNullOrWhiteSpace($actionName)) {
        $actionName = "app-open"
    }

    return [PSCustomObject]@{
        schemaVersion = 1
        kind = $kind
        clientId = $clientId
        timestamp = $timestamp
        utc = $nowUtc
        lastSeenUtc = $nowUtc
        appVersion = [string]$config.AppVersion
        computer = $env:COMPUTERNAME
        windowsUser = $windowsUser
        githubUser = $activeGhUser
        workingDirectory = $workingDirectory
        batPath = $batPath
        action = $actionName
        actionRepo = [string]$event.ActionRepo
        actionSiteUrl = [string]$event.ActionSiteUrl
        repos = @($repos)
    }
}

function Protect-TelemetryPayload($payload) {
    if ([string]::IsNullOrWhiteSpace([string]$config.KeyId) -or [string]::IsNullOrWhiteSpace([string]$config.PublicKey)) {
        return $null
    }

    $publicXml = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$config.PublicKey))
    $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider 2048
    $aes = [System.Security.Cryptography.Aes]::Create()

    try {
        $rsa.FromXmlString($publicXml)
        $aes.KeySize = 256
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.GenerateKey()
        $aes.GenerateIV()

        $json = $payload | ConvertTo-Json -Depth 30 -Compress
        $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $encryptor = $aes.CreateEncryptor()
        $cipherBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
        $encryptedKey = $rsa.Encrypt($aes.Key, $false)

        return [PSCustomObject]@{
            schemaVersion = 1
            kind = "gpm-encrypted-telemetry"
            keyId = [string]$config.KeyId
            clientId = $payload.clientId
            payloadKind = $payload.kind
            algorithm = "RSA-PKCS1+A256-CBC"
            encryptedKey = [Convert]::ToBase64String($encryptedKey)
            iv = [Convert]::ToBase64String($aes.IV)
            ciphertext = [Convert]::ToBase64String($cipherBytes)
            createdAt = (Get-Date).ToUniversalTime().ToString("s") + "Z"
        }
    }
    finally {
        if ($null -ne $aes) {
            $aes.Dispose()
        }

        if ($null -ne $rsa) {
            $rsa.Dispose()
        }
    }
}

function New-EncryptedTelemetryBody($payload) {
    $envelope = Protect-TelemetryPayload $payload

    if ($null -eq $envelope) {
        return $null
    }

    $json = $envelope | ConvertTo-Json -Depth 20
    $lines = @(
        "## GPM Encrypted Telemetry",
        "",
        "- Kind: $($payload.kind)",
        "- Client ID: gpm-client:$($payload.clientId)",
        "- Key ID: $($envelope.keyId)",
        "",
        '```json',
        $json,
        '```'
    )

    return ($lines -join [Environment]::NewLine)
}

function Find-ExistingClientIssue($clientId) {
    $result = Invoke-GhSilent @(
        "issue", "list",
        "--repo", ([string]$config.RepoFullName),
        "--state", "open",
        "--limit", "100",
        "--json", "number,title,url,body,labels"
    )

    if ($result.Code -ne 0 -or [string]::IsNullOrWhiteSpace($result.Output)) {
        return $null
    }

    try {
        $issues = @($result.Output | ConvertFrom-Json)
        $expectedTitle = "[GPM Telemetry] $clientId"
        $issue = $issues | Where-Object {
            $null -ne $_.title -and [string]$_.title -eq $expectedTitle
        } | Select-Object -First 1

        if ($null -ne $issue) {
            return $issue
        }

        return ($issues | Where-Object {
            $hasTelemetryLabel = $false

            foreach ($label in @($_.labels)) {
                $labelName = ""

                if ($null -ne $label -and $null -ne $label.PSObject.Properties["name"]) {
                    $labelName = [string]$label.name
                }
                elseif ($null -ne $label) {
                    $labelName = [string]$label
                }

                if ($labelName -eq "gpm-telemetry") {
                    $hasTelemetryLabel = $true
                    break
                }
            }

            $hasTelemetryLabel -and ($null -ne $_.body -and ([string]$_.body).Contains("gpm-client:$clientId"))
        } | Select-Object -First 1)
    }
    catch {
        return $null
    }
}

function Write-WorkerTextFile($path, $content) {
    $parent = Split-Path -Parent $path

    if (!(Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($path, [string]$content, $script:Utf8NoBom)
}

try {
    if (!(Command-Exists "gh")) {
        Save-Diagnostic "no-gh" "GitHub CLI bulunamadi."
        return
    }

    if ([string]::IsNullOrWhiteSpace([string]$config.KeyId) -or [string]::IsNullOrWhiteSpace([string]$config.PublicKey)) {
        Save-Diagnostic "no-key" "Telemetry public key bulunamadi."
        return
    }

    if ([string]::IsNullOrWhiteSpace([string]$config.RepoFullName)) {
        Save-Diagnostic "no-repo" "Telemetry issue reposu ayarlanmamis."
        return
    }

    $activeGhUser = Get-ActiveGitHubUser

    if ([string]::IsNullOrWhiteSpace($activeGhUser)) {
        Save-Diagnostic "no-auth" "Aktif GitHub kullanicisi alinamadi."
        return
    }

    if (!(Test-Path -LiteralPath ([string]$config.WorkDir))) {
        New-Item -ItemType Directory -Path ([string]$config.WorkDir) -Force | Out-Null
    }

    $clientId = Get-ClientId $activeGhUser
    $totalSentCount = 0
    $processedBatchCount = 0
    $sentHeartbeat = $false

    for ($batchIndex = 0; $batchIndex -lt 4; $batchIndex++) {
        $events = @(Get-QueuedEvents)

        if ($events.Count -eq 0) {
            if ($processedBatchCount -gt 0 -or $sentHeartbeat) {
                break
            }

            $events = @([PSCustomObject]@{
                QueuedAt = (Get-Date).ToUniversalTime().ToString("o")
                AppVersion = [string]$config.AppVersion
                Computer = $env:COMPUTERNAME
                WindowsUser = "$env:USERDOMAIN\$env:USERNAME"
                WorkingDirectory = (Get-Location).Path
                BatPath = [string]$config.BatPath
                Action = "app-open"
                ActionRepo = ""
                ActionSiteUrl = ""
            })
            $sentHeartbeat = $true
        }

        $repos = @(Get-RegisteredRepos)
        $latestEvent = @($events | Sort-Object QueuedAt -Descending | Select-Object -First 1)[0]
        $statusPayload = New-TelemetryPayload "status" $activeGhUser $clientId $latestEvent $repos
        $statusBody = New-EncryptedTelemetryBody $statusPayload

        if ([string]::IsNullOrWhiteSpace($statusBody)) {
            Save-Diagnostic "no-key" "Encrypted telemetry body olusturulamadi."
            return
        }

        $statusPath = Join-Path ([string]$config.WorkDir) ("client-status-" + $clientId + ".md")
        Write-WorkerTextFile $statusPath $statusBody

        $title = "[GPM Telemetry] $clientId"
        $existingIssue = Find-ExistingClientIssue $clientId
        $issueNumber = $null
        $result = $null

        if ($null -ne $existingIssue) {
            $issueNumber = [string]$existingIssue.number
            $result = Invoke-GhSilent @(
                "issue", "edit", $issueNumber,
                "--repo", ([string]$config.RepoFullName),
                "--title", $title,
                "--body-file", $statusPath
            )
        }
        else {
            $result = Invoke-GhSilent @(
                "issue", "create",
                "--repo", ([string]$config.RepoFullName),
                "--title", $title,
                "--body-file", $statusPath
            )

            if ($result.Code -eq 0 -and $result.Output -match '/issues/(\d+)') {
                $issueNumber = $matches[1]
            }

            if ([string]::IsNullOrWhiteSpace($issueNumber)) {
                $existingIssue = Find-ExistingClientIssue $clientId

                if ($null -ne $existingIssue) {
                    $issueNumber = [string]$existingIssue.number
                    $result = Invoke-GhSilent @(
                        "issue", "edit", $issueNumber,
                        "--repo", ([string]$config.RepoFullName),
                        "--title", $title,
                        "--body-file", $statusPath
                    )
                }
            }
        }

        if ($null -eq $result -or $result.Code -ne 0 -or [string]::IsNullOrWhiteSpace($issueNumber)) {
            $failureDetail = ""

            if ($null -ne $result) {
                $failureDetail = [string]$result.Output
            }

            Save-Diagnostic "issue-failed" $failureDetail
            return
        }

        $sentCount = 0

        foreach ($event in $events) {
            $usagePayload = New-TelemetryPayload "usage" $activeGhUser $clientId $event $repos
            $usageBody = New-EncryptedTelemetryBody $usagePayload

            if ([string]::IsNullOrWhiteSpace($usageBody)) {
                Save-Diagnostic "no-key" "Encrypted usage body olusturulamadi."
                return
            }

            $usagePath = Join-Path ([string]$config.WorkDir) ("usage-" + $clientId + "-" + (Get-Date -Format "yyyyMMdd-HHmmss") + "-" + $sentCount + ".md")
            Write-WorkerTextFile $usagePath $usageBody
            $commentResult = Invoke-GhSilent @(
                "issue", "comment", $issueNumber,
                "--repo", ([string]$config.RepoFullName),
                "--body-file", $usagePath
            )

            if ($commentResult.Code -ne 0) {
                Save-Diagnostic "issue-failed" $commentResult.Output
                return
            }

            $sentCount++
        }

        $totalSentCount += $sentCount

        foreach ($event in $events) {
            if (![string]::IsNullOrWhiteSpace([string]$event.QueueFile) -and (Test-Path -LiteralPath ([string]$event.QueueFile))) {
                Remove-Item -LiteralPath ([string]$event.QueueFile) -Force -ErrorAction SilentlyContinue
            }
        }

        $processedBatchCount++

        if ($sentHeartbeat) {
            break
        }

        Start-Sleep -Seconds 2
    }

    if ($processedBatchCount -eq 0 -and !$sentHeartbeat) {
        Save-Diagnostic "ok" "Telemetry kuyrugu bos."
        return
    }

    $cache = [PSCustomObject]@{
        SchemaVersion = [int]$config.ClientStatusSchemaVersion
        SentAt = (Get-Date).ToUniversalTime().ToString("o")
        Signature = $clientId
        Version = [string]$config.AppVersion
        GitHubUser = $activeGhUser
        Computer = $env:COMPUTERNAME
        WindowsUser = "$env:USERDOMAIN\$env:USERNAME"
    }
    [System.IO.File]::WriteAllText([string]$config.CachePath, ($cache | ConvertTo-Json -Depth 10), $script:Utf8NoBom)

    Save-Diagnostic "ok" "Telemetry issue guncellendi. $totalSentCount kullanim kaydi gonderildi."
}
catch {
    Save-Diagnostic "worker-crashed" $_.Exception.Message
}
finally {
    try {
        if (Test-Path -LiteralPath ([string]$config.LockPath)) {
            Remove-Item -LiteralPath ([string]$config.LockPath) -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
    }
}
'@.Replace("__CONFIG_B64__", $configB64)

        [System.IO.File]::WriteAllText($TelemetryWorkerPath, $workerScript, [System.Text.UTF8Encoding]::new($true))
        Save-ClientStatusDiagnostic "queued" "Telemetry arka planda gonderilecek."
        $workerPowerShell = Get-GpmPowerShellCommand
        if (Test-GpmLinux) {
            Start-Process -FilePath $workerPowerShell -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $TelemetryWorkerPath) | Out-Null
        }
        else {
            Start-Process -FilePath $workerPowerShell -WindowStyle Hidden -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $TelemetryWorkerPath) | Out-Null
        }
    }
    catch {
        Remove-Item -LiteralPath $TelemetryWorkerLockPath -Force -ErrorAction SilentlyContinue
        Save-ClientStatusDiagnostic "worker-failed" $_.Exception.Message
    }
}

function Find-ExistingClientStatusIssue($repoFullName, $signature) {
    if ([string]::IsNullOrWhiteSpace($signature)) {
        return $null
    }

    $expectedTitle = "[GPM Telemetry] $signature"

    $result = Invoke-GhSilent @(
        "issue", "list",
        "--repo", $repoFullName,
        "--state", "open",
        "--search", "gpm-client:$signature",
        "--json", "number,title,url,body,labels"
    )

    if ($result.Code -eq 0 -and ![string]::IsNullOrWhiteSpace($result.Output)) {
        try {
            $issues = @($result.Output | ConvertFrom-Json)
            $issue = $issues | Where-Object {
                $null -ne $_.title -and [string]$_.title -eq $expectedTitle
            } | Select-Object -First 1

            if ($null -ne $issue) {
                return $issue
            }

            $issue = $issues | Where-Object {
                $hasTelemetryLabel = $false

                foreach ($label in @($_.labels)) {
                    $labelName = ""

                    if ($null -ne $label -and $null -ne $label.PSObject.Properties["name"]) {
                        $labelName = [string]$label.name
                    }
                    elseif ($null -ne $label) {
                        $labelName = [string]$label
                    }

                    if ($labelName -eq "gpm-telemetry") {
                        $hasTelemetryLabel = $true
                        break
                    }
                }

                $hasTelemetryLabel -and ($null -ne $_.body -and ([string]$_.body).Contains("gpm-client:$signature"))
            } | Select-Object -First 1

            if ($null -ne $issue) {
                return $issue
            }
        }
        catch {
        }
    }

    $result = Invoke-GhSilent @(
        "issue", "list",
        "--repo", $repoFullName,
        "--state", "open",
        "--limit", "100",
        "--json", "number,title,url,body,labels"
    )

    if ($result.Code -ne 0 -or [string]::IsNullOrWhiteSpace($result.Output)) {
        return $null
    }

    try {
        $issues = @($result.Output | ConvertFrom-Json)
        $issue = $issues | Where-Object {
            $null -ne $_.title -and [string]$_.title -eq $expectedTitle
        } | Select-Object -First 1

        if ($null -ne $issue) {
            return $issue
        }

        return ($issues | Where-Object {
            $hasTelemetryLabel = $false

            foreach ($label in @($_.labels)) {
                $labelName = ""

                if ($null -ne $label -and $null -ne $label.PSObject.Properties["name"]) {
                    $labelName = [string]$label.name
                }
                elseif ($null -ne $label) {
                    $labelName = [string]$label
                }

                if ($labelName -eq "gpm-telemetry") {
                    $hasTelemetryLabel = $true
                    break
                }
            }

            $hasTelemetryLabel -and ($null -ne $_.body -and ([string]$_.body).Contains("gpm-client:$signature"))
        } | Select-Object -First 1)
    }
    catch {
        return $null
    }
}

function Submit-ClientStatus {
    if ($script:IsSendingClientStatus) {
        return
    }

    $script:IsSendingClientStatus = $true

    try {
        if (!(Command-Exists "gh")) {
            Save-ClientStatusDiagnostic "no-gh" "GitHub CLI bulunamadi."
            return
        }

        $repoFullName = Get-EffectiveErrorReportRepo

        if ([string]::IsNullOrWhiteSpace($repoFullName)) {
            Save-ClientStatusDiagnostic "no-repo" "Telemetry issue reposu ayarlanmamis."
            return
        }

        $activeGhUser = $script:GhUser

        if ([string]::IsNullOrWhiteSpace($activeGhUser)) {
            $activeGhUser = Get-ActiveGitHubUser
        }

        if ([string]::IsNullOrWhiteSpace($activeGhUser)) {
            Save-ClientStatusDiagnostic "no-auth" "Aktif GitHub kullanicisi alinamadi."
            return
        }

        if (!(Test-TelemetryEncryptionAvailable)) {
            Save-ClientStatusDiagnostic "no-key" "Telemetry public key bulunamadi."
            return
        }

        $events = @(Get-QueuedEvents)

        if ($events.Count -eq 0) {
            $events = @([PSCustomObject]@{
                QueuedAt = (Get-Date).ToUniversalTime().ToString("o")
                AppVersion = $AppVersion
                Computer = $env:COMPUTERNAME
                WindowsUser = "$env:USERDOMAIN\$env:USERNAME"
                WorkingDirectory = (Get-Location).Path
                BatPath = $env:BAT_FILE
                Action = "app-open"
                ActionRepo = ""
                ActionSiteUrl = ""
            })
        }

        $latestEvent = @($events | Sort-Object QueuedAt -Descending | Select-Object -First 1)[0]
        $latestAction = ([string]$latestEvent.Action).Trim()

        if ([string]::IsNullOrWhiteSpace($latestAction)) {
            $latestAction = "app-open"
        }

        $signature = Get-ClientStatusSignature $activeGhUser
        $statusPayload = New-TelemetryPayload "status" $activeGhUser $signature $latestAction ([string]$latestEvent.ActionRepo) ([string]$latestEvent.ActionSiteUrl)
        $usagePayload = New-TelemetryPayload "usage" $activeGhUser $signature $latestAction ([string]$latestEvent.ActionRepo) ([string]$latestEvent.ActionSiteUrl)
        $statusBody = New-EncryptedTelemetryBody $statusPayload
        $usageBody = New-EncryptedTelemetryBody $usagePayload

        if ([string]::IsNullOrWhiteSpace($statusBody) -or [string]::IsNullOrWhiteSpace($usageBody)) {
            Save-ClientStatusDiagnostic "no-key" "Encrypted telemetry body olusturulamadi."
            return
        }

        $canManageLabels = Test-CanManageIssueLabels $repoFullName
        $labels = @("gpm-telemetry", "gpm-v$AppVersion", "gpm-client-$signature")

        if ($canManageLabels) {
            Ensure-IssueLabels $repoFullName $labels
        }

        $reportsDir = Join-Path $StoreDir "client-status"
        New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null

        $bodyPath = Join-Path $reportsDir ("client-status-" + $signature + ".md")
        [System.IO.File]::WriteAllText($bodyPath, $statusBody, [System.Text.UTF8Encoding]::new($false))

        $existingIssue = Find-ExistingClientStatusIssue $repoFullName $signature
        $title = "[GPM Telemetry] $signature"
        $usageCommentSent = $false

        if ($null -ne $existingIssue) {
            $result = Invoke-GhSilent @(
                "issue", "edit", [string]$existingIssue.number,
                "--repo", $repoFullName,
                "--title", $title,
                "--body-file", $bodyPath
            )

            if ($result.Code -eq 0) {
                Save-ClientStatusCache $signature $activeGhUser
            }

            $usagePath = Join-Path $reportsDir ("usage-" + $signature + "-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".md")
            [System.IO.File]::WriteAllText($usagePath, $usageBody, [System.Text.UTF8Encoding]::new($false))

            $commentResult = Invoke-GhSilent @(
                "issue", "comment", [string]$existingIssue.number,
                "--repo", $repoFullName,
                "--body-file", $usagePath
            )

            if ($commentResult.Code -eq 0) {
                $usageCommentSent = $true
            }

            if ($result.Code -ne 0 -and $commentResult.Code -ne 0) {
                $result = $commentResult
            }
        }
        elseif ($canManageLabels) {
            $result = Invoke-GhSilent @(
                "issue", "create",
                "--repo", $repoFullName,
                "--title", $title,
                "--body-file", $bodyPath,
                "--label", ($labels -join ",")
            )

            if ($result.Code -eq 0) {
                $existingIssue = Find-ExistingClientStatusIssue $repoFullName $signature

                if ($null -eq $existingIssue -and $result.Output -match '/issues/(\d+)') {
                    $existingIssue = [PSCustomObject]@{
                        number = $matches[1]
                    }
                }
            }
        }
        else {
            $result = Invoke-GhSilent @(
                "issue", "create",
                "--repo", $repoFullName,
                "--title", $title,
                "--body-file", $bodyPath
            )

            if ($result.Code -eq 0) {
                $existingIssue = Find-ExistingClientStatusIssue $repoFullName $signature

                if ($null -eq $existingIssue -and $result.Output -match '/issues/(\d+)') {
                    $existingIssue = [PSCustomObject]@{
                        number = $matches[1]
                    }
                }
            }
        }

        if ($result.Code -eq 0) {
            Save-ClientStatusCache $signature $activeGhUser
            Save-ClientStatusDiagnostic "ok" "Telemetry issue guncellendi."
            Clear-ClientStatusQueue

            if ($null -ne $existingIssue) {
                if (!$usageCommentSent) {
                    $usagePath = Join-Path $reportsDir ("usage-" + $signature + "-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".md")
                    [System.IO.File]::WriteAllText($usagePath, $usageBody, [System.Text.UTF8Encoding]::new($false))
                    Invoke-GhSilent @(
                        "issue", "comment", [string]$existingIssue.number,
                        "--repo", $repoFullName,
                        "--body-file", $usagePath
                    ) | Out-Null
                }
            }
        }
        else {
            Save-ClientStatusDiagnostic "issue-failed" $result.Output
        }
    }
    catch {
        Save-ClientStatusDiagnostic "issue-failed" $_.Exception.Message
    }
    finally {
        $script:IsSendingClientStatus = $false
    }
}

function Get-UpdateArtifactLabel {
    if (Test-GpmLinux) {
        return "Linux SH"
    }

    return "BAT"
}

function Get-UpdateRootFileName {
    if (Test-GpmLinux) {
        return "github-pages-manager-linux-single.sh"
    }

    return "github-pages-manager.bat"
}

function Get-UpdateFileExtension {
    if (Test-GpmLinux) {
        return ".sh"
    }

    return ".bat"
}

function Get-UpdateArtifactFileInfo($manifest) {
    if ($null -eq $manifest -or $null -eq $manifest.files) {
        return $null
    }

    if (Test-GpmLinux) {
        return $manifest.files.managerSh
    }

    return $manifest.files.managerBat
}

function Get-MissingUpdateArtifactMessage($manifest) {
    if (Test-GpmLinux) {
        $version = [string]$manifest.version

        if ([string]::IsNullOrWhiteSpace($version)) {
            $version = "yayindaki"
        }

        return "$version release Linux SH guncelleme paketi icermiyor. Bu release sadece BAT yayinlamis olabilir. Admin aracindan Linux SH iceren yeni release yayinla veya github-pages-manager-linux-single.sh dosyasini elle yenisiyle degistir."
    }

    return "Manifest icinde indirilecek BAT bilgisi yok."
}

function Get-UpdateDownloadCandidates($manifest, $manifestUrl) {
    $fileInfo = Get-UpdateArtifactFileInfo $manifest
    $candidates = New-Object System.Collections.ArrayList
    $seen = @{}

    if ($null -eq $fileInfo) {
        throw (Get-MissingUpdateArtifactMessage $manifest)
    }

    function Add-Candidate($kind, $source, $label) {
        if ([string]::IsNullOrWhiteSpace($source)) {
            return
        }

        $key = "$kind|$source"

        if ($seen.ContainsKey($key)) {
            return
        }

        $seen[$key] = $true
        $null = $candidates.Add([PSCustomObject]@{
            Kind = $kind
            Source = $source
            Label = $label
        })
    }

    Add-Candidate "url" $fileInfo.downloadUrl "Manifest downloadUrl"

    foreach ($url in @($fileInfo.alternativeUrls)) {
        Add-Candidate "url" ([string]$url) "Manifest alternativeUrl"
    }

    $repoFullName = Get-RepoFullNameFromRawUrl $manifestUrl

    if ([string]::IsNullOrWhiteSpace($repoFullName)) {
        $repoFullName = Get-RepoFullNameFromRawUrl $manifest.latestJsonUrl
    }

    if ([string]::IsNullOrWhiteSpace($repoFullName)) {
        $repoFullName = Get-RepoFullNameFromRawUrl $fileInfo.downloadUrl
    }

    $artifactPath = $fileInfo.path

    if ([string]::IsNullOrWhiteSpace($artifactPath) -and ![string]::IsNullOrWhiteSpace($fileInfo.name)) {
        $artifactPath = "releases/$($fileInfo.name)"
    }

    if (![string]::IsNullOrWhiteSpace($repoFullName) -and ![string]::IsNullOrWhiteSpace($artifactPath)) {
        if (![string]::IsNullOrWhiteSpace($manifest.sourceRef)) {
            Add-Candidate "url" "https://raw.githubusercontent.com/$repoFullName/$($manifest.sourceRef)/$artifactPath" "Commit/ref sabit URL"
        }

        Add-Candidate "url" "https://raw.githubusercontent.com/$repoFullName/main/$artifactPath" "Main versioned URL"
    }

    if (![string]::IsNullOrWhiteSpace($repoFullName)) {
        Add-Candidate "url" "https://raw.githubusercontent.com/$repoFullName/main/$(Get-UpdateRootFileName)" "Uyumluluk root URL"
    }

    $adminRoot = Get-LocalAdminReleaseRoot

    if (Test-Path $adminRoot) {
        if (![string]::IsNullOrWhiteSpace($artifactPath)) {
            Add-Candidate "file" (Join-Path $adminRoot ($artifactPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)) "Yerel admin versioned release"
        }

        if (![string]::IsNullOrWhiteSpace($fileInfo.name)) {
            Add-Candidate "file" (Join-Path (Join-Path $adminRoot "releases") $fileInfo.name) "Yerel admin release adi"
        }

        Add-Candidate "file" (Join-Path $adminRoot (Get-UpdateRootFileName)) "Yerel admin root $(Get-UpdateArtifactLabel)"
    }

    return @($candidates.ToArray())
}

function Test-UpdateFileIntegrity($path, $fileInfo) {
    if (!(Test-Path $path)) {
        return [PSCustomObject]@{
            Valid = $false
            Hash = ""
            Size = 0
            Message = "Dosya bulunamadi."
        }
    }

    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $actualSize = (Get-Item -LiteralPath $path).Length
    $expectedHash = ""
    $expectedSize = 0

    if (![string]::IsNullOrWhiteSpace($fileInfo.sha256)) {
        $expectedHash = $fileInfo.sha256.ToLowerInvariant()
    }

    if ($null -ne $fileInfo.sizeBytes) {
        $expectedSize = [int64]$fileInfo.sizeBytes
    }

    $hashOk = [string]::IsNullOrWhiteSpace($expectedHash) -or $actualHash -eq $expectedHash
    $sizeOk = $expectedSize -le 0 -or $actualSize -eq $expectedSize
    $message = ""

    if (!$hashOk) {
        $message += "SHA256 uyusmuyor. "
    }

    if (!$sizeOk) {
        $message += "Boyut uyusmuyor. "
    }

    return [PSCustomObject]@{
        Valid = ($hashOk -and $sizeOk)
        Hash = $actualHash
        Size = $actualSize
        Message = $message.Trim()
    }
}

function Compare-VersionLabel($publishedVersion, $currentVersion) {
    if ([string]::IsNullOrWhiteSpace($publishedVersion) -or [string]::IsNullOrWhiteSpace($currentVersion)) {
        return "invalid"
    }

    if ($publishedVersion -eq $currentVersion) {
        return "same"
    }

    try {
        $published = [version]$publishedVersion
        $current = [version]$currentVersion

        if ($published -eq $current) {
            return "same"
        }

        if ($published -gt $current) {
            return "newer"
        }

        return "older"
    }
    catch {
        return "different"
    }
}

function Test-IsDifferentVersion($publishedVersion, $currentVersion) {
    $label = Compare-VersionLabel $publishedVersion $currentVersion
    return $label -ne "same" -and $label -ne "invalid"
}

function Get-UpdatePromptTitle($publishedVersion, $currentVersion) {
    switch (Compare-VersionLabel $publishedVersion $currentVersion) {
        "newer" { return "Yeni surum bulundu." }
        "older" { return "Yayindaki base surum farkli." }
        "different" { return "Farkli surum bulundu." }
        default { return "Surum bilgisi kontrol ediliyor." }
    }
}

function Get-ParentProcessId($processId) {
    try {
        if ([int]$processId -le 0) {
            return 0
        }

        $process = Get-CimInstance Win32_Process -Filter "ProcessId=$processId" -ErrorAction Stop

        if ($null -ne $process -and $null -ne $process.ParentProcessId) {
            return [int]$process.ParentProcessId
        }
    }
    catch {
    }

    return 0
}

function Test-UpdateTargetWritable($targetPath) {
    try {
        $targetDir = Split-Path -Parent $targetPath

        if ([string]::IsNullOrWhiteSpace($targetDir) -or !(Test-Path -LiteralPath $targetDir)) {
            return [PSCustomObject]@{
                Success = $false
                Message = "Hedef klasor bulunamadi: $targetDir"
            }
        }

        $probePath = Join-Path $targetDir (".gpm-update-write-test-" + ([Guid]::NewGuid().ToString("N")) + ".tmp")
        [System.IO.File]::WriteAllText($probePath, "ok", [System.Text.UTF8Encoding]::new($false))
        Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue

        return [PSCustomObject]@{
            Success = $true
            Message = ""
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

function Get-UpdateApplyDiagnostic {
    try {
        if (!(Test-Path -LiteralPath $UpdateApplyDiagPath)) {
            return $null
        }

        return Get-Content -LiteralPath $UpdateApplyDiagPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Get-UpdateFileSnapshot($path) {
    $snapshot = [ordered]@{
        Path = [string]$path
        Exists = $false
        Size = 0
        Sha256 = ""
        LastWriteUtc = ""
        Error = ""
    }

    try {
        if (![string]::IsNullOrWhiteSpace([string]$path) -and (Test-Path -LiteralPath $path)) {
            $item = Get-Item -LiteralPath $path -Force
            $snapshot.Exists = $true
            $snapshot.Size = [int64]$item.Length
            $snapshot.LastWriteUtc = $item.LastWriteTimeUtc.ToString("o")

            if (!$item.PSIsContainer) {
                $snapshot.Sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
    }
    catch {
        $snapshot.Error = $_.Exception.Message
    }

    return [PSCustomObject]$snapshot
}

function Write-UpdateApplyDiagnostic($status, $message, $details = @(), $source = "", $target = "", $backup = "", $targetVersion = "", $expectedHash = "", $expectedSize = 0) {
    try {
        $diagDir = Split-Path -Parent $UpdateApplyDiagPath

        if (![string]::IsNullOrWhiteSpace($diagDir) -and !(Test-Path -LiteralPath $diagDir)) {
            New-Item -ItemType Directory -Path $diagDir -Force | Out-Null
        }

        $manualRepair = ""

        if (!(Test-GpmLinux)) {
            $manualRepair = Join-Path (Split-Path -Parent $UpdateApplyDiagPath) "manual-repair.cmd"
        }

        $diag = [PSCustomObject]@{
            SchemaVersion = 1
            Status = [string]$status
            Message = [string]$message
            Details = @($details)
            Source = [string]$source
            Target = [string]$target
            Backup = [string]$backup
            ManualRepair = $manualRepair
            TargetVersion = [string]$targetVersion
            ExpectedHash = [string]$expectedHash
            ExpectedSize = [int64]$expectedSize
            AppVersion = [string]$AppVersion
            BatPath = [string]$env:BAT_FILE
            WorkingDirectory = (Get-Location).Path
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            SourceInfo = Get-UpdateFileSnapshot $source
            TargetInfo = Get-UpdateFileSnapshot $target
            BackupInfo = Get-UpdateFileSnapshot $backup
            UpdatedAt = (Get-Date).ToUniversalTime().ToString("o")
        }

        [System.IO.File]::WriteAllText($UpdateApplyDiagPath, ($diag | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
    }
    catch {
    }
}

function Get-LastProblemUpdateDiagnostic($targetVersion) {
    $diag = Get-UpdateApplyDiagnostic

    if ($null -eq $diag) {
        return $null
    }

    if ([string]$diag.Status -eq "ok") {
        if (![string]::IsNullOrWhiteSpace([string]$targetVersion) -and [string]$diag.TargetVersion -eq [string]$targetVersion) {
            return [PSCustomObject]@{
                Status = "stale-after-ok"
                Message = "Son guncelleme basarili gorunuyor ama bu BAT hala eski surumle acildi. Hedef dosya degismemis veya Windows eski kopyayi calistirmis olabilir."
                Details = @([string]$diag.Message)
                ManualRepair = [string]$diag.ManualRepair
                TargetVersion = [string]$diag.TargetVersion
                UpdatedAt = [string]$diag.UpdatedAt
            }
        }

        return $null
    }

    if (![string]::IsNullOrWhiteSpace([string]$targetVersion) -and ![string]::IsNullOrWhiteSpace([string]$diag.TargetVersion) -and [string]$diag.TargetVersion -ne [string]$targetVersion) {
        return $null
    }

    return $diag
}

function Invoke-LinuxSelfUpdate($downloadPath, $targetPath, $backupPath, $manifest, $fileInfo, $expectedHash, $expectedSizeValue) {
    $backupCreated = $false

    Write-UpdateApplyDiagnostic "started" "Linux guncelleme uygulanmaya basladi." @() $downloadPath $targetPath $backupPath ([string]$manifest.version) $expectedHash $expectedSizeValue

    try {
        if (!(Test-Path -LiteralPath $downloadPath)) {
            throw "Indirilen guncelleme dosyasi bulunamadi: $downloadPath"
        }

        $backupDir = Split-Path -Parent $backupPath

        if (![string]::IsNullOrWhiteSpace($backupDir) -and !(Test-Path -LiteralPath $backupDir)) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        }

        if (Test-Path -LiteralPath $targetPath) {
            Write-UpdateApplyDiagnostic "backup" "Mevcut SH yedekleniyor." @() $downloadPath $targetPath $backupPath ([string]$manifest.version) $expectedHash $expectedSizeValue
            Copy-Item -LiteralPath $targetPath -Destination $backupPath -Force
            $backupCreated = $true
        }

        Write-UpdateApplyDiagnostic "copying" "Yeni SH hedef dosyaya kopyalaniyor." @() $downloadPath $targetPath $backupPath ([string]$manifest.version) $expectedHash $expectedSizeValue
        Copy-Item -LiteralPath $downloadPath -Destination $targetPath -Force

        try {
            & chmod +x $targetPath
        }
        catch {
        }

        Write-UpdateApplyDiagnostic "verifying" "Yeni SH hedef dosyada dogrulaniyor." @() $downloadPath $targetPath $backupPath ([string]$manifest.version) $expectedHash $expectedSizeValue
        $targetCheck = Test-UpdateFileIntegrity $targetPath $fileInfo

        if (!$targetCheck.Valid) {
            throw "Kopyalama sonrasi dogrulama basarisiz. $($targetCheck.Message) SHA256: $($targetCheck.Hash) Boyut: $($targetCheck.Size)"
        }

        Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
        Write-UpdateApplyDiagnostic "ok" "Linux guncelleme uygulandi ve hedef SH dogrulandi." @() $downloadPath $targetPath $backupPath ([string]$manifest.version) $expectedHash $expectedSizeValue

        Write-StatusOk "Guncelleme uygulandi."

        if ($env:GPM_UPDATE_TEST_NO_RESTART -eq "1") {
            return
        }

        try {
            Start-Process -FilePath "bash" -ArgumentList @($targetPath) | Out-Null
        }
        catch {
            Write-UpdateApplyDiagnostic "restart-failed" "Guncelleme uygulandi fakat SH otomatik yeniden acilamadi. Dosyayi elle acabilirsin." @("restart failed: $($_.Exception.Message)") $downloadPath $targetPath $backupPath ([string]$manifest.version) $expectedHash $expectedSizeValue
            Write-StatusWarn "Guncelleme tamamlandi ama otomatik yeniden acilamadi. Dosyayi elle tekrar ac."
        }
    }
    catch {
        $message = $_.Exception.Message
        $details = New-Object System.Collections.ArrayList

        if ($backupCreated -and (Test-Path -LiteralPath $backupPath)) {
            try {
                Copy-Item -LiteralPath $backupPath -Destination $targetPath -Force
                [void]$details.Add("Yedek geri yuklendi.")
            }
            catch {
                [void]$details.Add("Yedek geri yuklenemedi: $($_.Exception.Message)")
            }
        }

        Write-UpdateApplyDiagnostic "failed" $message @($details.ToArray()) $downloadPath $targetPath $backupPath ([string]$manifest.version) $expectedHash $expectedSizeValue
        throw
    }
}

function Start-SelfUpdate($manifest, $manifestUrl) {
    $fileInfo = Get-UpdateArtifactFileInfo $manifest

    if ($null -eq $fileInfo) {
        throw (Get-MissingUpdateArtifactMessage $manifest)
    }

    $updatesDir = Join-Path $StoreDir "updates"
    $backupDir = Join-Path $StoreDir "backups"

    New-Item -ItemType Directory -Path $updatesDir -Force | Out-Null
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    $versionSafe = ($manifest.version -replace '[^A-Za-z0-9._-]', '-')
    $downloadPath = Join-Path $updatesDir "github-pages-manager-$versionSafe$(Get-UpdateFileExtension)"
    $updaterPath = Join-Path $updatesDir "apply-update.ps1"
    $supervisorPath = Join-Path $updatesDir "apply-update.cmd"
    $diagWriterPath = Join-Path $updatesDir "apply-update-diag.ps1"
    $verifyPath = Join-Path $updatesDir "apply-update-verify.ps1"
    $manualRepairPath = Join-Path $updatesDir "manual-repair.cmd"
    $backupPath = Join-Path $backupDir "github-pages-manager-$AppVersion-$(Get-Date -Format 'yyyyMMdd-HHmmss')$(Get-UpdateFileExtension)"

    Write-Host ""
    Write-StatusInfo "Yayindaki surum indiriliyor..."

    $candidates = @(Get-UpdateDownloadCandidates $manifest $manifestUrl)

    if ($candidates.Count -eq 0) {
        throw "Manifest icinde denenebilecek indirme kaynagi yok."
    }

    $verified = $false
    $failures = @()
    $attempt = 0
    $expectedHash = ""
    $expectedSize = ""
    $expectedSizeValue = 0

    if (![string]::IsNullOrWhiteSpace($fileInfo.sha256)) {
        $expectedHash = $fileInfo.sha256.ToLowerInvariant()
    }

    if ($null -ne $fileInfo.sizeBytes -and [int64]$fileInfo.sizeBytes -gt 0) {
        $expectedSizeValue = [int64]$fileInfo.sizeBytes
        $expectedSize = [string]$expectedSizeValue
    }

    foreach ($candidate in $candidates) {
        $attempt++
        Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue

        Write-StatusInfo "Kaynak deneniyor ($attempt/$($candidates.Count)): $($candidate.Label)"

        try {
            if ($candidate.Kind -eq "url") {
                Save-UrlToFile $candidate.Source $downloadPath
            }
            elseif ($candidate.Kind -eq "file") {
                if (!(Test-Path $candidate.Source)) {
                    throw "Yerel dosya bulunamadi."
                }

                Copy-Item -LiteralPath $candidate.Source -Destination $downloadPath -Force
            }
            else {
                throw "Bilinmeyen kaynak tipi: $($candidate.Kind)"
            }

            $check = Test-UpdateFileIntegrity $downloadPath $fileInfo

            if ($check.Valid) {
                $verified = $true
                break
            }

            $badPath = Join-Path $updatesDir ("github-pages-manager-$versionSafe-attempt$attempt.bad")
            Copy-Item -LiteralPath $downloadPath -Destination $badPath -Force

            $failures += @(
                "Kaynak: $($candidate.Source)",
                "  Etiket: $($candidate.Label)",
                "  Beklenen SHA256: $expectedHash",
                "  Gelen SHA256: $($check.Hash)",
                "  Beklenen boyut: $expectedSize",
                "  Gelen boyut: $($check.Size)",
                "  Saklanan hatali dosya: $badPath"
            ) -join [Environment]::NewLine
        }
        catch {
            $failures += @(
                "Kaynak: $($candidate.Source)",
                "  Etiket: $($candidate.Label)",
                "  Hata: $($_.Exception.Message)"
            ) -join [Environment]::NewLine
        }
    }

    if (!$verified) {
        Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
        $detail = ($failures -join ([Environment]::NewLine + [Environment]::NewLine))
        throw "Indirilen dosyanin SHA256/boyut dogrulamasi basarisiz.`n`n$detail"
    }

    $targetPath = $env:BAT_FILE
    $cmdPid = Get-ParentProcessId $PID
    $writeProbe = Test-UpdateTargetWritable $targetPath

    if ($null -eq $writeProbe -or !$writeProbe.Success) {
        throw "Guncelleme hedef klasorune yazilamiyor: $($writeProbe.Message)"
    }

    Write-UpdateApplyDiagnostic "downloaded" "Guncelleme indirildi ve hedef yazma testi basarili." @("candidate-count=$($candidates.Count)") $downloadPath $targetPath $backupPath ([string]$manifest.version) $expectedHash $expectedSizeValue

    if (Test-GpmLinux) {
        Invoke-LinuxSelfUpdate $downloadPath $targetPath $backupPath $manifest $fileInfo $expectedHash $expectedSizeValue
        exit 0
    }

    function ConvertTo-CmdLiteral($value) {
        return ([string]$value).Replace('"', '').Replace('%', '%%')
    }

    $cmdSource = ConvertTo-CmdLiteral $downloadPath
    $cmdTarget = ConvertTo-CmdLiteral $targetPath
    $cmdBackup = ConvertTo-CmdLiteral $backupPath
    $cmdExpectedHash = ConvertTo-CmdLiteral $expectedHash
    $cmdExpectedSize = ConvertTo-CmdLiteral ([string]$expectedSizeValue)

    $updaterScript = @'
param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Target,
    [Parameter(Mandatory=$true)][string]$Backup,
    [Parameter(Mandatory=$true)][int]$ParentPid,
    [Parameter(Mandatory=$true)][int]$CmdPid,
    [Parameter(Mandatory=$false)][string]$ExpectedHash = "",
    [Parameter(Mandatory=$false)][int64]$ExpectedSize = 0,
    [Parameter(Mandatory=$false)][string]$TargetVersion = "",
    [Parameter(Mandatory=$true)][string]$DiagPath
)

$ErrorActionPreference = "Stop"
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:BackupCreated = $false

function Get-UpdateFileSnapshot($path) {
    $snapshot = [ordered]@{
        Path = [string]$path
        Exists = $false
        Size = 0
        Sha256 = ""
        LastWriteUtc = ""
        Error = ""
    }

    try {
        if (![string]::IsNullOrWhiteSpace([string]$path) -and (Test-Path -LiteralPath $path)) {
            $item = Get-Item -LiteralPath $path -Force
            $snapshot.Exists = $true
            $snapshot.Size = [int64]$item.Length
            $snapshot.LastWriteUtc = $item.LastWriteTimeUtc.ToString("o")

            if (!$item.PSIsContainer) {
                $snapshot.Sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
    }
    catch {
        $snapshot.Error = $_.Exception.Message
    }

    return [PSCustomObject]$snapshot
}

function Write-UpdateDiagnostic($status, $message, $details = @()) {
    try {
        $diagDir = Split-Path -Parent $DiagPath

        if (![string]::IsNullOrWhiteSpace($diagDir) -and !(Test-Path -LiteralPath $diagDir)) {
            New-Item -ItemType Directory -Path $diagDir -Force | Out-Null
        }

        $diag = [PSCustomObject]@{
            SchemaVersion = 1
            Status = [string]$status
            Message = [string]$message
            Details = @($details)
            Source = [string]$Source
            Target = [string]$Target
            Backup = [string]$Backup
            ManualRepair = (Join-Path (Split-Path -Parent $DiagPath) "manual-repair.cmd")
            TargetVersion = [string]$TargetVersion
            ExpectedHash = [string]$ExpectedHash
            ExpectedSize = [int64]$ExpectedSize
            ParentPid = [int]$ParentPid
            CmdPid = [int]$CmdPid
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            SourceInfo = Get-UpdateFileSnapshot $Source
            TargetInfo = Get-UpdateFileSnapshot $Target
            BackupInfo = Get-UpdateFileSnapshot $Backup
            UpdatedAt = (Get-Date).ToUniversalTime().ToString("o")
        }

        [System.IO.File]::WriteAllText($DiagPath, ($diag | ConvertTo-Json -Depth 8), $script:Utf8NoBom)
    }
    catch {
    }
}

function Wait-ForProcessExit($processId, $timeoutSeconds) {
    if ([int]$processId -le 0) {
        return
    }

    $deadline = (Get-Date).AddSeconds($timeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        try {
            Get-Process -Id $processId -ErrorAction Stop | Out-Null
        }
        catch {
            return
        }

        Start-Sleep -Milliseconds 250
    }
}

function Invoke-WithRetry($label, [scriptblock]$action, $attempts = 32, $delayMs = 1000) {
    $lastError = ""

    for ($i = 1; $i -le $attempts; $i++) {
        try {
            & $action
            return
        }
        catch {
            $lastError = $_.Exception.Message
            Write-UpdateDiagnostic "copy-retry" "$label denemesi basarisiz." @("attempt=$i/$attempts", "error=$lastError")

            if ($i -lt $attempts) {
                Start-Sleep -Milliseconds $delayMs
            }
        }
    }

    throw "$label basarisiz: $lastError"
}

function Clear-ReadonlyFlag($path) {
    try {
        if (Test-Path -LiteralPath $path) {
            $item = Get-Item -LiteralPath $path -Force
            $item.IsReadOnly = $false
        }
    }
    catch {
    }
}

function Assert-TargetIntegrity {
    if (!(Test-Path -LiteralPath $Target)) {
        throw "Hedef BAT dosyasi kopyalama sonrasi bulunamadi."
    }

    if (![string]::IsNullOrWhiteSpace($ExpectedHash)) {
        $actualHash = (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash.ToLowerInvariant()

        if ($actualHash -ne $ExpectedHash.ToLowerInvariant()) {
            throw "Kopyalama sonrasi SHA256 uyusmuyor. Beklenen: $ExpectedHash Gelen: $actualHash"
        }
    }

    if ([int64]$ExpectedSize -gt 0) {
        $actualSize = (Get-Item -LiteralPath $Target).Length

        if ([int64]$actualSize -ne [int64]$ExpectedSize) {
            throw "Kopyalama sonrasi boyut uyusmuyor. Beklenen: $ExpectedSize Gelen: $actualSize"
        }
    }
}

function Start-UpdatedTarget {
    if ($env:GPM_UPDATE_TEST_NO_RESTART -eq "1") {
        return
    }

    $targetDir = Split-Path -Parent $Target
    $errors = New-Object System.Collections.ArrayList
    $escapedTarget = $Target.Replace('"', '""')
    $cmdLine = '/d /c start "" "' + $escapedTarget + '"'

    try {
        Start-Process -FilePath "cmd.exe" -WorkingDirectory $targetDir -ArgumentList $cmdLine | Out-Null
        return
    }
    catch {
        [void]$errors.Add("cmd start: $($_.Exception.Message)")
    }

    try {
        Start-Process -FilePath "explorer.exe" -ArgumentList "`"$Target`"" | Out-Null
        return
    }
    catch {
        [void]$errors.Add("explorer: $($_.Exception.Message)")
    }

    try {
        Invoke-Item -LiteralPath $Target
        return
    }
    catch {
        [void]$errors.Add("invoke-item: $($_.Exception.Message)")
    }

    throw "Guncellenen BAT yeniden acilamadi. $($errors -join ' | ')"
}

Write-UpdateDiagnostic "started" "Guncelleme uygulanmaya basladi."

try {
    Wait-ForProcessExit $ParentPid 45
    Wait-ForProcessExit $CmdPid 45
    Start-Sleep -Milliseconds 750

    if (!(Test-Path -LiteralPath $Source)) {
        throw "Indirilen guncelleme dosyasi bulunamadi: $Source"
    }

    $backupDir = Split-Path -Parent $Backup

    if (!(Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    if (Test-Path -LiteralPath $Target) {
        Write-UpdateDiagnostic "backup" "Mevcut BAT yedekleniyor."
        Clear-ReadonlyFlag $Target
        Invoke-WithRetry "Yedek alma" {
            Copy-Item -LiteralPath $Target -Destination $Backup -Force
            $script:BackupCreated = $true
        }
    }

    Write-UpdateDiagnostic "copying" "Yeni BAT hedef dosyaya kopyalaniyor."
    Invoke-WithRetry "Guncel BAT kopyalama" {
        Clear-ReadonlyFlag $Target
        Copy-Item -LiteralPath $Source -Destination $Target -Force
    }

    Write-UpdateDiagnostic "verifying" "Yeni BAT hedef dosyada dogrulaniyor."
    Invoke-WithRetry "Guncel BAT dogrulama" {
        Assert-TargetIntegrity
    } 4 500

    Remove-Item -LiteralPath $Source -Force -ErrorAction SilentlyContinue
    Write-UpdateDiagnostic "ok" "Guncelleme uygulandi ve hedef BAT dogrulandi."

    try {
        Start-UpdatedTarget
    }
    catch {
        Write-UpdateDiagnostic "restart-failed" "Guncelleme uygulandi fakat BAT otomatik yeniden acilamadi. Dosyayi elle acabilirsin." @("restart failed: $($_.Exception.Message)")
    }

    exit 0
}
catch {
    $message = $_.Exception.Message
    $details = New-Object System.Collections.ArrayList

    if ($script:BackupCreated -and (Test-Path -LiteralPath $Backup)) {
        try {
            Copy-Item -LiteralPath $Backup -Destination $Target -Force
            [void]$details.Add("Yedek geri yuklendi.")
        }
        catch {
            [void]$details.Add("Yedek geri yuklenemedi: $($_.Exception.Message)")
        }
    }

    Write-UpdateDiagnostic "failed" $message @($details.ToArray())
    exit 1
}
'@

    $diagWriterScript = @'
param(
    [Parameter(Mandatory=$true)][string]$Status,
    [Parameter(Mandatory=$false)][string]$Message = "",
    [Parameter(Mandatory=$false)][string[]]$Details = @()
)

$ErrorActionPreference = "Stop"
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

try {
    $diagPath = $env:GPM_UPDATE_DIAGPATH

    if ([string]::IsNullOrWhiteSpace($diagPath)) {
        exit 0
    }

    $diagDir = Split-Path -Parent $diagPath

    if (![string]::IsNullOrWhiteSpace($diagDir) -and !(Test-Path -LiteralPath $diagDir)) {
        New-Item -ItemType Directory -Path $diagDir -Force | Out-Null
    }

    $expectedSize = 0L
    [void][int64]::TryParse([string]$env:GPM_UPDATE_EXPECTED_SIZE, [ref]$expectedSize)

    $diag = [PSCustomObject]@{
        SchemaVersion = 1
        Status = [string]$Status
        Message = [string]$Message
        Details = @($Details)
        Source = [string]$env:GPM_UPDATE_SOURCE
        Target = [string]$env:GPM_UPDATE_TARGET
        Backup = [string]$env:GPM_UPDATE_BACKUP
        ManualRepair = (Join-Path (Split-Path -Parent $diagPath) "manual-repair.cmd")
        TargetVersion = [string]$env:GPM_UPDATE_TARGET_VERSION
        ExpectedHash = [string]$env:GPM_UPDATE_EXPECTED_HASH
        ExpectedSize = [int64]$expectedSize
        UpdatedAt = (Get-Date).ToUniversalTime().ToString("o")
    }

    [System.IO.File]::WriteAllText($diagPath, ($diag | ConvertTo-Json -Depth 8), $script:Utf8NoBom)
}
catch {
    exit 0
}
'@

    $verifyScript = @'
$ErrorActionPreference = "Stop"

try {
    $target = $env:GPM_UPDATE_TARGET

    if ([string]::IsNullOrWhiteSpace($target) -or !(Test-Path -LiteralPath $target)) {
        throw "Hedef BAT bulunamadi: $target"
    }

    $expectedHash = [string]$env:GPM_UPDATE_EXPECTED_HASH

    if (![string]::IsNullOrWhiteSpace($expectedHash)) {
        $actualHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()

        if ($actualHash -ne $expectedHash.ToLowerInvariant()) {
            throw "SHA256 uyusmuyor. Beklenen: $expectedHash Gelen: $actualHash"
        }
    }

    $expectedSize = 0L
    [void][int64]::TryParse([string]$env:GPM_UPDATE_EXPECTED_SIZE, [ref]$expectedSize)

    if ($expectedSize -gt 0) {
        $actualSize = (Get-Item -LiteralPath $target).Length

        if ([int64]$actualSize -ne [int64]$expectedSize) {
            throw "Boyut uyusmuyor. Beklenen: $expectedSize Gelen: $actualSize"
        }
    }

    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
'@

    $supervisorScript = @'
@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "UPDATER=%GPM_UPDATE_UPDATER%"
set "DIAG_WRITER=%GPM_UPDATE_DIAG_WRITER%"
set "VERIFY_SCRIPT=%GPM_UPDATE_VERIFY%"
set "SOURCE=%GPM_UPDATE_SOURCE%"
set "TARGET=%GPM_UPDATE_TARGET%"
set "BACKUP=%GPM_UPDATE_BACKUP%"

call :writeDiag started "Supervisor basladi."

powershell -NoProfile -ExecutionPolicy Bypass -File "%UPDATER%" -Source "%SOURCE%" -Target "%TARGET%" -Backup "%BACKUP%" -ParentPid "%GPM_UPDATE_PARENT_PID%" -CmdPid "%GPM_UPDATE_CMD_PID%" -ExpectedHash "%GPM_UPDATE_EXPECTED_HASH%" -ExpectedSize "%GPM_UPDATE_EXPECTED_SIZE%" -TargetVersion "%GPM_UPDATE_TARGET_VERSION%" -DiagPath "%GPM_UPDATE_DIAGPATH%"
set "PRIMARY_CODE=%ERRORLEVEL%"

if "%PRIMARY_CODE%"=="0" exit /b 0

call :writeDiag failed "PowerShell updater basarisiz oldu. CMD fallback deneniyor. Exit code: %PRIMARY_CODE%"
call :fallbackCopy
set "FALLBACK_CODE=%ERRORLEVEL%"

if "%FALLBACK_CODE%"=="0" (
    call :writeDiag ok "CMD fallback ile guncelleme uygulandi ve hedef BAT dogrulandi."
    call :restartTarget
    exit /b 0
)

call :writeDiag failed "PowerShell updater ve CMD fallback basarisiz oldu. Primary exit code: %PRIMARY_CODE%; fallback exit code: %FALLBACK_CODE%"
call :restartTarget
exit /b 1

:writeDiag
if not exist "%DIAG_WRITER%" exit /b 0
powershell -NoProfile -ExecutionPolicy Bypass -File "%DIAG_WRITER%" -Status "%~1" -Message "%~2" >nul 2>&1
exit /b 0

:fallbackCopy
if "%SOURCE%"=="" exit /b 20
if "%TARGET%"=="" exit /b 21
if not exist "%SOURCE%" exit /b 22

for %%I in ("%BACKUP%") do if not exist "%%~dpI" mkdir "%%~dpI" >nul 2>&1
if exist "%TARGET%" copy /y "%TARGET%" "%BACKUP%" >nul 2>&1

set /a ATTEMPT=0

:copyLoop
set /a ATTEMPT+=1
attrib -R "%TARGET%" >nul 2>&1
copy /y "%SOURCE%" "%TARGET%" >nul 2>&1
if not errorlevel 1 goto verifyTarget

if %ATTEMPT% GEQ 32 (
    call :restoreBackup
    exit /b 23
)

timeout /t 1 /nobreak >nul 2>&1
goto copyLoop

:verifyTarget
powershell -NoProfile -ExecutionPolicy Bypass -File "%VERIFY_SCRIPT%" >nul 2>&1
if errorlevel 1 (
    call :restoreBackup
    exit /b 24
)

del "%SOURCE%" >nul 2>&1
exit /b 0

:restoreBackup
if exist "%BACKUP%" copy /y "%BACKUP%" "%TARGET%" >nul 2>&1
exit /b 0

:restartTarget
if "%GPM_UPDATE_TEST_NO_RESTART%"=="1" exit /b 0
if "%TARGET%"=="" exit /b 0
if not exist "%TARGET%" exit /b 0
start "" "%TARGET%" >nul 2>&1
exit /b 0
'@

    $manualRepairScript = @"
@echo off
chcp 65001 >nul
setlocal EnableExtensions DisableDelayedExpansion

set "SOURCE=$cmdSource"
set "TARGET=$cmdTarget"
set "BACKUP=$cmdBackup"
set "GPM_REPAIR_EXPECTED_HASH=$cmdExpectedHash"
set "GPM_REPAIR_EXPECTED_SIZE=$cmdExpectedSize"
set "GPM_REPAIR_TARGET=$cmdTarget"

echo GitHub Pages Manager manual update repair
echo.
echo Source: %SOURCE%
echo Target: %TARGET%
echo.

if "%SOURCE%"=="" (
  echo Source bos.
  pause
  exit /b 20
)

if "%TARGET%"=="" (
  echo Target bos.
  pause
  exit /b 21
)

if not exist "%SOURCE%" (
  echo Indirilen guncelleme dosyasi bulunamadi.
  pause
  exit /b 22
)

for %%I in ("%BACKUP%") do if not exist "%%~dpI" mkdir "%%~dpI" >nul 2>&1
if exist "%TARGET%" copy /y "%TARGET%" "%BACKUP%" >nul 2>&1

attrib -R "%TARGET%" >nul 2>&1
copy /y "%SOURCE%" "%TARGET%" >nul 2>&1
if errorlevel 1 (
  echo Yeni BAT hedef dosyaya kopyalanamadi.
  echo Antivirus, OneDrive veya dosya kilidi engelliyor olabilir.
  pause
  exit /b 23
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "`$target=`$env:GPM_REPAIR_TARGET; if(!(Test-Path -LiteralPath `$target)){throw 'Hedef BAT bulunamadi.'}; if(`$env:GPM_REPAIR_EXPECTED_HASH){`$actual=(Get-FileHash -LiteralPath `$target -Algorithm SHA256).Hash.ToLowerInvariant(); if(`$actual -ne ([string]`$env:GPM_REPAIR_EXPECTED_HASH).ToLowerInvariant()){throw ('SHA256 uyusmuyor: ' + `$actual)}}; if([int64]([string]`$env:GPM_REPAIR_EXPECTED_SIZE) -gt 0){`$size=(Get-Item -LiteralPath `$target).Length; if([int64]`$size -ne [int64]([string]`$env:GPM_REPAIR_EXPECTED_SIZE)){throw ('Boyut uyusmuyor: ' + `$size)}}"
if errorlevel 1 (
  echo Hedef BAT dogrulanamadi.
  pause
  exit /b 24
)

echo.
echo Guncelleme elle uygulandi. BAT yeniden aciliyor.
start "" "%TARGET%"
exit /b 0
"@

    [System.IO.File]::WriteAllText($updaterPath, $updaterScript, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($diagWriterPath, $diagWriterScript, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($verifyPath, $verifyScript, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($supervisorPath, $supervisorScript, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($manualRepairPath, $manualRepairScript, [System.Text.UTF8Encoding]::new($false))

    Write-StatusOk "Guncelleme indirildi ve dogrulandi."
    Write-StatusInfo "Uygulama guncellenip yeniden baslatilacak..."

    $env:GPM_UPDATE_UPDATER = $updaterPath
    $env:GPM_UPDATE_DIAG_WRITER = $diagWriterPath
    $env:GPM_UPDATE_VERIFY = $verifyPath
    $env:GPM_UPDATE_SOURCE = $downloadPath
    $env:GPM_UPDATE_TARGET = $targetPath
    $env:GPM_UPDATE_BACKUP = $backupPath
    $env:GPM_UPDATE_PARENT_PID = [string]$PID
    $env:GPM_UPDATE_CMD_PID = [string]$cmdPid
    $env:GPM_UPDATE_EXPECTED_HASH = $expectedHash
    $env:GPM_UPDATE_EXPECTED_SIZE = [string]$expectedSizeValue
    $env:GPM_UPDATE_TARGET_VERSION = [string]$manifest.version
    $env:GPM_UPDATE_DIAGPATH = $UpdateApplyDiagPath

    Write-UpdateApplyDiagnostic "launching" "Guncelleme supervisor baslatiliyor." @("primary=powershell", "fallback=cmd", "manual-repair=$manualRepairPath") $downloadPath $targetPath $backupPath ([string]$manifest.version) $expectedHash $expectedSizeValue

    try {
        $launchCommand = '/d /c "' + $supervisorPath.Replace('"', '""') + '"'
        Start-Process -FilePath "cmd.exe" -WindowStyle Hidden -WorkingDirectory $updatesDir -ArgumentList $launchCommand | Out-Null
    }
    catch {
        Write-UpdateApplyDiagnostic "failed" "Guncelleme supervisor baslatilamadi: $($_.Exception.Message)" @() $downloadPath $targetPath $backupPath ([string]$manifest.version) $expectedHash $expectedSizeValue
        throw
    }

    exit 0
}

function Show-UpdatePrompt($manifest, $manifestSourceUrl, $sourceNotice = $null) {
    if ($null -eq $manifest) {
        return
    }

    $localManifest = Get-LocalAdminManifest

    if ([string]::IsNullOrWhiteSpace($manifest.version) -and $null -ne $localManifest) {
        $manifest = $localManifest
    }

    $manifestNotes = @(Get-ManifestNotes $manifest)

    if ($manifestNotes.Count -eq 0 -and $null -ne $localManifest -and $localManifest.version -eq $manifest.version) {
        $manifest = $localManifest
        $manifestNotes = @(Get-ManifestNotes $manifest)
    }

    if (![string]::IsNullOrWhiteSpace($manifest.appId) -and $manifest.appId -ne "github-pages-manager") {
        return
    }

    if (!(Test-IsDifferentVersion $manifest.version $AppVersion)) {
        return
    }

    Header
    Write-BoxMessage "version switch" (Get-UpdatePromptTitle $manifest.version $AppVersion) "Cyan"
    if (![string]::IsNullOrWhiteSpace($sourceNotice)) {
        Write-StatusWarn $sourceNotice
    }

    $lastUpdateProblem = Get-LastProblemUpdateDiagnostic $manifest.version

    if ($null -ne $lastUpdateProblem) {
        if ([string]$lastUpdateProblem.Status -eq "stale-after-ok") {
            Write-StatusWarn "Son guncellemeden sonra bu BAT hala eski surumle acildi."
        }
        else {
            Write-StatusWarn "Son guncelleme uygulanamadi veya tamamlanmadan kesildi."
        }

        if (![string]::IsNullOrWhiteSpace([string]$lastUpdateProblem.Message)) {
            Write-ThemeValue "son hata" ([string]$lastUpdateProblem.Message)
        }

        $lastDetails = @($lastUpdateProblem.Details)

        if ($lastDetails.Count -gt 0 -and ![string]::IsNullOrWhiteSpace([string]$lastDetails[0])) {
            Write-ThemeValue "detay" ([string]$lastDetails[0])
        }

        if (![string]::IsNullOrWhiteSpace([string]$lastUpdateProblem.ManualRepair)) {
            Write-ThemeValue "manuel onarim" ([string]$lastUpdateProblem.ManualRepair)
        }

        if (![string]::IsNullOrWhiteSpace([string]$lastUpdateProblem.UpdatedAt)) {
            Write-ThemeValue "son deneme" ([string]$lastUpdateProblem.UpdatedAt)
        }
    }

    Write-ThemeValue "mevcut" $AppVersion
    Write-ThemeValue "yayindaki" $manifest.version
    Write-Host ""
    Write-SectionTitle "release notes"
    Write-ManifestNotes $manifest

    Write-Host ""
    Write-MenuFrame "update" {
        Write-MenuItem "1" "Guncelle"
        Write-MenuItem "2" "Simdilik gec"
    }
    Write-Host ""
    Write-KeyPrompt "secim"

    $choice = Read-KeyChoice @("1", "2")

    if ($choice -eq "2") {
        return
    }

    try {
        Start-SelfUpdate $manifest $manifestSourceUrl
    }
    catch {
        Show-Error $_.Exception.Message
        Pause-Back
    }
}

function Check-ForUpdates {
    $manifestUrl = Get-EffectiveUpdateManifestUrl

    if ([string]::IsNullOrWhiteSpace($manifestUrl)) {
        return
    }

    $cache = Get-UpdateCheckCache

    try {
        $manifestResult = Get-UpdateManifest $manifestUrl
        Save-UpdateCheckCache $manifestUrl $manifestResult.SourceUrl $manifestResult.Manifest
        Show-UpdatePrompt $manifestResult.Manifest $manifestResult.SourceUrl
        return
    }
    catch {
        if ($null -ne $cache -and $null -ne $cache.Manifest) {
            Show-UpdatePrompt $cache.Manifest $cache.SourceUrl "GitHub okunamadi, son bilinen manifest kullaniliyor."
            return
        }

        $manifest = Get-LocalAdminManifest

        if ($null -ne $manifest) {
            Show-UpdatePrompt $manifest $manifestUrl "GitHub okunamadi, yerel admin manifesti kullaniliyor."
        }
    }
}

function Show-UpdateNotes {
    Header

    $manifestUrl = Get-EffectiveUpdateManifestUrl

    if ([string]::IsNullOrWhiteSpace($manifestUrl)) {
        Write-BoxMessage "update notes" "Guncelleme kaynagi henuz ayarlanmamis. Admin BAT ile ilk yayin yapildiktan sonra bu bolum aktif olur." "Yellow"
        Pause-Back
        return
    }

    try {
        $manifestResult = Get-UpdateManifest $manifestUrl
        $manifest = $manifestResult.Manifest
    }
    catch {
        $manifest = Get-LocalAdminManifest

        if ($null -eq $manifest) {
            Write-BoxMessage "update notes" "Guncelleme notlari su an okunamadi. Biraz sonra tekrar deneyebilirsin." "Yellow"
            Pause-Back
            return
        }

        Write-BoxMessage "offline cache" "GitHub'a ulasilamadi. Yerel son kopya gosteriliyor." "Yellow"
    }

    $localManifest = Get-LocalAdminManifest

    if ([string]::IsNullOrWhiteSpace($manifest.version) -and $null -ne $localManifest) {
        $manifest = $localManifest
    }

    $notes = @(Get-ManifestNotes $manifest)

    if ($notes.Count -eq 0 -and $null -ne $localManifest -and $localManifest.version -eq $manifest.version) {
        $manifest = $localManifest
        $notes = @(Get-ManifestNotes $manifest)
    }

    Write-ThemeValue "mevcut" $AppVersion
    Write-ThemeValue "yayindaki" $manifest.version
    Write-Host ""
    Write-SectionTitle "release notes"
    Write-ManifestNotes $manifest

    Pause-Back
}

function Copy-DeviceLoginCode-IfPresent($text) {
    if ([string]::IsNullOrWhiteSpace($text)) {
        return
    }

    if ($text -match "one-time code:\s*([A-Z0-9]+-[A-Z0-9]+)") {
        $code = $matches[1]

        try {
            Set-Clipboard -Value $code
            Write-StatusOk "GitHub giris kodu panoya kopyalandi: $code"
        }
        catch {
            Write-StatusWarn "GitHub giris kodu panoya kopyalanamadi."
            Write-ThemeValue "kod" $code
        }
    }
}

function Open-DeviceLoginUrl-IfPresent($text) {
    if ([string]::IsNullOrWhiteSpace($text)) {
        return
    }

    if ($text -match "https://github\.com/login/device\b") {
        $url = $matches[0]

        if ($script:LastOpenedDeviceLoginUrl -ne $url) {
            $script:LastOpenedDeviceLoginUrl = $url
            Write-StatusInfo "GitHub device login sayfasi tarayicida aciliyor..."

            try {
                Start-Process $url
            }
            catch {
                Write-StatusWarn "Tarayici otomatik acilamadi. Linki elle ac:"
                Write-ThemeValue "url" $url
            }
        }
    }
}

function Invoke-GhInteractive($argsList) {
    $result = Invoke-GhInteractiveResult $argsList
    return $result.Code
}

function Invoke-GhSilent($argsList) {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    $output = & gh @argsList 2>&1

    $code = $LASTEXITCODE
    $ErrorActionPreference = $oldPreference

    return [PSCustomObject]@{
        Code = $code
        Output = ($output -join [Environment]::NewLine)
    }
}

function Invoke-GhInteractiveResult($argsList) {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $captured = @()
    $script:LastOpenedDeviceLoginUrl = $null

    & gh @argsList 2>&1 | ForEach-Object {
        $line = $_.ToString()
        $captured += $line
        Write-Host $line
        Copy-DeviceLoginCode-IfPresent $line
        Open-DeviceLoginUrl-IfPresent $line
    }

    $code = $LASTEXITCODE
    $ErrorActionPreference = $oldPreference

    return [PSCustomObject]@{
        Code = $code
        Output = ($captured -join [Environment]::NewLine)
    }
}

function Invoke-GhInteractiveWithRetry($argsList, $label, $maxAttempts, $delaySeconds) {
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        if ($attempt -gt 1) {
            Write-Host ""
            Write-StatusInfo "$label tekrar deneniyor ($attempt/$maxAttempts)..."
        }

        $result = Invoke-GhInteractiveResult $argsList

        if ($result.Code -eq 0) {
            return $result
        }

        if ($attempt -lt $maxAttempts) {
            $waitSeconds = $delaySeconds * $attempt
            Write-Host ""
            Write-StatusWarn "$label basarisiz oldu. $waitSeconds saniye sonra tekrar denenecek..."
            Start-Sleep -Seconds $waitSeconds
        }
    }

    return $result
}

function Get-ActiveGitHubUser {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    $user = (& gh api user --jq ".login" 2>$null)

    $code = $LASTEXITCODE
    $ErrorActionPreference = $oldPreference

    if ($code -ne 0 -or [string]::IsNullOrWhiteSpace($user)) {
        return $null
    }

    return $user.Trim()
}

function Get-GhStoredUsers {
    $result = Invoke-GhSilent @("auth", "status", "--hostname", "github.com")

    if ($result.Code -ne 0 -or [string]::IsNullOrWhiteSpace($result.Output)) {
        return @()
    }

    $users = @()
    $userPattern = "([A-Za-z0-9][A-Za-z0-9-]{0,38})"

    foreach ($line in ($result.Output -split "`r?`n")) {
        $trimmed = $line.Trim()

        if ($trimmed -match "account\s+$userPattern") {
            $users += $matches[1]
        }
        elseif ($trimmed -match "\bas\s+$userPattern") {
            $users += $matches[1]
        }
        elseif ($trimmed -match "Logged in to github.com account\s+$userPattern") {
            $users += $matches[1]
        }
    }

    return @($users | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Test-GhHasScope($scope) {
    if ([string]::IsNullOrWhiteSpace($scope)) {
        return $false
    }

    $result = Invoke-GhSilent @("auth", "status", "--hostname", "github.com", "--show-token-scopes")

    if ($result.Code -ne 0 -or [string]::IsNullOrWhiteSpace($result.Output)) {
        return $false
    }

    $escapedScope = [regex]::Escape($scope)
    return $result.Output -match "(?i)(^|[^A-Za-z0-9_])$escapedScope([^A-Za-z0-9_]|$)"
}

function Parse-GhCredentialMismatch($output) {
    if ([string]::IsNullOrWhiteSpace($output)) {
        return $null
    }

    $userPattern = "([A-Za-z0-9][A-Za-z0-9-]{0,38})"
    $pattern = "error refreshing credentials for\s+$userPattern,\s+received credentials for\s+$userPattern"

    if ($output -match $pattern) {
        return [PSCustomObject]@{
            OldUser = $matches[1]
            NewUser = $matches[2]
        }
    }

    return $null
}

function Repair-GhAuthForOwner($expectedOwner, $failureOutput) {
    if ([string]::IsNullOrWhiteSpace($expectedOwner)) {
        Write-BoxMessage "auth error" "Beklenen GitHub kullanicisi belirlenemedi." "Red"
        return $false
    }

    $mismatch = Parse-GhCredentialMismatch $failureOutput
    $storedUsers = @(Get-GhStoredUsers)
    $activeUser = Get-ActiveGitHubUser
    $usersToLogout = @()

    if ($null -ne $mismatch) {
        $usersToLogout += $mismatch.OldUser

        if ($mismatch.NewUser -ne $expectedOwner) {
            $usersToLogout += $mismatch.NewUser
        }
    }

    if (![string]::IsNullOrWhiteSpace($activeUser) -and $activeUser -ne $expectedOwner) {
        $usersToLogout += $activeUser
    }

    $usersToLogout = @($usersToLogout | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

    Header
    Write-BoxMessage "auth repair" "GitHub CLI hesap kaydi onariliyor." "Cyan"
    Write-ThemeValue "beklenen" $expectedOwner

    if ($null -ne $mismatch) {
        Write-ThemeValue "eski kayit" $mismatch.OldUser
        Write-ThemeValue "gelen hesap" $mismatch.NewUser
    }

    if ($storedUsers.Count -gt 0) {
        Write-SectionTitle "stored gh accounts"
        foreach ($user in $storedUsers) {
            Write-Host "- $user"
        }
        Write-Host ""
    }

    foreach ($user in $usersToLogout) {
        Write-StatusInfo "Eski / uyumsuz GitHub CLI kaydi temizleniyor: $user"
        Invoke-GhSilent @("auth", "logout", "--hostname", "github.com", "--user", $user, "--yes") | Out-Null
    }

    Write-BoxMessage "github login" "GitHub girisi yenilenecek. Tarayicida repo sahibi hesapla onay ver." "Cyan"
    Write-ThemeValue "hesap" $expectedOwner

    $loginResult = Invoke-GhInteractiveResult @("auth", "login", "--hostname", "github.com", "--web", "--git-protocol", "https", "--scopes", "repo,delete_repo")

    if ($loginResult.Code -ne 0) {
        $existingSwitch = Invoke-GhSilent @("auth", "switch", "--hostname", "github.com", "--user", $expectedOwner)

        if ($existingSwitch.Code -ne 0) {
            Write-BoxMessage "auth error" "GitHub girisi yenilenemedi." "Red"
            Write-Host $loginResult.Output
            return $false
        }
    }

    $activeAfterLogin = Get-ActiveGitHubUser

    if ($activeAfterLogin -ne $expectedOwner) {
        if (![string]::IsNullOrWhiteSpace($activeAfterLogin)) {
            Write-StatusInfo "Yanlis hesapla giris algilandi, kayit temizleniyor: $activeAfterLogin"
            Invoke-GhSilent @("auth", "logout", "--hostname", "github.com", "--user", $activeAfterLogin, "--yes") | Out-Null
        }

        Write-BoxMessage "wrong account" "Yanlis GitHub hesabi ile izin verildi." "Red"
        Write-ThemeValue "beklenen" $expectedOwner
        if ([string]::IsNullOrWhiteSpace($activeAfterLogin)) {
            Write-ThemeValue "algilanan" "Bilinmiyor"
        }
        else {
            Write-ThemeValue "algilanan" $activeAfterLogin
        }
        return $false
    }

    $switchResult = Invoke-GhSilent @("auth", "switch", "--hostname", "github.com", "--user", $expectedOwner)

    if ($switchResult.Code -ne 0) {
        Write-BoxMessage "auth error" "GitHub CLI beklenen hesaba gecemedi." "Red"
        Write-Host $switchResult.Output
        return $false
    }

    if (Test-GhHasScope "delete_repo") {
        Write-StatusOk "delete_repo yetkisi mevcut."
    }
    else {
        Write-StatusInfo "delete_repo yetkisi yenileniyor..."
        $refreshResult = Invoke-GhInteractiveResult @("auth", "refresh", "--hostname", "github.com", "-s", "delete_repo")

        if ($refreshResult.Code -ne 0) {
            Write-BoxMessage "auth error" "delete_repo yetkisi otomatik yenilenemedi." "Red"
            Write-Host $refreshResult.Output
            return $false
        }
    }

    $setupGit = Invoke-GhSilent @("auth", "setup-git")

    if ($setupGit.Code -ne 0) {
        Write-StatusWarn "gh auth setup-git tamamlanamadi."
        Write-Host $setupGit.Output
    }

    $script:GhUser = $expectedOwner
    return $true
}

function Ensure-OwnerAuth($owner) {
    $active = Get-ActiveGitHubUser

    if ($active -eq $owner) {
        $script:GhUser = $active
        return $true
    }

    $switchResult = Invoke-GhSilent @("auth", "switch", "--hostname", "github.com", "--user", $owner)

    if ($switchResult.Code -eq 0) {
        $activeAfterSwitch = Get-ActiveGitHubUser

        if ($activeAfterSwitch -eq $owner) {
            $script:GhUser = $activeAfterSwitch
            return $true
        }
    }

    Header

    Write-BoxMessage "account mismatch" "Bu repoyu silmek icin GitHub CLI'da repo sahibi hesapla giris yapman gerekiyor." "Yellow"
    Write-ThemeValue "repo sahibi" $owner
    if ([string]::IsNullOrWhiteSpace($active)) {
        Write-ThemeValue "aktif hesap" "Bilinmiyor / giris yok"
    }
    else {
        Write-ThemeValue "aktif hesap" $active
    }
    Write-Host ""
    Write-MenuFrame "auth" {
        Write-MenuItem "1" "Bu hesapla giris yap / yeniden yetkilendir"
        Write-MenuItem "0" "Geri"
    }
    Write-Host ""
    Write-KeyPrompt "secim"

    $choice = Read-KeyChoice @("1", "0")

    if ($choice -eq "0") {
        return $false
    }

    Header
    Write-BoxMessage "github login" "Tarayici acilacak. Farkli hesapla izin verirsen GitHub yine hata verir." "Cyan"
    Write-ThemeValue "hesap" $owner

    $loginCode = Invoke-GhInteractive @("auth", "login", "--hostname", "github.com", "--web", "--git-protocol", "https", "--scopes", "repo,delete_repo")

    if ($loginCode -ne 0) {
        Write-BoxMessage "auth error" "GitHub girisi tamamlanamadi." "Red"
        Pause-Back
        return $false
    }

    $switchAgain = Invoke-GhSilent @("auth", "switch", "--hostname", "github.com", "--user", $owner)

    if ($switchAgain.Code -ne 0) {
        Write-BoxMessage "auth error" "GitHub CLI hala $owner hesabina gecemiyor. Sebep genelde tarayicida farkli hesapla izin verilmesi." "Red"
        Pause-Back
        return $false
    }

    $activeAfterLogin = Get-ActiveGitHubUser

    if ($activeAfterLogin -ne $owner) {
        Write-BoxMessage "wrong account" "Tarayicida dogru GitHub hesabina gecip tekrar dene." "Red"
        Write-ThemeValue "beklenen" $owner
        Write-ThemeValue "aktif" $activeAfterLogin
        Pause-Back
        return $false
    }

    $script:GhUser = $activeAfterLogin
    return $true
}

function Command-Exists($name) {
    return $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

function Refresh-Path {
    if (Test-GpmLinux) {
        return
    }

    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

function Install-Tool($id, $label) {
    if (Test-GpmLinux) {
        if (!(Command-Exists "sudo")) {
            throw "sudo bulunamadi. $label otomatik kurulamiyor. Once $label aracini manuel kurman gerekiyor."
        }

        $packageName = switch ($id) {
            "Git.Git" { "git" }
            "GitHub.cli" { "gh" }
            default { $label.ToLowerInvariant() }
        }

        Write-StatusInfo "$label bulunamadi. apt ile kuruluyor..."
        & sudo apt-get update
        & sudo apt-get install -y $packageName
        return
    }

    if (!(Command-Exists "winget")) {
        throw "winget bulunamadi. $label otomatik kurulamiyor. Once winget/App Installer kurulu olmali."
    }

    Write-StatusInfo "$label bulunamadi. Winget ile kuruluyor..."
    winget install --id $id -e --accept-source-agreements --accept-package-agreements

    Refresh-Path
}

function Ensure-Tools {
    if (!(Command-Exists "git")) {
        Install-Tool "Git.Git" "Git"
    }

    if (!(Command-Exists "git")) {
        throw "Git kuruldu ama bu oturumda gorunmuyor. Terminali veya bilgisayari yeniden acip tekrar dene."
    }

    if (!(Command-Exists "gh")) {
        Install-Tool "GitHub.cli" "GitHub CLI"
    }

    if (!(Command-Exists "gh")) {
        throw "GitHub CLI kuruldu ama bu oturumda gorunmuyor. Terminali veya bilgisayari yeniden acip tekrar dene."
    }
}

function Ensure-GitHubAuth {
    $status = Invoke-GhSilent @("auth", "status")

    if ($status.Code -ne 0) {
        Write-BoxMessage "github login" "GitHub girisi yok. Tarayici acilacak; GitHub izin ekraninda onay ver." "Cyan"

        $loginCode = Invoke-GhInteractive @("auth", "login", "--hostname", "github.com", "--web", "--git-protocol", "https", "--scopes", "repo")

        if ($loginCode -ne 0) {
            throw "GitHub girisi tamamlanamadi."
        }
    }

    $script:GhUser = Get-ActiveGitHubUser

    if ([string]::IsNullOrWhiteSpace($script:GhUser)) {
        throw "GitHub kullanici adi alinamadi."
    }
}

function Ensure-GitHubReady {
    Ensure-Tools
    Ensure-GitHubAuth
}

function Load-Db {
    Ensure-Storage

    try {
        $raw = [System.IO.File]::ReadAllText($DbPath)

        if ([string]::IsNullOrWhiteSpace($raw)) {
            [System.IO.File]::WriteAllText($DbPath, "[]", [System.Text.UTF8Encoding]::new($false))
            return @()
        }

        $data = $raw | ConvertFrom-Json

        if ($null -eq $data) {
            return @()
        }

        return @($data)
    }
    catch {
        Write-StatusWarn "Kayit dosyasi okunamadi. Sifirlaniyor."
        [System.IO.File]::WriteAllText($DbPath, "[]", [System.Text.UTF8Encoding]::new($false))
        return @()
    }
}

function Save-Db($items) {
    Ensure-Storage

    $clean = @()

    foreach ($item in @($items)) {
        if ($null -ne $item) {
            $clean += $item
        }
    }

    if ($clean.Count -eq 0) {
        $json = "[]"
    }
    elseif ($clean.Count -eq 1) {
        $one = $clean[0] | ConvertTo-Json -Depth 20
        $json = "[" + [Environment]::NewLine + $one + [Environment]::NewLine + "]"
    }
    else {
        $json = ConvertTo-Json -InputObject @($clean) -Depth 20
    }

    if ([string]::IsNullOrWhiteSpace($json)) {
        $json = "[]"
    }

    [System.IO.File]::WriteAllText($DbPath, $json, [System.Text.UTF8Encoding]::new($false))

    $check = [System.IO.File]::ReadAllText($DbPath)

    if ([string]::IsNullOrWhiteSpace($check)) {
        throw "Kayit dosyasi yazildi ama bos kaldi: $DbPath"
    }
}

function Upsert-Record($record) {
    if ($null -eq $record) {
        throw "Kaydedilecek repo bilgisi bos geldi."
    }

    if ([string]::IsNullOrWhiteSpace($record.FullName)) {
        throw "Repo FullName bos geldi, kayit yapilamadi."
    }

    $items = @(Load-Db)

    $recordFullName = [string]$record.FullName
    $recordLocalPath = [string]$record.LocalPath

    $items = @($items | Where-Object {
        $existingFullName = [string]$_.FullName
        $existingLocalPath = [string]$_.LocalPath
        $sameFullName = (![string]::IsNullOrWhiteSpace($existingFullName) -and $existingFullName.Equals($recordFullName, [System.StringComparison]::OrdinalIgnoreCase))
        $sameLocalPath = (![string]::IsNullOrWhiteSpace($existingLocalPath) -and ![string]::IsNullOrWhiteSpace($recordLocalPath) -and $existingLocalPath.Equals($recordLocalPath, [System.StringComparison]::OrdinalIgnoreCase))
        !$sameFullName -and !$sameLocalPath
    })

    $items += $record

    Save-Db $items

    Write-Host ""
    Write-StatusOk "Repo kayda yazildi."
    Write-ThemeValue "kayit" $DbPath
}

function Remove-Record($fullName) {
    $items = @(Load-Db)

    $items = @($items | Where-Object {
        !([string]$_.FullName).Equals([string]$fullName, [System.StringComparison]::OrdinalIgnoreCase)
    })

    Save-Db $items
}

function Get-SafeRepoName {
    $folderName = Split-Path -Leaf (Get-Location)
    $safe = $folderName -replace '[^A-Za-z0-9._-]', '-'
    $safe = $safe -replace '-+', '-'
    $safe = $safe.Trim([char[]]"-.")

    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = "demo-site"
    }

    return $safe
}

function Normalize-RepoNameInput($repoName) {
    $safe = ([string]$repoName).Trim()
    $safe = $safe -replace '[^A-Za-z0-9._-]', '-'
    $safe = $safe -replace '-+', '-'
    $safe = $safe.Trim([char[]]"-.")

    if ([string]::IsNullOrWhiteSpace($safe)) {
        return (Get-SafeRepoName)
    }

    return $safe
}

function Split-FullRepoName($fullName) {
    $parts = $fullName.Split("/")

    if ($parts.Count -ne 2) {
        throw "Repo adi hatali: $fullName"
    }

    return [PSCustomObject]@{
        Owner = $parts[0]
        Repo  = $parts[1]
    }
}

function Get-FullPathSafe($path) {
    return [System.IO.Path]::GetFullPath($path)
}

function Assert-PathInside($childPath, $parentPath) {
    $parentFull = Get-FullPathSafe $parentPath
    $childFull = Get-FullPathSafe $childPath
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $parentPrefix = $parentFull.TrimEnd($separator) + $separator

    if ($childFull -ne $parentFull -and !$childFull.StartsWith($parentPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Guvenlik kontrolu basarisiz. Hedef klasor uygulama staging alani disinda: $childFull"
    }
}

function Ensure-WorktreesDir {
    Ensure-Storage

    if (!(Test-Path $WorktreesDir)) {
        New-Item -ItemType Directory -Path $WorktreesDir -Force | Out-Null
    }
}

function Get-RepoWorktreePath($fullName) {
    if ([string]::IsNullOrWhiteSpace($fullName)) {
        throw "Staging klasoru icin repo adi bos geldi."
    }

    Ensure-WorktreesDir

    $safe = $fullName -replace '/', '__'
    $safe = $safe -replace '[^A-Za-z0-9._-]', '-'
    $safe = $safe.Trim([char[]]"-.")

    if ([string]::IsNullOrWhiteSpace($safe)) {
        throw "Staging klasoru icin guvenli repo adi uretilemedi."
    }

    $path = Join-Path $WorktreesDir $safe
    Assert-PathInside $path $WorktreesDir
    return $path
}

function New-RepoRecord($fullName, $localPath) {
    $split = Split-FullRepoName $fullName
    $owner = $split.Owner
    $repoName = $split.Repo
    $siteUrl = "https://$owner.github.io/$repoName/"
    $repoUrl = "https://github.com/$fullName"
    $worktreePath = Get-RepoWorktreePath $fullName

    return [PSCustomObject]@{
        FullName = $fullName
        Owner = $owner
        RepoName = $repoName
        LocalPath = $localPath
        WorktreePath = $worktreePath
        SiteUrl = $siteUrl
        RepoUrl = $repoUrl
        UpdatedAt = (Get-Date).ToString("s")
    }
}

function Get-GitHubCanonicalRepo($fullName) {
    if ([string]::IsNullOrWhiteSpace($fullName)) {
        return $null
    }

    $view = Invoke-GhSilent @("repo", "view", $fullName, "--json", "name,owner,url", "--jq", "{name:.name,owner:.owner.login,url:.url}")

    if ($view.Code -ne 0 -or [string]::IsNullOrWhiteSpace($view.Output)) {
        return $null
    }

    try {
        $data = $view.Output | ConvertFrom-Json

        if ($null -eq $data -or [string]::IsNullOrWhiteSpace($data.owner) -or [string]::IsNullOrWhiteSpace($data.name)) {
            return $null
        }

        return [PSCustomObject]@{
            Owner = [string]$data.owner
            RepoName = [string]$data.name
            FullName = "$($data.owner)/$($data.name)"
            RepoUrl = if (![string]::IsNullOrWhiteSpace($data.url)) { [string]$data.url } else { "https://github.com/$($data.owner)/$($data.name)" }
        }
    }
    catch {
        return $null
    }
}

function Resolve-CanonicalRepoFullName($fullName) {
    $canonical = Get-GitHubCanonicalRepo $fullName

    if ($null -ne $canonical -and ![string]::IsNullOrWhiteSpace($canonical.FullName)) {
        return [string]$canonical.FullName
    }

    return $fullName
}

function Resolve-PublishFullNameForActiveUser($fullName, $fallbackRepoName) {
    if ([string]::IsNullOrWhiteSpace($fullName) -or [string]::IsNullOrWhiteSpace($script:GhUser)) {
        return $fullName
    }

    $split = Split-FullRepoName $fullName

    if ($split.Owner.Equals($script:GhUser, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $fullName
    }

    $repoName = [string]$split.Repo

    if ([string]::IsNullOrWhiteSpace($repoName)) {
        $repoName = Normalize-RepoNameInput $fallbackRepoName
    }

    $updatedFullName = "$script:GhUser/$repoName"

    Write-BoxMessage "account sync" "Kayitli GitHub sahibi aktif hesapla uyusmuyor. Yayin hedefi aktif hesaba aliniyor." "Yellow"
    Write-ThemeValue "kayitli owner" $split.Owner
    Write-ThemeValue "aktif hesap" $script:GhUser
    Write-ThemeValue "yeni hedef" $updatedFullName

    return $updatedFullName
}

function Repair-RepoRecordCasing($record) {
    if ($null -eq $record -or [string]::IsNullOrWhiteSpace($record.FullName)) {
        return $record
    }

    $canonicalFullName = Resolve-CanonicalRepoFullName ([string]$record.FullName)

    if ([string]::IsNullOrWhiteSpace($canonicalFullName)) {
        return $record
    }

    $localPath = [string]$record.LocalPath
    $updated = New-RepoRecord $canonicalFullName $localPath

    if ([string]$updated.FullName -ne [string]$record.FullName -or [string]$updated.SiteUrl -ne [string]$record.SiteUrl -or [string]$updated.RepoUrl -ne [string]$record.RepoUrl) {
        Upsert-Record $updated

        if (![string]::IsNullOrWhiteSpace($localPath) -and (Get-FullPathSafe $localPath) -eq (Get-FullPathSafe (Get-Location).Path)) {
            Save-LocalMap $updated.FullName $updated.RepoName $updated.SiteUrl
        }

        Write-StatusInfo "Repo kaydi GitHub'daki gercek adla esitlendi: $($updated.FullName)"
    }

    return $updated
}

function Test-ShouldSkipPublishItem($relativePath, $isDirectory) {
    if ([string]::IsNullOrWhiteSpace($relativePath)) {
        return $false
    }

    $normalized = ($relativePath -replace '\\', '/').Trim("/")
    $segments = @($normalized.Split("/", [System.StringSplitOptions]::RemoveEmptyEntries))

    foreach ($segment in $segments) {
        $lowerSegment = $segment.ToLowerInvariant()

        if ($lowerSegment -eq ".git" -or $lowerSegment -eq "node_modules") {
            return $true
        }

        if ($lowerSegment -eq ".env" -or $lowerSegment.StartsWith(".env.")) {
            return $true
        }
    }

    if ($segments.Count -eq 0) {
        return $false
    }

    $leaf = $segments[$segments.Count - 1].ToLowerInvariant()

    if ($leaf -in @(
        ".gh-pages-publisher.json",
        ".gitignore",
        ".nojekyll",
        "github-pages-manager.bat",
        "github-pages-update-admin.bat",
        ".ds_store",
        "thumbs.db"
    )) {
        return $true
    }

    if (!$isDirectory -and $leaf -like "*.log") {
        return $true
    }

    return $false
}

function Clear-StagingContent($stagingPath) {
    Ensure-WorktreesDir
    Assert-PathInside $stagingPath $WorktreesDir

    if (!(Test-Path $stagingPath)) {
        [System.IO.Directory]::CreateDirectory($stagingPath) | Out-Null
        return
    }

    foreach ($item in @(Get-ChildItem -LiteralPath $stagingPath -Force)) {
        if ($item.Name -eq ".git") {
            continue
        }

        Remove-Item -LiteralPath $item.FullName -Recurse -Force
    }
}

function Copy-PublishTree($sourceDir, $destDir, $baseRoot) {
    foreach ($item in @(Get-ChildItem -LiteralPath $sourceDir -Force)) {
        $relativePath = $item.FullName.Substring($baseRoot.Length).TrimStart([char[]]"\/")

        if (Test-ShouldSkipPublishItem $relativePath $item.PSIsContainer) {
            continue
        }

        $targetPath = Join-Path $destDir $item.Name
        $targetParent = Split-Path -Parent $targetPath

        if (![string]::IsNullOrWhiteSpace($targetParent)) {
            [System.IO.Directory]::CreateDirectory($targetParent) | Out-Null
        }

        if ($item.PSIsContainer) {
            [System.IO.Directory]::CreateDirectory($targetPath) | Out-Null
            Copy-PublishTree $item.FullName $targetPath $baseRoot
        }
        else {
            Copy-Item -LiteralPath $item.FullName -Destination $targetPath -Force
        }
    }
}

function Get-PublishReferenceFiles($rootPath) {
    $rootFull = Get-FullPathSafe $rootPath

    return @(Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force | Where-Object {
        $relativePath = $_.FullName.Substring($rootFull.Length).TrimStart([char[]]"\/")
        $extension = $_.Extension.ToLowerInvariant()
        ($extension -in @(".html", ".htm", ".css")) -and !(Test-ShouldSkipPublishItem $relativePath $false)
    })
}

function Get-PublishReferencePathOnly($reference) {
    if ([string]::IsNullOrWhiteSpace($reference)) {
        return ""
    }

    $trimmed = ([string]$reference).Trim()

    if ($trimmed.StartsWith("#")) {
        return ""
    }

    return (($trimmed -split "[?#]", 2)[0])
}

function Test-IsLocalPublishReference($reference) {
    $pathOnly = Get-PublishReferencePathOnly $reference

    if ([string]::IsNullOrWhiteSpace($pathOnly)) {
        return $false
    }

    $lower = $pathOnly.ToLowerInvariant()

    if ($lower.StartsWith("//")) {
        return $false
    }

    if ($lower -match "^[a-z][a-z0-9+.-]*:") {
        return $false
    }

    return $true
}

function Test-ShouldValidatePublishReference($kind, $reference) {
    if (!(Test-IsLocalPublishReference $reference)) {
        return $false
    }

    $kindValue = ([string]$kind).ToLowerInvariant()

    if ($kindValue -ne "href") {
        return $true
    }

    $pathOnly = Get-PublishReferencePathOnly $reference
    $extension = [System.IO.Path]::GetExtension($pathOnly)

    if (![string]::IsNullOrWhiteSpace($extension)) {
        return $true
    }

    $normalized = $pathOnly -replace "\\", "/"

    if ($normalized.StartsWith("/assets/", [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalized.StartsWith("assets/", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    return $false
}

function Convert-PathToFileUri($path) {
    $full = (Get-FullPathSafe $path) -replace "\\", "/"

    if (!$full.StartsWith("/")) {
        $full = "/" + $full
    }

    return [Uri]::new("file://$full")
}

function Get-RelativeReferenceFromFile($filePath, $targetPath) {
    $baseDir = Split-Path -Parent (Get-FullPathSafe $filePath)
    $baseFull = (Get-FullPathSafe $baseDir).TrimEnd([char[]]"\/") + [System.IO.Path]::DirectorySeparatorChar
    $baseUri = Convert-PathToFileUri $baseFull
    $targetUri = Convert-PathToFileUri $targetPath
    $relative = $baseUri.MakeRelativeUri($targetUri).ToString()
    return [Uri]::UnescapeDataString($relative)
}

function Get-RelativePublishPath($rootPath, $targetPath) {
    $rootFull = (Get-FullPathSafe $rootPath).TrimEnd([char[]]"\/")
    $targetFull = Get-FullPathSafe $targetPath

    if ($targetFull.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return ""
    }

    return (($targetFull.Substring($rootFull.Length)).TrimStart([char[]]"\/") -replace "\\", "/")
}

function Get-PublishReferenceTargetPath($rootPath, $filePath, $reference) {
    $pathOnly = Get-PublishReferencePathOnly $reference

    if ([string]::IsNullOrWhiteSpace($pathOnly)) {
        return $null
    }

    $pathOnly = [Uri]::UnescapeDataString($pathOnly)

    if ($pathOnly.StartsWith("/")) {
        $rootRelative = $pathOnly.TrimStart("/")
        $rootName = Split-Path -Leaf (Get-FullPathSafe $rootPath)

        if ($rootRelative.StartsWith("$rootName/", [System.StringComparison]::OrdinalIgnoreCase)) {
            $rootRelative = $rootRelative.Substring($rootName.Length + 1)
        }

        return Get-FullPathSafe (Join-Path (Get-FullPathSafe $rootPath) $rootRelative)
    }

    $baseDir = Split-Path -Parent (Get-FullPathSafe $filePath)
    return Get-FullPathSafe (Join-Path $baseDir $pathOnly)
}

function Test-PathInsideRoot($rootPath, $targetPath) {
    if ([string]::IsNullOrWhiteSpace($targetPath)) {
        return $false
    }

    $rootFull = (Get-FullPathSafe $rootPath).TrimEnd([char[]]"\/")
    $targetFull = Get-FullPathSafe $targetPath
    $rootPrefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar

    return ($targetFull.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -or
        $targetFull.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase))
}

function Find-CaseInsensitivePublishPath($rootPath, $targetPath) {
    if (!(Test-PathInsideRoot $rootPath $targetPath)) {
        return $null
    }

    $relative = Get-RelativePublishPath $rootPath $targetPath

    if ([string]::IsNullOrWhiteSpace($relative)) {
        return Get-FullPathSafe $rootPath
    }

    $current = Get-FullPathSafe $rootPath

    foreach ($segment in @($relative.Split("/", [System.StringSplitOptions]::RemoveEmptyEntries))) {
        $match = @(Get-ChildItem -LiteralPath $current -Force | Where-Object {
            $_.Name.Equals($segment, [System.StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1)

        if ($match.Count -eq 0) {
            return $null
        }

        $current = $match[0].FullName
    }

    return $current
}

function Test-ExactPublishPathCase($rootPath, $targetPath) {
    $resolved = Find-CaseInsensitivePublishPath $rootPath $targetPath

    if ([string]::IsNullOrWhiteSpace($resolved)) {
        return $false
    }

    return (Get-FullPathSafe $resolved).Equals((Get-FullPathSafe $targetPath), [System.StringComparison]::Ordinal)
}

function Test-PublishReferenceTargetExists($targetPath, $kind) {
    if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
        return $true
    }

    if (([string]$kind).ToLowerInvariant() -eq "href" -and (Test-Path -LiteralPath $targetPath -PathType Container)) {
        $indexPath = Join-Path $targetPath "index.html"
        return (Test-Path -LiteralPath $indexPath -PathType Leaf)
    }

    return $false
}

function Get-PublishImageExtensions {
    return @(".jpg", ".jpeg", ".png", ".webp", ".gif", ".svg", ".avif")
}

function Test-IsPublishImagePath($path) {
    $extension = ([System.IO.Path]::GetExtension([string]$path)).ToLowerInvariant()
    return ((Get-PublishImageExtensions) -contains $extension)
}

function Test-IsHeroFallbackReference($pathOnly, $kind) {
    $kindValue = ([string]$kind).ToLowerInvariant()

    if ($kindValue -notin @("src", "url")) {
        return $false
    }

    if (!(Test-IsPublishImagePath $pathOnly)) {
        return $false
    }

    $name = ([System.IO.Path]::GetFileNameWithoutExtension([string]$pathOnly)).ToLowerInvariant()
    return ($name -in @("hero", "banner", "background", "bg", "cover", "header", "text-bg"))
}

function Get-PublishAssetFallbackCandidates($rootPath, $reference, $kind) {
    $pathOnly = Get-PublishReferencePathOnly $reference

    if (!(Test-IsHeroFallbackReference $pathOnly $kind)) {
        return @()
    }

    $assetsDir = Join-Path (Get-FullPathSafe $rootPath) "assets"

    if (!(Test-Path -LiteralPath $assetsDir -PathType Container)) {
        return @()
    }

    $wantedName = ([System.IO.Path]::GetFileNameWithoutExtension([string]$pathOnly)).ToLowerInvariant()
    $imageExtensions = Get-PublishImageExtensions
    $files = @(Get-ChildItem -LiteralPath $assetsDir -File -Force | Where-Object {
        $imageExtensions -contains $_.Extension.ToLowerInvariant()
    })

    $exactNameMatches = @($files | Where-Object {
        ([System.IO.Path]::GetFileNameWithoutExtension($_.Name)).Equals($wantedName, [System.StringComparison]::OrdinalIgnoreCase)
    })

    if ($exactNameMatches.Count -gt 0) {
        return @($exactNameMatches | ForEach-Object { $_.FullName })
    }

    $fallbackNames = @("hero", "banner", "background", "bg", "cover", "header", "text-bg")
    return @($files | Where-Object {
        $fallbackNames -contains ([System.IO.Path]::GetFileNameWithoutExtension($_.Name)).ToLowerInvariant()
    } | ForEach-Object { $_.FullName })
}

function Get-RepairedPublishReference($rootPath, $filePath, $reference, $kind) {
    if (!(Test-ShouldValidatePublishReference $kind $reference)) {
        return $null
    }

    $pathOnly = Get-PublishReferencePathOnly $reference
    $suffix = ([string]$reference).Substring($pathOnly.Length)
    $targetPath = Get-PublishReferenceTargetPath $rootPath $filePath $reference

    if ([string]::IsNullOrWhiteSpace($targetPath)) {
        return $null
    }

    if ($pathOnly.StartsWith("/") -and (Test-PublishReferenceTargetExists $targetPath $kind)) {
        return (Get-RelativeReferenceFromFile $filePath $targetPath) + $suffix
    }

    if ((Test-PublishReferenceTargetExists $targetPath $kind) -and (Test-ExactPublishPathCase $rootPath $targetPath)) {
        return $null
    }

    $leaf = Split-Path -Leaf $pathOnly

    if ($pathOnly -notmatch "[/\\]" -and ![string]::IsNullOrWhiteSpace($leaf)) {
        $assetCandidate = Join-Path (Join-Path (Get-FullPathSafe $rootPath) "assets") $leaf

        if (Test-Path -LiteralPath $assetCandidate -PathType Leaf) {
            return (Get-RelativeReferenceFromFile $filePath $assetCandidate) + $suffix
        }
    }

    $fallbackCandidates = @(Get-PublishAssetFallbackCandidates $rootPath $reference $kind)

    if ($fallbackCandidates.Count -eq 1) {
        return (Get-RelativeReferenceFromFile $filePath $fallbackCandidates[0]) + $suffix
    }

    return $null
}

function Repair-PublishAssetReferences($rootPath) {
    Assert-PathInside $rootPath $WorktreesDir

    $fixedCount = 0

    foreach ($file in @(Get-PublishReferenceFiles $rootPath)) {
        $content = [System.IO.File]::ReadAllText($file.FullName)
        $original = $content

        $content = [regex]::Replace($content, '(?i)\b(src|href)(\s*=\s*)(["''])(.*?)\3', {
            param($match)
            $kind = $match.Groups[1].Value.ToLowerInvariant()
            $newReference = Get-RepairedPublishReference $rootPath $file.FullName $match.Groups[4].Value $kind

            if ([string]::IsNullOrWhiteSpace($newReference)) {
                return $match.Value
            }

            return $match.Groups[1].Value + $match.Groups[2].Value + $match.Groups[3].Value + $newReference + $match.Groups[3].Value
        })

        $content = [regex]::Replace($content, 'url\(\s*(["'']?)([^"''\)]+)\1\s*\)', {
            param($match)
            $newReference = Get-RepairedPublishReference $rootPath $file.FullName $match.Groups[2].Value "url"

            if ([string]::IsNullOrWhiteSpace($newReference)) {
                return $match.Value
            }

            $quote = $match.Groups[1].Value

            if ([string]::IsNullOrWhiteSpace($quote)) {
                return "url($newReference)"
            }

            return "url($quote$newReference$quote)"
        })

        if ($content -ne $original) {
            [System.IO.File]::WriteAllText($file.FullName, $content, [System.Text.UTF8Encoding]::new($false))
            $relativeFile = Get-RelativePublishPath $rootPath $file.FullName
            Write-StatusInfo "Yayin kopyasinda asset yollari duzeltildi: $relativeFile"
            $fixedCount++
        }
    }

    if ($fixedCount -gt 0) {
        Write-StatusOk "Kaynak dosyalara dokunulmadan $fixedCount yayin kopyasi dosyasinda asset yolu duzeltildi."
    }
}

function Get-PublishReferencesFromContent($content) {
    $references = New-Object System.Collections.ArrayList

    foreach ($match in [regex]::Matches($content, '(?i)\b(src|href)\s*=\s*(["''])(.*?)\2')) {
        [void]$references.Add([PSCustomObject]@{
            Kind = $match.Groups[1].Value.ToLowerInvariant()
            Reference = $match.Groups[3].Value
        })
    }

    foreach ($match in [regex]::Matches($content, 'url\(\s*(["'']?)([^"''\)]+)\1\s*\)')) {
        [void]$references.Add([PSCustomObject]@{
            Kind = "url"
            Reference = $match.Groups[2].Value
        })
    }

    return @($references.ToArray())
}

function Assert-PublishAssetReferences($rootPath) {
    $issues = New-Object System.Collections.ArrayList
    $script:LastAssetValidationIssues = @()

    foreach ($file in @(Get-PublishReferenceFiles $rootPath)) {
        $content = [System.IO.File]::ReadAllText($file.FullName)
        $relativeFile = Get-RelativePublishPath $rootPath $file.FullName

        foreach ($referenceInfo in @(Get-PublishReferencesFromContent $content)) {
            $kind = [string]$referenceInfo.Kind
            $reference = [string]$referenceInfo.Reference

            if (!(Test-ShouldValidatePublishReference $kind $reference)) {
                continue
            }

            $pathOnly = Get-PublishReferencePathOnly $reference
            $targetPath = Get-PublishReferenceTargetPath $rootPath $file.FullName $reference

            if ($pathOnly.StartsWith("/")) {
                [void]$issues.Add("$relativeFile [$kind] -> $reference : kok-relative path GitHub Pages proje sitesinde bozulur.")
                continue
            }

            if (!(Test-PathInsideRoot $rootPath $targetPath)) {
                [void]$issues.Add("$relativeFile [$kind] -> $reference : proje klasoru disina cikiyor.")
                continue
            }

            if (!(Test-PublishReferenceTargetExists $targetPath $kind)) {
                $caseMatch = Find-CaseInsensitivePublishPath $rootPath $targetPath

                if (![string]::IsNullOrWhiteSpace($caseMatch)) {
                    $expected = Get-RelativePublishPath $rootPath $caseMatch
                    [void]$issues.Add("$relativeFile [$kind] -> $reference : buyuk/kucuk harf uyusmuyor. Gercek dosya: $expected")
                }
                else {
                    $fallbackCandidates = @(Get-PublishAssetFallbackCandidates $rootPath $reference $kind)

                    if ($fallbackCandidates.Count -gt 1) {
                        $candidateText = (@($fallbackCandidates) | ForEach-Object { Get-RelativePublishPath $rootPath $_ }) -join ", "
                        [void]$issues.Add("$relativeFile [$kind] -> $reference : dosya bulunamadi; birden fazla uygun aday var: $candidateText")
                    }
                    else {
                        [void]$issues.Add("$relativeFile [$kind] -> $reference : dosya bulunamadi.")
                    }
                }

                continue
            }

            if ((Test-Path -LiteralPath $targetPath -PathType Leaf) -and !(Test-ExactPublishPathCase $rootPath $targetPath)) {
                $expected = Get-RelativePublishPath $rootPath (Find-CaseInsensitivePublishPath $rootPath $targetPath)
                [void]$issues.Add("$relativeFile [$kind] -> $reference : buyuk/kucuk harf uyusmuyor. Gercek dosya: $expected")
            }
        }
    }

    if ($issues.Count -gt 0) {
        $script:LastAssetValidationIssues = @($issues.ToArray())
        Write-BoxMessage "asset path error" "Yayin durduruldu. GitHub Pages'ta calismayacak dosya yollari var." "Red"

        foreach ($issue in @($script:LastAssetValidationIssues)) {
            Write-Host "- $issue"
        }

        $summary = (@($script:LastAssetValidationIssues) | Select-Object -First 8) -join [Environment]::NewLine
        throw ("Asset yolu kontrolu basarisiz." + [Environment]::NewLine + $summary)
    }

    Write-StatusOk "Asset yollari GitHub Pages icin uygun."
}

function Sync-ProjectToStaging($sourcePath, $stagingPath) {
    if (!(Test-Path $sourcePath)) {
        throw "Kaynak proje klasoru bulunamadi: $sourcePath"
    }

    $sourceFull = Get-FullPathSafe $sourcePath
    $stagingFull = Get-FullPathSafe $stagingPath

    Assert-PathInside $stagingFull $WorktreesDir
    Clear-StagingContent $stagingFull

    Write-StatusInfo "Proje dosyalari staging klasorune hazirlaniyor..."
    Copy-PublishTree $sourceFull $stagingFull $sourceFull

    Write-StatusInfo "Yayin kopyasinda asset yollari GitHub Pages icin kontrol ediliyor..."
    Repair-PublishAssetReferences $stagingFull
    Assert-PublishAssetReferences $stagingFull

    $nojekyllPath = Join-Path $stagingFull ".nojekyll"
    if (!(Test-Path $nojekyllPath)) {
        New-Item -ItemType File -Path $nojekyllPath | Out-Null
    }
}

function Remove-StagingForRecord($record) {
    try {
        if ($null -eq $record -or [string]::IsNullOrWhiteSpace($record.FullName)) {
            return
        }

        $stagingPath = Get-RepoWorktreePath $record.FullName

        if (Test-Path $stagingPath) {
            Assert-PathInside $stagingPath $WorktreesDir
            Remove-Item -LiteralPath $stagingPath -Recurse -Force
        }
    }
    catch {
        Write-StatusWarn "Staging klasoru temizlenemedi: $($_.Exception.Message)"
    }
}

function Save-LocalMap($fullName, $repoName, $siteUrl) {
    try {
        if ([string]::IsNullOrWhiteSpace($fullName)) {
            return
        }

        $map = [PSCustomObject]@{
            SchemaVersion = 1
            FullName = [string]$fullName
            RepoName = [string]$repoName
            SiteUrl = [string]$siteUrl
            UpdatedAt = (Get-Date).ToString("s")
        }

        $json = $map | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($LocalMapFile, $json, [System.Text.UTF8Encoding]::new($false))
    }
    catch {
        Write-StatusWarn "Yerel repo baglanti dosyasi yazilamadi: $($_.Exception.Message)"
    }
}

function Load-LocalMap {
    if (!(Test-Path $LocalMapFile)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $LocalMapFile -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Ensure-GitRepo($fullName, $repoPath) {
    if ([string]::IsNullOrWhiteSpace($repoPath)) {
        throw "Git staging klasoru bos geldi."
    }

    if (!(Test-Path $repoPath)) {
        New-Item -ItemType Directory -Path $repoPath -Force | Out-Null
    }

    Assert-PathInside $repoPath $WorktreesDir
    Push-Location $repoPath

    try {
        if (!(Test-Path ".git")) {
            Write-StatusInfo "Git staging repo baslatiliyor..."
            & git init

            if ($LASTEXITCODE -ne 0) {
                throw "git init basarisiz."
            }
        }

        & git branch -M main *> $null

        if (![string]::IsNullOrWhiteSpace($script:GhUser)) {
            & git config user.name $script:GhUser
            & git config user.email "$script:GhUser@users.noreply.github.com"
        }

        $remoteUrl = "https://github.com/$fullName.git"
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"

        try {
            $remotes = @(& git remote 2>$null)
            if ($LASTEXITCODE -ne 0) {
                throw "Git remote listesi okunamadi."
            }

            if ($remotes -contains "origin") {
                & git remote set-url origin $remoteUrl *> $null
            }
            else {
                & git remote add origin $remoteUrl *> $null
            }

            if ($LASTEXITCODE -ne 0) {
                throw "Git remote ayarlanamadi."
            }
        }
        finally {
            $ErrorActionPreference = $oldPreference
        }
    }
    finally {
        Pop-Location
    }
}

function Enable-Pages($owner, $repo) {
    Write-StatusInfo "GitHub Pages aktif ediliyor..."

    $post = Invoke-GhSilent @(
        "api",
        "--method", "POST",
        "-H", "Accept: application/vnd.github+json",
        "/repos/$owner/$repo/pages",
        "-f", "build_type=legacy",
        "-f", "source[branch]=main",
        "-f", "source[path]=/"
    )

    if ($post.Code -ne 0) {
        $put = Invoke-GhSilent @(
            "api",
            "--method", "PUT",
            "-H", "Accept: application/vnd.github+json",
            "/repos/$owner/$repo/pages",
            "-f", "build_type=legacy",
            "-f", "source[branch]=main",
            "-f", "source[path]=/"
        )

        if ($put.Code -ne 0) {
            Write-StatusWarn "Pages ayari otomatik tamamlanamadi."
            Write-BoxMessage "pages warning" "Repo yuklendi ama Pages'i GitHub ayarlarindan manuel acman gerekebilir." "Yellow"
        }
    }
}

function Invoke-GitWithRetry($argsList, $label, $maxAttempts, $delaySeconds) {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $script:LastGitOutput = ""

    try {
        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            if ($attempt -gt 1) {
                Write-Host ""
                Write-StatusInfo "$label tekrar deneniyor ($attempt/$maxAttempts)..."
            }

            $gitOutput = & git @argsList 2>&1

            $script:LastGitOutput = (@($gitOutput) | ForEach-Object {
                $_.ToString()
            }) -join [Environment]::NewLine

            foreach ($line in @($gitOutput)) {
                Write-Host $line.ToString()
            }

            $code = $LASTEXITCODE

            if ($code -eq 0) {
                return 0
            }

            if ($attempt -lt $maxAttempts) {
                $waitSeconds = $delaySeconds * $attempt
                Write-Host ""
                Write-StatusWarn "$label basarisiz oldu. $waitSeconds saniye sonra tekrar denenecek..."
                Start-Sleep -Seconds $waitSeconds
            }
        }

        return $code
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }
}

function Test-GitPushAuthFailure($output) {
    if ([string]::IsNullOrWhiteSpace($output)) {
        return $false
    }

    return ($output -match "Permission to .+ denied to .+" -or
        $output -match "The requested URL returned error:\s*403" -or
        $output -match "Authentication failed" -or
        $output -match "Repository not found")
}

function Commit-And-Push($repoPath) {
    if ([string]::IsNullOrWhiteSpace($repoPath)) {
        throw "Git commit klasoru bos geldi."
    }

    Assert-PathInside $repoPath $WorktreesDir
    Push-Location $repoPath

    try {
        Write-StatusInfo "Dosyalar commitleniyor..."

        & git add -A

        if ($LASTEXITCODE -ne 0) {
            throw "git add basarisiz."
        }

        & git diff --cached --quiet

        if ($LASTEXITCODE -ne 0) {
            & git commit -m "Publish website demo"

            if ($LASTEXITCODE -ne 0) {
                throw "git commit basarisiz."
            }
        }
        else {
            Write-StatusInfo "Yeni commitlenecek degisiklik yok."
        }

        Write-StatusInfo "GitHub'a yukleniyor..."

        $pushCode = Invoke-GitWithRetry -argsList @("push", "-u", "origin", "main") -label "Normal push" -maxAttempts 1 -delaySeconds 5

        if ($pushCode -ne 0) {
            if (Test-GitPushAuthFailure $script:LastGitOutput) {
                Write-BoxMessage "auth error" "GitHub push yetkisi reddedildi. Aktif GitHub hesabi hedef repoya yazamiyor." "Red"
                Write-ThemeValue "aktif hesap" $script:GhUser
                $remote = (& git remote get-url origin 2>$null)
                if (![string]::IsNullOrWhiteSpace($remote)) {
                    Write-ThemeValue "remote" $remote
                }
                throw "GitHub push yetkisi reddedildi."
            }

            Write-BoxMessage "force push" "Normal push basarisiz oldu. Uzak repo bu klasorle otomatik ezilecek." "Yellow"

            $forcePushCode = Invoke-GitWithRetry -argsList @("push", "-u", "origin", "main", "--force") -label "Force push" -maxAttempts 1 -delaySeconds 5

            if ($forcePushCode -ne 0) {
                if (Test-GitPushAuthFailure $script:LastGitOutput) {
                    Write-BoxMessage "auth error" "GitHub force push yetkisi reddedildi. Aktif GitHub hesabi hedef repoya yazamiyor." "Red"
                    Write-ThemeValue "aktif hesap" $script:GhUser
                    $remote = (& git remote get-url origin 2>$null)
                    if (![string]::IsNullOrWhiteSpace($remote)) {
                        Write-ThemeValue "remote" $remote
                    }
                    throw "GitHub push yetkisi reddedildi."
                }

                throw "Force push da basarisiz oldu."
            }
        }
    }
    finally {
        Pop-Location
    }
}

function Publish-CurrentFolder {
    Header

    if (!(Test-Path "index.html")) {
        Write-BoxMessage "publish blocked" "Bu klasorde index.html yok. BAT dosyasini yayina almak istedigin sitenin ana klasorune koy." "Red"
        After-Action
        return
    }

    Ensure-GitHubReady

    $currentPath = (Get-Location).Path
    $localMap = Load-LocalMap
    $db = @(Load-Db)

    $fullName = $null
    $repoName = $null

    if ($null -ne $localMap -and ![string]::IsNullOrWhiteSpace($localMap.FullName)) {
        $fullName = $localMap.FullName
        $repoName = $localMap.RepoName
        Write-ThemeValue "baglanti" $fullName
    }
    else {
        $existing = $db | Where-Object { $_.LocalPath -eq $currentPath } | Select-Object -First 1

        if ($null -ne $existing) {
            $fullName = $existing.FullName
            $repoName = $existing.RepoName
            Write-ThemeValue "kayit" $fullName
        }
    }

    if ([string]::IsNullOrWhiteSpace($fullName)) {
        $defaultRepo = Get-SafeRepoName

        Write-BoxMessage "new repo" "Bu klasor henuz bir GitHub reposuna bagli degil." "Cyan"
        Write-ThemeValue "otomatik ad" $defaultRepo
        Write-Host ""

        $custom = Read-Host "Repo adi yaz veya otomatik ad icin ENTER"

        if ([string]::IsNullOrWhiteSpace($custom)) {
            $repoName = $defaultRepo
        }
        else {
            $repoName = $custom.Trim()
        }

        $repoName = Normalize-RepoNameInput $repoName
        $fullName = "$script:GhUser/$repoName"
    }

    $fullName = Resolve-PublishFullNameForActiveUser $fullName $repoName
    $fullName = Resolve-CanonicalRepoFullName $fullName
    $record = New-RepoRecord $fullName $currentPath
    $owner = $record.Owner
    $repoName = $record.RepoName
    $siteUrl = $record.SiteUrl
    $repoUrl = $record.RepoUrl

    Write-Host ""
    Write-ThemeValue "repo" $fullName
    Write-ThemeValue "site" $siteUrl
    Write-BoxMessage "clean mode" "Proje klasoru temiz kalacak; Git islemleri uygulama staging klasorunde yapiliyor." "Cyan"
    Write-Host ""

    $worktreePath = $record.WorktreePath

    Write-StatusInfo "Repo kaydi yaziliyor..."
    Upsert-Record $record
    Save-LocalMap $record.FullName $record.RepoName $record.SiteUrl

    $writtenCheck = [System.IO.File]::ReadAllText($DbPath)

    if ([string]::IsNullOrWhiteSpace($writtenCheck) -or $writtenCheck.Trim() -eq "[]") {
        throw "Kayit yazilamadi. repos.json hala bos: $DbPath"
    }

    Write-StatusOk "Kayit dosyasi dolu."
    Write-ThemeValue "kayit" $DbPath
    Write-Host ""

    $repoView = Invoke-GhSilent @("repo", "view", $fullName)
    $repoExists = $repoView.Code -eq 0

    if (!$repoExists) {
        Write-StatusInfo "GitHub reposu yok. Olusturuluyor..."

        $createResult = Invoke-GhInteractiveWithRetry -argsList @("repo", "create", $fullName, "--public") -label "GitHub reposu olusturma" -maxAttempts 4 -delaySeconds 5

        if ($createResult.Code -ne 0) {
            $repoViewAfterCreate = Invoke-GhSilent @("repo", "view", $fullName)

            if ($repoViewAfterCreate.Code -ne 0) {
                throw "GitHub reposu olusturulamadi."
            }

            Write-StatusInfo "Repo olusturma komutu hata verdi ama repo GitHub'da gorunuyor. Devam ediliyor."
        }
    }
    else {
        Write-StatusInfo "GitHub reposu var. Guncellenecek."
    }

    $canonicalAfterCreate = Resolve-CanonicalRepoFullName $fullName

    if (![string]::IsNullOrWhiteSpace($canonicalAfterCreate) -and $canonicalAfterCreate -ne $fullName) {
        $fullName = $canonicalAfterCreate
        $record = New-RepoRecord $fullName $currentPath
        $owner = $record.Owner
        $repoName = $record.RepoName
        $siteUrl = $record.SiteUrl
        $repoUrl = $record.RepoUrl
        $worktreePath = $record.WorktreePath
        Upsert-Record $record
        Save-LocalMap $record.FullName $record.RepoName $record.SiteUrl
        Write-StatusInfo "Repo adi GitHub ile esitlendi: $fullName"
    }

    Sync-ProjectToStaging $currentPath $worktreePath
    Ensure-GitRepo $fullName $worktreePath
    Commit-And-Push $worktreePath
    Enable-Pages $owner $repoName

    $finalRecord = New-RepoRecord $fullName $currentPath
    Upsert-Record $finalRecord
    Save-LocalMap $finalRecord.FullName $finalRecord.RepoName $finalRecord.SiteUrl
    Start-ClientStatusWorker "publish" $finalRecord.FullName $finalRecord.SiteUrl

    Write-BoxMessage "publish complete" "Yayin / guncelleme tamamlandi." "Green"
    Write-ThemeValue "repo" $finalRecord.RepoUrl
    Write-ThemeValue "site" $finalRecord.SiteUrl
    Write-ThemeValue "kayit" $DbPath
    Write-StatusInfo "Ilk yayin bazen 1-3 dakika gec acilabilir."

    After-Publish $finalRecord.SiteUrl
}

function Remove-LocalMap-IfMatches($record) {
    try {
        if ($null -eq $record -or !(Test-Path $LocalMapFile)) {
            return
        }

        $localMap = Load-LocalMap

        if ($null -eq $localMap -or [string]::IsNullOrWhiteSpace($localMap.FullName)) {
            return
        }

        if (([string]$localMap.FullName).Equals([string]$record.FullName, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $LocalMapFile -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
    }
}

function Delete-GitHubRepo($record) {
    Header

    Ensure-GitHubReady

    Write-ThemeValue "repo" $record.FullName
    Write-BoxMessage "danger zone" "Bu islem GitHub reposunu gercekten siler. Geri almak kolay degil." "Yellow"
    Write-Host ""

    $confirm = Read-Host "Silmek icin repo adini aynen yaz: $($record.RepoName)"

    if ($confirm -ne $record.RepoName) {
        Write-Host ""
        Write-BoxMessage "cancelled" "Silme iptal edildi." "Yellow"
        Pause-Back
        return $false
    }

    $authOk = Ensure-OwnerAuth $record.Owner

    if (!$authOk) {
        return $false
    }

    Header

    Write-ThemeValue "repo" $record.FullName
    Write-StatusInfo "Silme yetkisi kontrol ediliyor..."

    if (Test-GhHasScope "delete_repo") {
        Write-StatusOk "delete_repo yetkisi zaten var."
    }
    else {
        $refreshResult = Invoke-GhInteractiveResult @("auth", "refresh", "--hostname", "github.com", "-s", "delete_repo")

        if ($refreshResult.Code -ne 0) {
            $repairOk = Repair-GhAuthForOwner $record.Owner $refreshResult.Output

            if (!$repairOk) {
                Write-Host ""
                Write-BoxMessage "auth error" "delete_repo yetkisi alinamadi." "Red"
                Write-ThemeValue "beklenen" $record.Owner
                Pause-Back
                return $false
            }

            Header

            Write-ThemeValue "repo" $record.FullName
            Write-BoxMessage "auth repaired" "GitHub CLI hesap kaydi ve silme yetkisi onarildi." "Green"
        }
    }

    Write-StatusInfo "GitHub reposu siliniyor..."

    $deleteCode = Invoke-GhInteractive @("repo", "delete", $record.FullName, "--yes")

    if ($deleteCode -ne 0) {
        Write-BoxMessage "delete error" "Repo silinemedi." "Red"
        Pause-Back
        return $false
    }

    Remove-Record $record.FullName
    Remove-LocalMap-IfMatches $record
    Remove-StagingForRecord $record

    Write-Host ""
    Write-BoxMessage "deleted" "Repo GitHub'dan silindi ve kayittan kaldirildi." "Green"
    Pause-Back
    return $true
}

function Remove-OnlyRecord($record) {
    Remove-Record $record.FullName
    Remove-LocalMap-IfMatches $record
    Remove-StagingForRecord $record

    Write-Host ""
    Write-BoxMessage "record removed" "Kayit kaldirildi. GitHub reposuna dokunulmadi." "Green"
    Pause-Back
    return $true
}

function Repo-Options($record) {
    $selectionTelemetryQueued = $false

    while ($true) {
        if ($script:ReturnToMain) {
            return
        }

        $record = Repair-RepoRecordCasing $record

        if (!$selectionTelemetryQueued) {
            Start-ClientStatusWorker "repo-selected" $record.FullName $record.SiteUrl
            $selectionTelemetryQueued = $true
        }

        Header

        Write-ThemeValue "repo" $record.FullName
        Write-ThemeValue "site" $record.SiteUrl
        Write-ThemeValue "klasor" $record.LocalPath
        Write-Host ""
        Write-MenuFrame "repo actions" {
            Write-MenuItem "1" "siteyi ac"
            Write-MenuItem "2" "GitHub repo sayfasini ac"
            Write-MenuItem "3" "GitHub'dan sil ve kayittan kaldir"
            Write-MenuItem "4" "sadece kayittan kaldir"
            Write-MenuItem "8" "ana menu"
            Write-MenuItem "0" "geri"
        }
        Write-Host ""
        Write-KeyPrompt "secim"

        $choice = Read-KeyChoice @("1", "2", "3", "4", "8", "0")

        switch ($choice) {
            "1" {
                $record = Repair-RepoRecordCasing $record
                Start-ClientStatusWorker "open-site" $record.FullName $record.SiteUrl
                Start-Process $record.SiteUrl
                continue
            }
            "2" {
                $record = Repair-RepoRecordCasing $record
                Start-ClientStatusWorker "open-repo" $record.FullName $record.RepoUrl
                Start-Process $record.RepoUrl
                continue
            }
            "3" {
                $deleted = Delete-GitHubRepo $record

                if ($deleted -eq $true) {
                    return
                }

                continue
            }
            "4" {
                $removed = Remove-OnlyRecord $record

                if ($removed -eq $true) {
                    return
                }

                continue
            }
            "8" {
                $script:ReturnToMain = $true
                return
            }
            "0" {
                return
            }
        }
    }
}

function Show-RegisteredRepos {
    $telemetryQueued = $false

    while ($true) {
        if ($script:ReturnToMain) {
            return
        }

        Header

        if (!$telemetryQueued) {
            Start-ClientStatusWorker "repo-list-open" "" ""
            $telemetryQueued = $true
        }

        $items = @(Load-Db)

        if ($items.Count -eq 0) {
            Write-BoxMessage "repo records" "Kayitli repo yok." "Yellow"
            Write-ThemeValue "kayit" $DbPath
            Write-Host ""
            Write-MenuItem "0" "geri"
            Write-Host ""
            Write-KeyPrompt "secim"

            $choice = Read-KeyChoice @("0")
            return
        }

        Write-SectionTitle "repo records"
        Write-Host ""

        for ($i = 0; $i -lt $items.Count; $i++) {
            $n = $i + 1
            Write-MenuItem ([string]$n) $items[$i].FullName
            Write-Host "      site   : $($items[$i].SiteUrl)" -ForegroundColor DarkGray
            Write-Host "      klasor : $($items[$i].LocalPath)" -ForegroundColor DarkGray
            Write-Host ""
        }

        Write-Host "+---------------------------------------------------+" -ForegroundColor DarkCyan
        Write-MenuItem "0" "geri"
        Write-Host ""
        Write-KeyPrompt "repo"

        $validKeys = @("0")

        for ($i = 1; $i -le $items.Count; $i++) {
            if ($i -le 9) {
                $validKeys += "$i"
            }
        }

        $choice = Read-KeyChoice $validKeys

        if ($choice -eq "0") {
            return
        }

        $number = [int]$choice

        if ($number -lt 1 -or $number -gt $items.Count) {
            continue
        }

        Repo-Options $items[$number - 1]
    }
}

function Open-AppDataFolder {
    Ensure-WorktreesDir
    Start-Process $StoreDir
}

function Run-Action($action) {
    try {
        & $action
    }
    catch {
        Show-Error $_.Exception.Message
        After-Action
    }
}

function Invoke-StartupStep($name, [scriptblock]$action) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $status = "ok"
    $detail = ""

    try {
        & $action
    }
    catch {
        $status = "error"
        $detail = $_.Exception.Message
    }
    finally {
        $sw.Stop()

        [void]$script:StartupSteps.Add([PSCustomObject]@{
            Name = $name
            Status = $status
            Detail = $detail
            Milliseconds = $sw.ElapsedMilliseconds
        })
    }
}

function Save-StartupDiagnostic {
    try {
        Ensure-Storage

        $diagnostic = [PSCustomObject]@{
            SchemaVersion = 1
            StartedAt = (Get-Date).ToUniversalTime().ToString("o")
            AppVersion = $AppVersion
            Steps = @($script:StartupSteps.ToArray())
        }

        $json = $diagnostic | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($StartupDiagPath, $json, [System.Text.UTF8Encoding]::new($false))
    }
    catch {
    }
}

if ($env:GPM_TELEMETRY_WORKER -eq "1") {
    try {
        Ensure-Storage
        Submit-ClientStatus
    }
    catch {
        Save-ClientStatusDiagnostic "issue-failed" $_.Exception.Message
    }

    exit 0
}

try {
    $script:StartupSteps = New-Object System.Collections.ArrayList
    Invoke-StartupStep "storage" { Ensure-Storage }
    Invoke-StartupStep "update diagnosis" { Submit-PendingUpdateDiagnostic }
    Invoke-StartupStep "update check" { Check-ForUpdates }
    Invoke-StartupStep "telemetry worker" { Start-ClientStatusWorker }
    Save-StartupDiagnostic
}
catch {
    Show-Error $_.Exception.Message
    Write-Host ""
    Write-MenuItem "2" "Kapat"
    Write-Host ""
    Read-KeyChoice @("2") | Out-Null
    exit 1
}

while ($true) {
    $script:ReturnToMain = $false

    Header

    Write-ThemeValue "surum" $AppVersion
    Write-Host ""
    if ([string]::IsNullOrWhiteSpace($script:GhUser)) {
        Write-ThemeValue "github" "gerekince kontrol edilecek"
    }
    else {
        Write-ThemeValue "github" $script:GhUser
    }
    Write-ThemeValue "klasor" (Get-Location).Path
    Write-ThemeValue "kayit" $DbPath
    Write-Host ""
    Write-MenuFrame "operasyonlar" {
        Write-MenuItem "1" "repo kayitlari"
        Write-MenuItem "2" "bu klasoru yayinla / guncelle"
        Write-MenuItem "3" "guncelleme notlari"
        Write-MenuItem "4" "uygulama veri klasorunu ac"
        Write-MenuItem "5" "cikis"
    }
    Write-Host ""
    Write-KeyPrompt "secim"

    $mainChoice = Read-KeyChoice @("1", "2", "3", "4", "5")

    switch ($mainChoice) {
        "1" {
            Run-Action { Show-RegisteredRepos }
        }
        "2" {
            Run-Action { Publish-CurrentFolder }
        }
        "3" {
            Run-Action { Show-UpdateNotes }
        }
        "4" {
            Run-Action { Open-AppDataFolder }
        }
        "5" {
            exit 0
        }
    }
}
