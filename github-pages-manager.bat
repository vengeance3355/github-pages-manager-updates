@echo off
setlocal
cd /d "%~dp0"
set "BAT_FILE=%~f0"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$file=$env:BAT_FILE; $marker='### POWERSHELL ###'; $lines=Get-Content -LiteralPath $file; $idx=[Array]::IndexOf($lines,$marker); if($idx -lt 0){Write-Error 'PowerShell bolumu bulunamadi.'; exit 1}; $code=($lines[($idx+1)..($lines.Count-1)] -join [Environment]::NewLine); Invoke-Expression $code"

exit /b %ERRORLEVEL%

### POWERSHELL ###

$ErrorActionPreference = "Stop"

$AppVersion = "1.0.0"
$UpdateManifestUrl = "https://raw.githubusercontent.com/vengeance3355/github-pages-manager-updates/main/latest.json"
$StoreDir = Join-Path $env:APPDATA "GithubPagesPublisher"
$DbPath = Join-Path $StoreDir "repos.json"
$UpdateStatePath = Join-Path $StoreDir "update-state.json"
$AdminConfigPath = Join-Path $env:APPDATA "GithubPagesPublisherAdmin\admin.json"
$LocalMapFile = ".gh-pages-publisher.json"
$script:ReturnToMain = $false
$script:GhUser = $null
$script:LastOpenedDeviceLoginUrl = $null

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
    Write-Host "===================================================="
    Write-Host " GitHub Pages Manager"
    Write-Host "===================================================="
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
    Write-Host "1) Ana menu"
    Write-Host "2) Kapat"
    Write-Host ""

    $choice = Read-KeyChoice @("1", "2")

    if ($choice -eq "2") {
        exit 0
    }

    $script:ReturnToMain = $true
}

function After-Publish($siteUrl) {
    Write-Host ""
    Write-Host "1) Ana menu"
    Write-Host "2) Kapat"
    Write-Host "3) Siteyi ac"
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
    Write-Host "0) Geri"
    Write-Host ""

    Read-KeyChoice @("0") | Out-Null
}

function Show-Error($message) {
    Write-Host ""
    Write-Host "[HATA]"
    Write-Host $message
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

        $response = Invoke-RestMethod -Uri $uri.Uri.AbsoluteUri -Headers $headers -UseBasicParsing

        if ($response -is [string]) {
            return ($response | ConvertFrom-Json)
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
                --header "User-Agent: GitHubPagesManager" `
                --header "Cache-Control: no-cache" `
                $url 2>&1
            $curlCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $oldCurlPreference
        }

        if ($curlCode -eq 0 -and ![string]::IsNullOrWhiteSpace(($curlOutput -join [Environment]::NewLine))) {
            return (($curlOutput -join [Environment]::NewLine) | ConvertFrom-Json)
        }

        throw "URL okunamadi. PowerShell: $lastError Curl: $($curlOutput -join [Environment]::NewLine)"
    }

    throw "URL okunamadi. PowerShell: $lastError"
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

