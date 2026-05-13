@echo off
setlocal
cd /d "%~dp0"
set "BAT_FILE=%~f0"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$file=$env:BAT_FILE; $marker='### POWERSHELL ###'; $lines=Get-Content -LiteralPath $file; $idx=[Array]::IndexOf($lines,$marker); if($idx -lt 0){Write-Error 'PowerShell bolumu bulunamadi.'; exit 1}; $code=($lines[($idx+1)..($lines.Count-1)] -join [Environment]::NewLine); Invoke-Expression $code"

exit /b %ERRORLEVEL%

### POWERSHELL ###

$ErrorActionPreference = "Stop"

$AppVersion = "1.0.9"
$UpdateManifestUrl = "https://raw.githubusercontent.com/vengeance3355/github-pages-manager-updates/main/latest.json"
$ErrorReportRepo = "vengeance3355/github-pages-manager-updates"
$StoreDir = Join-Path $env:APPDATA "GithubPagesPublisher"
$DbPath = Join-Path $StoreDir "repos.json"
$WorktreesDir = Join-Path $StoreDir "worktrees"
$UpdateCheckCachePath = Join-Path $StoreDir "update-check.json"
$UpdateCheckCacheHours = 6
$HttpTimeoutSeconds = 8
$AdminConfigPath = Join-Path $env:APPDATA "GithubPagesPublisherAdmin\admin.json"
$LocalMapFile = ".gh-pages-publisher.json"
$script:ReturnToMain = $false
$script:GhUser = $null
$script:LastOpenedDeviceLoginUrl = $null
$script:IsSendingErrorReport = $false

function Write-ThemeLine($text = "", $color = "Gray") {
    Write-Host $text -ForegroundColor $color
}