function Load-UpdateState {
    if (!(Test-Path $UpdateStatePath)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $UpdateStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
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

function Save-SkippedUpdateVersion($version) {
    Ensure-Storage

    $state = [PSCustomObject]@{
        SkippedVersion = $version
        SkippedAt = (Get-Date).ToString("s")
    }

    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $UpdateStatePath -Encoding UTF8
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

    if ($null -eq $fileInfo -or [string]::IsNullOrWhiteSpace($fileInfo.downloadUrl)) {
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
    Write-Host "[INFO] Yeni surum indiriliyor..."
    Invoke-WebRequest -Uri $fileInfo.downloadUrl -OutFile $downloadPath -UseBasicParsing

    if (![string]::IsNullOrWhiteSpace($fileInfo.sha256)) {
        $downloadHash = (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash.ToLowerInvariant()

        if ($downloadHash -ne $fileInfo.sha256.ToLowerInvariant()) {
            Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
            throw "Indirilen dosyanin SHA256 dogrulamasi basarisiz."
        }
    }

    if ($null -ne $fileInfo.sizeBytes -and [int64]$fileInfo.sizeBytes -gt 0) {
        $downloadSize = (Get-Item -LiteralPath $downloadPath).Length

        if ($downloadSize -ne [int64]$fileInfo.sizeBytes) {
            Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
            throw "Indirilen dosyanin boyutu manifest ile uyusmuyor."
        }
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

    Write-Host "[OK] Guncelleme indirildi ve dogrulandi."
    Write-Host "[INFO] Uygulama guncellenip yeniden baslatilacak..."

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

function Check-ForUpdates {
    $manifestUrl = Get-EffectiveUpdateManifestUrl

    if ([string]::IsNullOrWhiteSpace($manifestUrl)) {
        return
    }

    try {
        $manifest = Invoke-JsonUrl $manifestUrl
    }
    catch {
        $manifest = Get-LocalAdminManifest

        if ($null -eq $manifest) {
            return
        }
    }

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

    $state = Load-UpdateState

    if ($null -ne $state -and $state.SkippedVersion -eq $manifest.version) {
        return
    }

    Header
    Write-Host "Yeni guncelleme bulundu."
    Write-Host ""
    Write-Host "Mevcut surum: $AppVersion"
    Write-Host "Yeni surum: $($manifest.version)"
    Write-Host ""
    Write-Host "Guncelleme notlari:"

    if ($manifestNotes.Count -eq 0) {
        Write-Host "- Not yok."
    }
    else {
        foreach ($note in $manifestNotes) {
            Write-Host "- $note"
        }
    }

    Write-Host ""
    Write-Host "1) Guncelle"
    Write-Host "2) Bu surumu atla"
    Write-Host "3) Simdilik gec"
    Write-Host ""
    Write-Host "Secim:"

    $choice = Read-KeyChoice @("1", "2", "3")

    if ($choice -eq "2") {
        Save-SkippedUpdateVersion $manifest.version
        return
    }

    if ($choice -eq "3") {
        return
    }

    try {
        Start-SelfUpdate $manifest $manifestUrl
    }
    catch {
        Show-Error $_.Exception.Message
        Pause-Back
    }
}

function Show-UpdateNotes {
    Header

    $manifestUrl = Get-EffectiveUpdateManifestUrl

    if ([string]::IsNullOrWhiteSpace($manifestUrl)) {
        Write-Host "Guncelleme kaynagi henuz ayarlanmamis."
        Write-Host ""
        Write-Host "Admin BAT ile ilk yayin yapildiktan sonra bu bolum aktif olur."
        Pause-Back
        return
    }

    Write-Host "Guncelleme manifesti:"
    Write-Host $manifestUrl
    Write-Host ""

    try {
        $manifest = Invoke-JsonUrl $manifestUrl
    }
    catch {
        $remoteError = $_.Exception.Message
        $manifest = Get-LocalAdminManifest

        if ($null -eq $manifest) {
            Write-Host "[HATA] Guncelleme notlari okunamadi."
            Write-Host $remoteError
            Pause-Back
            return
        }

        Write-Host "[UYARI] GitHub manifesti okunamadi. Yerel son kopya gosteriliyor."
        Write-Host ""
    }

    $localManifest = Get-LocalAdminManifest

    if ([string]::IsNullOrWhiteSpace($manifest.version) -and $null -ne $localManifest) {
        $manifest = $localManifest
        Write-Host "[UYARI] GitHub manifesti beklenen formatta degil. Yerel son kopya gosteriliyor."
        Write-Host ""
    }

    $notes = @(Get-ManifestNotes $manifest)

    if ($notes.Count -eq 0 -and $null -ne $localManifest -and $localManifest.version -eq $manifest.version) {
        $manifest = $localManifest
        $notes = @(Get-ManifestNotes $manifest)
        Write-Host "[UYARI] GitHub manifestinde not yok. Yerel son notlar gosteriliyor."
        Write-Host ""
    }

    Write-Host "Mevcut uygulama surumu: $AppVersion"
    Write-Host "Yayindaki son surum: $($manifest.version)"

    if (![string]::IsNullOrWhiteSpace($manifest.publishedAt)) {
        Write-Host "Yayin zamani: $($manifest.publishedAt)"
    }

    Write-Host ""
    Write-Host "Guncelleme notlari:"

    if ($notes.Count -eq 0) {
        Write-Host "- Not yok."
    }
    else {
        foreach ($note in $notes) {
            Write-Host "- $note"
        }
    }

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
            Write-Host "[OK] GitHub giris kodu panoya kopyalandi: $code"
        }
        catch {
            Write-Host "[UYARI] GitHub giris kodu panoya kopyalanamadi:"
            Write-Host $code
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
            Write-Host "[INFO] GitHub device login sayfasi tarayicida aciliyor..."

            try {
                Start-Process $url
            }
            catch {
                Write-Host "[UYARI] Tarayici otomatik acilamadi. Linki elle ac:"
                Write-Host $url
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
            Write-Host "[INFO] $label tekrar deneniyor ($attempt/$maxAttempts)..."
        }

        $result = Invoke-GhInteractiveResult $argsList

        if ($result.Code -eq 0) {
            return $result
        }

        if ($attempt -lt $maxAttempts) {
            $waitSeconds = $delaySeconds * $attempt
            Write-Host ""
            Write-Host "[UYARI] $label basarisiz oldu. $waitSeconds saniye sonra tekrar denenecek..."
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
        Write-Host "[HATA] Beklenen GitHub kullanicisi belirlenemedi."
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
    Write-Host "GitHub CLI hesap kaydi onariliyor."
    Write-Host ""
    Write-Host "Beklenen repo sahibi:"
    Write-Host $expectedOwner
    Write-Host ""

    if ($null -ne $mismatch) {
        Write-Host "Algilanan eski / hatali kayit:"
        Write-Host $mismatch.OldUser
        Write-Host ""
        Write-Host "Tarayicidan gelen hesap:"
        Write-Host $mismatch.NewUser
        Write-Host ""
    }

    if ($storedUsers.Count -gt 0) {
        Write-Host "GitHub CLI'da gorunen hesaplar:"
        foreach ($user in $storedUsers) {
            Write-Host "- $user"
        }
        Write-Host ""
    }

    foreach ($user in $usersToLogout) {
        Write-Host "[INFO] Eski / uyumsuz GitHub CLI kaydi temizleniyor: $user"
        Invoke-GhSilent @("auth", "logout", "--hostname", "github.com", "--user", $user, "--yes") | Out-Null
    }

    Write-Host ""
    Write-Host "[INFO] GitHub girisi yenilenecek."
    Write-Host "Tarayicida su repo sahibi hesapla onay ver:"
    Write-Host $expectedOwner
    Write-Host ""

    $loginResult = Invoke-GhInteractiveResult @("auth", "login", "--hostname", "github.com", "--web", "--git-protocol", "https", "--scopes", "repo,delete_repo")

    if ($loginResult.Code -ne 0) {
        $existingSwitch = Invoke-GhSilent @("auth", "switch", "--hostname", "github.com", "--user", $expectedOwner)

        if ($existingSwitch.Code -ne 0) {
            Write-Host ""
            Write-Host "[HATA] GitHub girisi yenilenemedi."
            Write-Host $loginResult.Output
            return $false
        }
    }

    $activeAfterLogin = Get-ActiveGitHubUser

    if ($activeAfterLogin -ne $expectedOwner) {
        if (![string]::IsNullOrWhiteSpace($activeAfterLogin)) {
            Write-Host ""
            Write-Host "[INFO] Yanlis hesapla giris algilandi, kayit temizleniyor: $activeAfterLogin"
            Invoke-GhSilent @("auth", "logout", "--hostname", "github.com", "--user", $activeAfterLogin, "--yes") | Out-Null
        }

        Write-Host ""
        Write-Host "[HATA] Yanlis GitHub hesabi ile izin verildi."
        Write-Host ""
        Write-Host "Beklenen hesap:"
        Write-Host $expectedOwner
        Write-Host ""
        Write-Host "Algilanan hesap:"
        if ([string]::IsNullOrWhiteSpace($activeAfterLogin)) {
            Write-Host "Bilinmiyor"
        }
        else {
            Write-Host $activeAfterLogin
        }
        return $false
    }

    $switchResult = Invoke-GhSilent @("auth", "switch", "--hostname", "github.com", "--user", $expectedOwner)

    if ($switchResult.Code -ne 0) {
        Write-Host ""
        Write-Host "[HATA] GitHub CLI beklenen hesaba gecemedi."
        Write-Host $switchResult.Output
        return $false
    }

    if (Test-GhHasScope "delete_repo") {
        Write-Host ""
        Write-Host "[OK] delete_repo yetkisi mevcut."
    }
    else {
        Write-Host ""
        Write-Host "[INFO] delete_repo yetkisi yenileniyor..."
        $refreshResult = Invoke-GhInteractiveResult @("auth", "refresh", "--hostname", "github.com", "-s", "delete_repo")

        if ($refreshResult.Code -ne 0) {
            Write-Host ""
            Write-Host "[HATA] delete_repo yetkisi otomatik yenilenemedi."
            Write-Host $refreshResult.Output
            return $false
        }
    }

    $setupGit = Invoke-GhSilent @("auth", "setup-git")

    if ($setupGit.Code -ne 0) {
        Write-Host ""
        Write-Host "[UYARI] gh auth setup-git tamamlanamadi."
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

    Write-Host "GitHub hesap uyusmazligi var."
    Write-Host ""
    Write-Host "Silinecek repo sahibi:"
    Write-Host $owner
    Write-Host ""
    Write-Host "GitHub CLI aktif hesabi:"
    if ([string]::IsNullOrWhiteSpace($active)) {
        Write-Host "Bilinmiyor / giris yok"
    }
    else {
        Write-Host $active
    }
    Write-Host ""
    Write-Host "Bu repoyu silmek icin GitHub CLI'da repo sahibi hesapla giris yapman gerekiyor."
    Write-Host ""
    Write-Host "1) Bu hesapla giris yap / yeniden yetkilendir"
    Write-Host "0) Geri"
    Write-Host ""
    Write-Host "Secim:"

    $choice = Read-KeyChoice @("1", "0")

    if ($choice -eq "0") {
        return $false
    }

    Header
    Write-Host "Tarayici acilacak."
    Write-Host ""
    Write-Host "Onemli:"
    Write-Host "Tarayicida su GitHub hesabiyla giris yap:"
    Write-Host $owner
    Write-Host ""
    Write-Host "Farkli hesapla izin verirsen GitHub yine hata verir."
    Write-Host ""

    $loginCode = Invoke-GhInteractive @("auth", "login", "--hostname", "github.com", "--web", "--git-protocol", "https", "--scopes", "repo,delete_repo")

    if ($loginCode -ne 0) {
        Write-Host ""
        Write-Host "[HATA] GitHub girisi tamamlanamadi."
        Pause-Back
        return $false
    }

    $switchAgain = Invoke-GhSilent @("auth", "switch", "--hostname", "github.com", "--user", $owner)

    if ($switchAgain.Code -ne 0) {
        Write-Host ""
        Write-Host "[HATA] GitHub CLI hala $owner hesabina gecemiyor."
        Write-Host ""
        Write-Host "Sebep genelde tarayicida farkli hesapla izin verilmesi."
        Write-Host "GitHub'dan cikis yapip $owner hesabi ile tekrar dene."
        Pause-Back
        return $false
    }

    $activeAfterLogin = Get-ActiveGitHubUser

    if ($activeAfterLogin -ne $owner) {
        Write-Host ""
        Write-Host "[HATA] Yanlis hesap aktif."
        Write-Host ""
        Write-Host "Beklenen hesap:"
        Write-Host $owner
        Write-Host ""
        Write-Host "Aktif hesap:"
        Write-Host $activeAfterLogin
        Write-Host ""
        Write-Host "Tarayicida dogru GitHub hesabina gecip tekrar dene."
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

    Write-Host "[INFO] $label bulunamadi. Winget ile kuruluyor..."
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
        Write-Host ""
        Write-Host "[INFO] GitHub girisi yok."
        Write-Host "[INFO] Tarayici acilacak. GitHub izin ekraninda onay ver."
        Write-Host ""

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
        Write-Host "[UYARI] Kayit dosyasi okunamadi. Sifirlaniyor."
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
    Write-Host "[OK] Repo kayda yazildi:"
    Write-Host $DbPath
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

function Ensure-GitIgnore {
    $gitignorePath = ".gitignore"
    $batName = Split-Path -Leaf $env:BAT_FILE

    $linesToAdd = @(
        $LocalMapFile,
        $batName,
        "github-pages-update-admin.bat",
        "node_modules/",
        ".env",
        ".env.*",
        "*.log",
        ".DS_Store",
        "Thumbs.db"
    )

    if (!(Test-Path $gitignorePath)) {
        New-Item -ItemType File -Path $gitignorePath | Out-Null
    }

    $existing = @(Get-Content -LiteralPath $gitignorePath -ErrorAction SilentlyContinue)

    foreach ($line in $linesToAdd) {
        if ($existing -notcontains $line) {
            Add-Content -LiteralPath $gitignorePath -Value $line
        }
    }
}

function Save-LocalMap($fullName, $repoName, $siteUrl) {
    $map = [PSCustomObject]@{
        FullName = $fullName
        RepoName = $repoName
        SiteUrl = $siteUrl
        SavedAt = (Get-Date).ToString("s")
    }

    $map | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $LocalMapFile -Encoding UTF8
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

function Ensure-GitRepo($fullName) {
    if (!(Test-Path ".git")) {
        Write-Host "[INFO] Git repo baslatiliyor..."
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

    & git remote remove origin 2>$null
    & git remote add origin $remoteUrl

    if ($LASTEXITCODE -ne 0) {
        throw "Git remote ayarlanamadi."
    }
}

function Enable-Pages($owner, $repo) {
    Write-Host "[INFO] GitHub Pages aktif ediliyor..."

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
            Write-Host "[UYARI] Pages ayari otomatik tamamlanamadi."
            Write-Host "Repo yuklendi ama Pages'i GitHub ayarlarindan manuel acman gerekebilir."
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
                Write-Host "[INFO] $label tekrar deneniyor ($attempt/$maxAttempts)..."
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
                Write-Host "[UYARI] $label basarisiz oldu. $waitSeconds saniye sonra tekrar denenecek..."
                Start-Sleep -Seconds $waitSeconds
            }
        }

        return $code
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }
}

function Commit-And-Push {
    Write-Host "[INFO] Dosyalar commitleniyor..."

    & git add .

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
        Write-Host "[INFO] Yeni commitlenecek degisiklik yok."
    }

    Write-Host "[INFO] GitHub'a yukleniyor..."

    $pushCode = Invoke-GitWithRetry -argsList @("push", "-u", "origin", "main") -label "Normal push" -maxAttempts 3 -delaySeconds 5

    if ($pushCode -ne 0) {
        Write-Host ""
        Write-Host "[UYARI] Normal push basarisiz oldu."
        Write-Host "Sebep genelde GitHub reposunda daha once farkli dosyalar olmasidir."
        Write-Host ""
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

function Publish-CurrentFolder {
    Header

    if (!(Test-Path "index.html")) {
        Write-Host "[HATA] Bu klasorde index.html yok."
        Write-Host "BAT dosyasini yayina almak istedigin sitenin ana klasorune koy."
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
        Write-Host "[OK] Bu klasor daha once repoya baglanmis: $fullName"
    }
    else {
        $existing = $db | Where-Object { $_.LocalPath -eq $currentPath } | Select-Object -First 1

        if ($null -ne $existing) {
            $fullName = $existing.FullName
            $repoName = $existing.RepoName
            Write-Host "[OK] Bu klasor kayitlarda bulundu: $fullName"
        }
    }

    if ([string]::IsNullOrWhiteSpace($fullName)) {
        $defaultRepo = Get-SafeRepoName

        Write-Host "Bu klasor henuz bir GitHub reposuna bagli degil."
        Write-Host "Otomatik repo adi: $defaultRepo"
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
    Write-Host "Kullanilacak repo: $fullName"
    Write-Host "Site linki: $siteUrl"
    Write-Host ""

    $earlyRecord = [PSCustomObject]@{
        FullName = $fullName
        Owner = $owner
        RepoName = $repoName
        LocalPath = $currentPath
        SiteUrl = $siteUrl
        RepoUrl = $repoUrl
        UpdatedAt = (Get-Date).ToString("s")
    }

    Write-Host "[INFO] Repo kaydi yaziliyor..."
    Upsert-Record $earlyRecord

    $writtenCheck = [System.IO.File]::ReadAllText($DbPath)

    if ([string]::IsNullOrWhiteSpace($writtenCheck) -or $writtenCheck.Trim() -eq "[]") {
        throw "Kayit yazilamadi. repos.json hala bos: $DbPath"
    }

    Write-Host "[OK] Kayit dosyasi dolu."
    Write-Host $DbPath
    Write-Host ""

    $repoView = Invoke-GhSilent @("repo", "view", $fullName)
    $repoExists = $repoView.Code -eq 0

    if (!$repoExists) {
        Write-Host "[INFO] GitHub reposu yok. Olusturuluyor..."

        $createResult = Invoke-GhInteractiveWithRetry -argsList @("repo", "create", $fullName, "--public") -label "GitHub reposu olusturma" -maxAttempts 4 -delaySeconds 5

        if ($createResult.Code -ne 0) {
            $repoViewAfterCreate = Invoke-GhSilent @("repo", "view", $fullName)

            if ($repoViewAfterCreate.Code -ne 0) {
                throw "GitHub reposu olusturulamadi."
            }

            Write-Host "[INFO] Repo olusturma komutu hata verdi ama repo GitHub'da gorunuyor. Devam ediliyor."
        }
    }
    else {
        Write-Host "[INFO] GitHub reposu var. Guncellenecek."
    }

    Ensure-GitIgnore
    Ensure-GitRepo $fullName

    if (!(Test-Path ".nojekyll")) {
        New-Item -ItemType File -Path ".nojekyll" | Out-Null
    }

    Commit-And-Push
    Enable-Pages $owner $repoName

    Save-LocalMap $fullName $repoName $siteUrl

    $finalRecord = [PSCustomObject]@{
        FullName = $fullName
        Owner = $owner
        RepoName = $repoName
        LocalPath = $currentPath
        SiteUrl = $siteUrl
        RepoUrl = $repoUrl
        UpdatedAt = (Get-Date).ToString("s")
    }

    Upsert-Record $finalRecord

    Write-Host ""
    Write-Host "===================================================="
    Write-Host "   YAYIN / GUNCELLEME TAMAMLANDI"
    Write-Host "===================================================="
    Write-Host ""
    Write-Host "Repo:"
    Write-Host $repoUrl
    Write-Host ""
    Write-Host "Site:"
    Write-Host $siteUrl
    Write-Host ""
    Write-Host "Kayit dosyasi:"
    Write-Host $DbPath
    Write-Host ""
    Write-Host "Not: Ilk yayin bazen 1-3 dakika gec acilabilir."

    After-Publish $siteUrl
}

function Remove-LocalMap-IfMatches($record) {
    try {
        if ($null -eq $record.LocalPath) {
            return
        }

        $mapPath = Join-Path $record.LocalPath $LocalMapFile

        if (!(Test-Path $mapPath)) {
            return
        }

        $map = Get-Content -LiteralPath $mapPath -Raw -Encoding UTF8 | ConvertFrom-Json

        if ($map.FullName -eq $record.FullName) {
            Remove-Item -LiteralPath $mapPath -Force
        }
    }
    catch {
    }
}

function Delete-GitHubRepo($record) {
    Header

    Write-Host "SECILI REPO:"
    Write-Host $record.FullName
    Write-Host ""
    Write-Host "DIKKAT: Bu islem GitHub reposunu gercekten siler."
    Write-Host "Geri almak kolay degil."
    Write-Host ""

    $confirm = Read-Host "Silmek icin repo adini aynen yaz: $($record.RepoName)"

    if ($confirm -ne $record.RepoName) {
        Write-Host ""
        Write-Host "Silme iptal edildi."
        Pause-Back
        return $false
    }

    $authOk = Ensure-OwnerAuth $record.Owner

    if (!$authOk) {
        return $false
    }

    Header

    Write-Host "SECILI REPO:"
    Write-Host $record.FullName
    Write-Host ""
    Write-Host "[INFO] Silme yetkisi kontrol ediliyor..."

    if (Test-GhHasScope "delete_repo") {
        Write-Host "[OK] delete_repo yetkisi zaten var."
    }
    else {
        $refreshResult = Invoke-GhInteractiveResult @("auth", "refresh", "--hostname", "github.com", "-s", "delete_repo")

        if ($refreshResult.Code -ne 0) {
            $repairOk = Repair-GhAuthForOwner $record.Owner $refreshResult.Output

            if (!$repairOk) {
                Write-Host ""
                Write-Host "[HATA] delete_repo yetkisi alinamadi."
                Write-Host ""
                Write-Host "Beklenen hesap:"
                Write-Host $record.Owner
                Pause-Back
                return $false
            }

            Header

            Write-Host "SECILI REPO:"
            Write-Host $record.FullName
            Write-Host ""
            Write-Host "[OK] GitHub CLI hesap kaydi ve silme yetkisi onarildi."
            Write-Host ""
        }
    }

    Write-Host "[INFO] GitHub reposu siliniyor..."

    $deleteCode = Invoke-GhInteractive @("repo", "delete", $record.FullName, "--yes")

    if ($deleteCode -ne 0) {
        Write-Host "[HATA] Repo silinemedi."
        Pause-Back
        return $false
    }

    Remove-Record $record.FullName
    Remove-LocalMap-IfMatches $record

    Write-Host ""
    Write-Host "[OK] Repo GitHub'dan silindi ve kayittan kaldirildi."
    Pause-Back
    return $true
}

function Remove-OnlyRecord($record) {
    Remove-Record $record.FullName
    Remove-LocalMap-IfMatches $record

    Write-Host ""
    Write-Host "[OK] Kayit kaldirildi. GitHub reposuna dokunulmadi."
    Pause-Back
    return $true
}

function Repo-Options($record) {
    while ($true) {
        if ($script:ReturnToMain) {
            return
        }

        Header

        Write-Host "Secili repo:"
        Write-Host $record.FullName
        Write-Host ""
        Write-Host "Site:"
        Write-Host $record.SiteUrl
        Write-Host ""
        Write-Host "Yerel klasor:"
        Write-Host $record.LocalPath
        Write-Host ""
        Write-Host "1) Siteyi ac"
        Write-Host "2) GitHub repo sayfasini ac"
        Write-Host "3) GitHub'dan sil ve kayittan kaldir"
        Write-Host "4) Sadece kayittan kaldir"
        Write-Host "8) Ana menu"
        Write-Host "0) Geri"
        Write-Host ""
        Write-Host "Secim:"

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
            Write-Host "Kayitli repo yok."
            Write-Host ""
            Write-Host "Kayit dosyasi:"
            Write-Host $DbPath
            Write-Host ""
            Write-Host "0) Geri"
            Write-Host ""
            Write-Host "Secim:"

            $choice = Read-KeyChoice @("0")
            return
        }

        Write-Host "Kayitli repolar:"
        Write-Host ""

        for ($i = 0; $i -lt $items.Count; $i++) {
            $n = $i + 1
            Write-Host "$n) $($items[$i].FullName)"
            Write-Host " Site: $($items[$i].SiteUrl)"
            Write-Host " Klasor: $($items[$i].LocalPath)"
            Write-Host ""
        }

        Write-Host "0) Geri"
        Write-Host ""
        Write-Host "Repo numarasi sec:"

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
    Write-Host "2) Kapat"
    Write-Host ""
    Read-KeyChoice @("2") | Out-Null
    exit 1
}

while ($true) {
    $script:ReturnToMain = $false

    Header

    Write-Host "Uygulama surumu: $AppVersion"
    Write-Host ""
    Write-Host "GitHub kullanicisi: $script:GhUser"
    Write-Host "Calisan klasor:"
    Write-Host (Get-Location).Path
    Write-Host ""
    Write-Host "Kayit dosyasi:"
    Write-Host $DbPath
    Write-Host ""
    Write-Host "1) Kayitli repolar"
    Write-Host "2) Kaydet/Guncelle - bu klasoru GitHub Pages'e yayinla"
    Write-Host "3) Guncelleme notlari"
    Write-Host "4) Cikis"
    Write-Host ""
    Write-Host "Secim:"

    $mainChoice = Read-KeyChoice @("1", "2", "3", "4")

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
            exit 0
        }
    }
}