function Write-ThemeValue($label, $value) {
    Write-Host ("[sys] {0,-12}: " -f $label) -ForegroundColor DarkGray -NoNewline
    Write-Host $value -ForegroundColor Green
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

    $curl = Get-Command "curl.exe" -ErrorAction SilentlyContinue

    if ($null -ne $curl) {
        $oldCurlPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"

        try {
            $curlOutput = & curl.exe --location --silent --show-error --fail --ssl-no-revoke `
                --max-time $HttpTimeoutSeconds `
                --header "User-Agent: GitHubPagesManager" `
                --header "Cache-Control: no-cache" `
                $url 2>&1
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

function Get-UpdateManifest($manifestUrl) {
    $pinnedManifestUrl = Get-PinnedManifestUrl $manifestUrl

    if (![string]::IsNullOrWhiteSpace($pinnedManifestUrl)) {
        try {
            $manifest = Invoke-JsonUrl $pinnedManifestUrl

            if ($null -ne $manifest) {
                return [PSCustomObject]@{
                    Manifest = $manifest
                    SourceUrl = $pinnedManifestUrl
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

function Test-UpdateCheckCacheFresh($cache, $manifestUrl) {
    if ($null -eq $cache -or [string]::IsNullOrWhiteSpace($cache.CheckedAt)) {
        return $false
    }

    if (![string]::IsNullOrWhiteSpace($cache.ManifestUrl) -and $cache.ManifestUrl -ne $manifestUrl) {
        return $false
    }

    try {
        $checkedAt = ([datetime]::Parse([string]$cache.CheckedAt)).ToUniversalTime()
        $age = (Get-Date).ToUniversalTime() - $checkedAt
        return $age.TotalHours -lt [double]$UpdateCheckCacheHours
    }
    catch {
        return $false
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
        Invoke-WebRequest -Uri $downloadUrl -OutFile $outFile -Headers $headers -UseBasicParsing
        return
    }
    catch {
        $lastError = $_.Exception.Message
    }
    finally {
        [Net.ServicePointManager]::SecurityProtocol = $oldProtocol
    }

    $curl = Get-Command "curl.exe" -ErrorAction SilentlyContinue

    if ($null -ne $curl) {
        $oldCurlPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"

        try {
            $curlOutput = & curl.exe --location --silent --show-error --fail --ssl-no-revoke `
                --header "User-Agent: GitHubPagesManager" `
                --header "Cache-Control: no-cache" `
                --output $outFile `
                $downloadUrl 2>&1
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
    $manifestPath = Join-Path $env:APPDATA "GithubPagesPublisherAdmin\update-repo\latest.json"

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
    return (Join-Path $env:APPDATA "GithubPagesPublisherAdmin\update-repo")
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

function Ensure-IssueLabels($repoFullName, $labels) {
    foreach ($label in @($labels)) {
        if ([string]::IsNullOrWhiteSpace($label)) {
            continue
        }

        $color = "ededed"

        if ($label -eq "gpm-error") {
            $color = "d73a4a"
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

function New-ErrorReportBody($message) {
    $activeGhUser = $null

    try {
        if (Command-Exists "gh") {
            $activeGhUser = Get-ActiveGitHubUser
        }
    }
    catch {
        $activeGhUser = $null
    }

    $windowsUser = $env:USERNAME

    if (![string]::IsNullOrWhiteSpace($env:USERDOMAIN)) {
        $windowsUser = "$env:USERDOMAIN\$env:USERNAME"
    }

    $lines = @(
        "## Hata Raporu",
        "",
        "- Tarih: $((Get-Date).ToString("s"))",
        "- UTC: $((Get-Date).ToUniversalTime().ToString("s"))Z",
        "- Uygulama surumu: $AppVersion",
        "- Windows kullanicisi: $windowsUser",
        "- GitHub kullanicisi: $activeGhUser",
        "- Bilgisayar: $env:COMPUTERNAME",
        "- Calisan klasor: $((Get-Location).Path)",
        "- BAT yolu: $env:BAT_FILE",
        "",
        "## Siniflandirma",
        "",
        "- Kategori: $script:CurrentErrorCategory",
        "- Imza: gpm-signature:$script:CurrentErrorSignature",
        "",
        "## Hata",
        "",
        '```text',
        ([string]$message),
        '```'
    )

    return ($lines -join [Environment]::NewLine)
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

        $category = Get-ErrorCategory $message
        $signature = Get-ErrorSignature $message $category
        $script:CurrentErrorCategory = $category
        $script:CurrentErrorSignature = $signature
        $labels = @("gpm-error", "gpm-$category", "gpm-v$AppVersion", "gpm-sig-$signature")
        $canManageLabels = Test-CanManageIssueLabels $repoFullName

        if ($canManageLabels) {
            Ensure-IssueLabels $repoFullName $labels
        }

        $safeTitleText = ([string]$message -replace "`r", " " -replace "`n", " ").Trim()

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
        [System.IO.File]::WriteAllText($bodyPath, (New-ErrorReportBody $message), [System.Text.UTF8Encoding]::new($false))

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

function Get-UpdateDownloadCandidates($manifest, $manifestUrl) {
    $fileInfo = $manifest.files.managerBat
    $candidates = New-Object System.Collections.ArrayList
    $seen = @{}

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
        Add-Candidate "url" "https://raw.githubusercontent.com/$repoFullName/main/github-pages-manager.bat" "Uyumluluk root URL"
    }

    $adminRoot = Get-LocalAdminReleaseRoot

    if (Test-Path $adminRoot) {
        if (![string]::IsNullOrWhiteSpace($artifactPath)) {
            Add-Candidate "file" (Join-Path $adminRoot ($artifactPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)) "Yerel admin versioned release"
        }

        if (![string]::IsNullOrWhiteSpace($fileInfo.name)) {
            Add-Candidate "file" (Join-Path (Join-Path $adminRoot "releases") $fileInfo.name) "Yerel admin release adi"
        }

        Add-Candidate "file" (Join-Path $adminRoot "github-pages-manager.bat") "Yerel admin root BAT"
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

function Test-IsNewerVersion($latestVersion, $currentVersion) {
    if ([string]::IsNullOrWhiteSpace($latestVersion) -or [string]::IsNullOrWhiteSpace($currentVersion)) {
        return $false
    }

    if ($latestVersion -eq $currentVersion) {
        return $false
    }

    try {
        return ([version]$latestVersion) -gt ([version]$currentVersion)
    }
    catch {
        return $latestVersion -ne $currentVersion
    }
}

function Start-SelfUpdate($manifest, $manifestUrl) {
    $fileInfo = $manifest.files.managerBat

    if ($null -eq $fileInfo) {
        throw "Manifest icinde indirilecek BAT bilgisi yok."
    }

    $updatesDir = Join-Path $StoreDir "updates"
    $backupDir = Join-Path $StoreDir "backups"

    New-Item -ItemType Directory -Path $updatesDir -Force | Out-Null
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    $versionSafe = ($manifest.version -replace '[^A-Za-z0-9._-]', '-')
    $downloadPath = Join-Path $updatesDir "github-pages-manager-$versionSafe.bat"
    $updaterPath = Join-Path $updatesDir "apply-update.ps1"
    $backupPath = Join-Path $backupDir "github-pages-manager-$AppVersion-$(Get-Date -Format 'yyyyMMdd-HHmmss').bat"

    Write-Host ""
    Write-StatusInfo "Yeni surum indiriliyor..."

    $candidates = @(Get-UpdateDownloadCandidates $manifest $manifestUrl)

    if ($candidates.Count -eq 0) {
        throw "Manifest icinde denenebilecek indirme kaynagi yok."
    }

    $verified = $false
    $failures = @()
    $attempt = 0
    $expectedHash = ""
    $expectedSize = ""

    if (![string]::IsNullOrWhiteSpace($fileInfo.sha256)) {
        $expectedHash = $fileInfo.sha256.ToLowerInvariant()
    }

    if ($null -ne $fileInfo.sizeBytes -and [int64]$fileInfo.sizeBytes -gt 0) {
        $expectedSize = [string]([int64]$fileInfo.sizeBytes)
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
    $updaterScript = @'
param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Target,
    [Parameter(Mandatory=$true)][string]$Backup,
    [Parameter(Mandatory=$true)][int]$ParentPid
)

$ErrorActionPreference = "Stop"

try {
    Wait-Process -Id $ParentPid -ErrorAction SilentlyContinue -Timeout 20
}
catch {
}

Start-Sleep -Seconds 2

$backupDir = Split-Path -Parent $Backup

if (!(Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
}

if (Test-Path $Target) {
    Copy-Item -LiteralPath $Target -Destination $Backup -Force
}

Copy-Item -LiteralPath $Source -Destination $Target -Force
Remove-Item -LiteralPath $Source -Force -ErrorAction SilentlyContinue

Start-Process -FilePath $Target -WorkingDirectory (Split-Path -Parent $Target)
'@

    [System.IO.File]::WriteAllText($updaterPath, $updaterScript, [System.Text.UTF8Encoding]::new($false))

    Write-StatusOk "Guncelleme indirildi ve dogrulandi."
    Write-StatusInfo "Uygulama guncellenip yeniden baslatilacak..."

    Start-Process powershell -WindowStyle Hidden -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $updaterPath,
        "-Source", $downloadPath,
        "-Target", $targetPath,
        "-Backup", $backupPath,
        "-ParentPid", $PID
    )

    exit 0
}

function Show-UpdatePrompt($manifest, $manifestSourceUrl) {
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

    if (!(Test-IsNewerVersion $manifest.version $AppVersion)) {
        return
    }

    Header
    Write-BoxMessage "update available" "Yeni guncelleme bulundu." "Cyan"
    Write-ThemeValue "mevcut" $AppVersion
    Write-ThemeValue "yeni" $manifest.version
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
            Show-UpdatePrompt $cache.Manifest $cache.SourceUrl
            return
        }

        $manifest = Get-LocalAdminManifest

        if ($null -ne $manifest) {
            Show-UpdatePrompt $manifest $manifestUrl
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
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

function Install-Tool($id, $label) {
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

    $items = @($items | Where-Object {
        $_.FullName -ne $record.FullName -and $_.LocalPath -ne $record.LocalPath
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
        $_.FullName -ne $fullName
    })

    Save-Db $items
}

function Get-SafeRepoName {
    $folderName = Split-Path -Leaf (Get-Location)
    $safe = $folderName -replace '[^A-Za-z0-9._-]', '-'
    $safe = $safe -replace '-+', '-'
    $safe = $safe.Trim([char[]]"-.")
    $safe = $safe.ToLowerInvariant()

    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = "demo-site"
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
        New-Item -ItemType Directory -Path $stagingPath -Force | Out-Null
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

        if ($item.PSIsContainer) {
            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
            Copy-PublishTree $item.FullName $targetPath $baseRoot
        }
        else {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            Copy-Item -LiteralPath $item.FullName -Destination $targetPath -Force
        }
    }
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
    return
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

        $currentName = (& git config user.name 2>$null)
        if ([string]::IsNullOrWhiteSpace($currentName)) {
            & git config user.name $script:GhUser
        }

        $currentEmail = (& git config user.email 2>$null)
        if ([string]::IsNullOrWhiteSpace($currentEmail)) {
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

    try {
        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            if ($attempt -gt 1) {
                Write-Host ""
                Write-StatusInfo "$label tekrar deneniyor ($attempt/$maxAttempts)..."
            }

            & git @argsList 2>&1 | ForEach-Object {
                Write-Host $_.ToString()
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

        $pushCode = Invoke-GitWithRetry -argsList @("push", "-u", "origin", "main") -label "Normal push" -maxAttempts 3 -delaySeconds 5

        if ($pushCode -ne 0) {
            Write-BoxMessage "push warning" "Normal push basarisiz oldu. Sebep genelde GitHub reposunda daha once farkli dosyalar olmasidir." "Yellow"
            $force = Read-Host "Uzak repoyu bu klasorle ezmek icin EVET yaz, iptal icin ENTER"

            if ($force -eq "EVET") {
                $forcePushCode = Invoke-GitWithRetry -argsList @("push", "-u", "origin", "main", "--force") -label "Force push" -maxAttempts 3 -delaySeconds 5

                if ($forcePushCode -ne 0) {
                    throw "Force push da basarisiz oldu."
                }
            }
            else {
                throw "Push iptal edildi."
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

        $repoName = $repoName -replace '[^A-Za-z0-9._-]', '-'
        $repoName = $repoName -replace '-+', '-'
        $repoName = $repoName.Trim([char[]]"-.")
        $fullName = "$script:GhUser/$repoName"
    }

    $split = Split-FullRepoName $fullName
    $owner = $split.Owner
    $repoName = $split.Repo
    $siteUrl = "https://$owner.github.io/$repoName/"
    $repoUrl = "https://github.com/$fullName"

    Write-Host ""
    Write-ThemeValue "repo" $fullName
    Write-ThemeValue "site" $siteUrl
    Write-BoxMessage "clean mode" "Proje klasoru temiz kalacak; Git islemleri uygulama staging klasorunde yapiliyor." "Cyan"
    Write-Host ""

    $worktreePath = Get-RepoWorktreePath $fullName

    $earlyRecord = [PSCustomObject]@{
        FullName = $fullName
        Owner = $owner
        RepoName = $repoName
        LocalPath = $currentPath
        WorktreePath = $worktreePath
        SiteUrl = $siteUrl
        RepoUrl = $repoUrl
        UpdatedAt = (Get-Date).ToString("s")
    }

    Write-StatusInfo "Repo kaydi yaziliyor..."
    Upsert-Record $earlyRecord

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

    Sync-ProjectToStaging $currentPath $worktreePath
    Ensure-GitRepo $fullName $worktreePath
    Commit-And-Push $worktreePath
    Enable-Pages $owner $repoName

    $finalRecord = [PSCustomObject]@{
        FullName = $fullName
        Owner = $owner
        RepoName = $repoName
        LocalPath = $currentPath
        WorktreePath = $worktreePath
        SiteUrl = $siteUrl
        RepoUrl = $repoUrl
        UpdatedAt = (Get-Date).ToString("s")
    }

    Upsert-Record $finalRecord

    Write-BoxMessage "publish complete" "Yayin / guncelleme tamamlandi." "Green"
    Write-ThemeValue "repo" $repoUrl
    Write-ThemeValue "site" $siteUrl
    Write-ThemeValue "kayit" $DbPath
    Write-StatusInfo "Ilk yayin bazen 1-3 dakika gec acilabilir."

    After-Publish $siteUrl
}

function Remove-LocalMap-IfMatches($record) {
    return
}

function Delete-GitHubRepo($record) {
    Header

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
    Remove-StagingForRecord $record

    Write-Host ""
    Write-BoxMessage "deleted" "Repo GitHub'dan silindi ve kayittan kaldirildi." "Green"
    Pause-Back
    return $true
}

function Remove-OnlyRecord($record) {
    Remove-Record $record.FullName
    Remove-StagingForRecord $record

    Write-Host ""
    Write-BoxMessage "record removed" "Kayit kaldirildi. GitHub reposuna dokunulmadi." "Green"
    Pause-Back
    return $true
}

function Repo-Options($record) {
    while ($true) {
        if ($script:ReturnToMain) {
            return
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
                Start-Process $record.SiteUrl
                continue
            }
            "2" {
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
    while ($true) {
        if ($script:ReturnToMain) {
            return
        }

        Header

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

try {
    Ensure-Storage
    Check-ForUpdates
    Ensure-Tools
    Ensure-GitHubAuth
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
    Write-ThemeValue "github" $script:GhUser
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
