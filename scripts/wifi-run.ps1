<#
.SYNOPSIS
    One-shot wireless debugging + flutter run for the Aumazing main app.

.DESCRIPTION
    Connects the phone over Wi-Fi (reusing the last known IP if it still works),
    falling back to a USB cable to flip the device into TCP/IP mode, then runs
    `flutter run` against it.

    First run of the day: plug the phone in with USB debugging on. After that
    you can unplug and run this with no cable at all, as long as the phone
    stays on the same Wi-Fi and hasn't rebooted.

.PARAMETER Port
    adb TCP port. 5555 is the classic `adb tcpip` port.

.PARAMETER Ip
    Skip discovery and connect straight to this IP.

.PARAMETER Release
    Build in release mode instead of debug.

.PARAMETER EnvFile
    Name of the file under apps/main_app/env to pass to --dart-define-from-file.
    Defaults to "dev" (i.e. env/dev.json). Pass "none" to skip it entirely.

.PARAMETER DevTools
    Launch with ENABLE_DEVELOPER_TOOLS=true.

.PARAMETER NoDevTools
    Launch with ENABLE_DEVELOPER_TOOLS=false.
    If neither switch is given, the script asks.

.PARAMETER Reconnect
    Ignore the cached address and re-derive it from the USB device.

.PARAMETER Apk
    Build a release APK and install it on the device (a real, standalone build
    that keeps working after the cable/Wi-Fi is gone), instead of `flutter run`.

.PARAMETER Run
    Force the `flutter run` (hot-reload) path. Default when neither -Apk nor
    -Run is given is to ask.

.PARAMETER Clean
    Run `flutter clean` (and `flutter pub get`) before building. Use when a
    build is behaving oddly / after switching branches. Slower. If not passed,
    the script asks.

.PARAMETER FreePremium
    Compile the app with all Premium feature gates unlocked for free testing or
    distribution. This is independent of the developer toolbox.

.PARAMETER PublishFree
    Produce a clean, release-signed APK with Premium unlocked and developer
    tools disabled. Does not require a phone and does not install the APK.
    Requires android/key.properties so the package cannot silently use the
    debug signing key.

.PARAMETER NoLaunch
    With -Apk: install only, don't auto-start the app afterwards.

.PARAMETER Device
    When more than one phone is found, pick the one whose serial / IP / model
    contains this text, instead of being asked. e.g. -Device CPH2711 or -Device .58

.PARAMETER NoPause
    Don't wait for a keypress before closing. Use when running inside a shell
    you already have open. By default the window stays open so you can read the
    output (and any errors) instead of it vanishing.
#>
[CmdletBinding()]
param(
    [int]$Port = 5555,
    [string]$Ip,
    [switch]$Release,
    [switch]$Reconnect,
    [string]$EnvFile = 'dev',
    [switch]$DevTools,
    [switch]$NoDevTools,
    [switch]$NoPause,
    [string]$Device,
    [switch]$Apk,
    [switch]$Run,
    [switch]$NoLaunch,
    [switch]$Clean,
    [switch]$FreePremium,
    [switch]$PublishFree
)

$ErrorActionPreference = 'Stop'

# Keep the window open on the way out so nothing scrolls past and disappears.
function Exit-Run([int]$code) {
    if ($script:__lock) {
        try { $script:__lock.ReleaseMutex() } catch { }
        $script:__lock.Dispose()
        $script:__lock = $null
    }
    if (-not $NoPause) {
        Write-Host ""
        try { Read-Host "Press Enter to close" | Out-Null } catch { }
    }
    exit $code
}

# Any terminating error lands here so you get one readable line instead of a
# red stack trace in a window that vanishes. wifi-run.cmd pauses afterwards.
trap {
    Write-Host ""
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $ln = $_.InvocationInfo.ScriptLineNumber
    if ($ln) { Write-Host "  (wifi-run.ps1 line $ln)" -ForegroundColor DarkGray }
    Exit-Run 1
}

# --- single instance -------------------------------------------------------
# A named mutex is held for the life of this process. A second launch can't
# grab it, so it bows out instead of starting a rival `flutter run`.
$script:__lock = New-Object System.Threading.Mutex($false, 'Local\Aumazing.WifiRun')
try {
    $gotLock = $script:__lock.WaitOne(0)
} catch [System.Threading.AbandonedMutexException] {
    # previous run crashed without releasing; we now own it -- carry on.
    $gotLock = $true
}
if (-not $gotLock) {
    Write-Host ""
    Write-Host "wifi-run is already running in another window." -ForegroundColor Yellow
    Write-Host "Switch to it, or close it before starting again." -ForegroundColor Yellow
    $script:__lock.Dispose()
    $script:__lock = $null
    Exit-Run 0
}

$repoRoot  = Split-Path -Parent $PSScriptRoot
$appDir    = Join-Path $repoRoot 'apps\main_app'
$cacheFile = Join-Path $env:LOCALAPPDATA 'aumazing\wifi-device.txt'

if ($PublishFree -and ($Run -or $Apk)) {
    throw "-PublishFree selects its own package mode; don't combine it with -Run or -Apk."
}
if ($PublishFree -and $DevTools) {
    throw "-PublishFree always disables developer tools; don't combine it with -DevTools."
}
if ($PublishFree -and -not (Test-Path (Join-Path $appDir 'android\key.properties'))) {
    throw "Publish build requires apps/main_app/android/key.properties for release signing."
}

$requiresDevice = -not $PublishFree

# --- locate adb -------------------------------------------------------------
if ($requiresDevice) {
$adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
if (-not $adb) {
    $candidates = @(
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "$env:ANDROID_HOME\platform-tools\adb.exe",
        "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe"
    )
    $adb = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $adb) { throw "adb.exe not found. Install Android platform-tools or set ANDROID_HOME." }

# --- Windows Developer Mode (Flutter needs it for plugin symlinks) ----------
function Test-DeveloperMode {
    $k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
    $v = (Get-ItemProperty -Path $k -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
    return ($v -eq 1)
}

if (-not (Test-DeveloperMode)) {
    Write-Host ""
    Write-Warning "Windows Developer Mode is OFF - Flutter can't build plugins without it."
    Write-Host "(Error you'd otherwise hit: 'Building with plugins requires symlink support'.)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Turn it on once, either way:" -ForegroundColor Yellow
    Write-Host "  * Settings > System > For developers > Developer Mode = On, or" -ForegroundColor Yellow
    Write-Host "  * run this in an ADMIN PowerShell:" -ForegroundColor Yellow
    Write-Host '      reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v AllowDevelopmentWithoutDevLicense /d 1' -ForegroundColor Cyan
    Write-Host ""
    try {
        $o = (Read-Host "Open the Developer settings page now? (Y/n)").Trim().ToLower()
        if ($o -eq '' -or $o -in @('y','yes')) { Start-Process 'ms-settings:developers' }
    } catch { }
    Write-Host "Flip Developer Mode on, then run this again." -ForegroundColor Yellow
    Exit-Run 1
}

# adb writes ordinary chatter to stderr, and PowerShell 5.1 turns a native
# command's stderr into an ErrorRecord -- which, under 'Stop', kills the script
# for something as harmless as "no such device". Run adb with that relaxed and
# hand back its combined output as text; callers decide what counts as failure.
function Invoke-Adb {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        (& $adb @args 2>&1 | Out-String)
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Get-AdbDevices {
    # returns objects: Serial, State
    (Invoke-Adb devices) -split "`r?`n" | Select-Object -Skip 1 | ForEach-Object {
        $line = $_.Trim()
        if ($line -match '^(\S+)\s+(\S+)$') {
            [pscustomobject]@{ Serial = $Matches[1]; State = $Matches[2] }
        }
    }
}

function Test-WirelessConnect([string]$target) {
    Write-Host "  trying $target ..." -NoNewline
    $null = Invoke-Adb connect $target
    # The wording changed across adb releases ("connected", "already
    # connected", or no useful stdout when mDNS auto-connect won the race).
    # The device table is the authoritative result, not the sentence adb used.
    $alive = Get-AdbDevices | Where-Object { $_.Serial -eq $target -and $_.State -eq 'device' }
    if ($alive) { Write-Host " ok" -ForegroundColor Green; return $true }
    Write-Host " no" -ForegroundColor DarkGray
    Invoke-Adb disconnect $target | Out-Null
    return $false
}

# A restarted adbd can return from `adb tcpip` before its Wi-Fi listener is
# routable. Polling the socket avoids two expensive `adb connect` timeouts and
# gives slower phones / access points enough time to update ARP state.
function Test-TcpEndpoint([string]$target, [int]$timeoutMs = 1000) {
    if ($target -notmatch '^(.+):(\d+)$') { return $false }
    $hostName = $Matches[1]
    $portNumber = [int]$Matches[2]
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $pending = $client.ConnectAsync($hostName, $portNumber)
        if (-not $pending.Wait($timeoutMs)) { return $false }
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Wait-TcpEndpoint([string]$target, [int]$timeoutSeconds = 20) {
    $deadline = [DateTime]::UtcNow.AddSeconds($timeoutSeconds)
    do {
        if (Test-TcpEndpoint $target) { return $true }
        Start-Sleep -Milliseconds 750
    } while ([DateTime]::UtcNow -lt $deadline)
    return $false
}

function Get-DeviceWifiIp([string]$serial) {
    foreach ($iface in @('wlan0', 'wlan1')) {
        $out = Invoke-Adb -s $serial shell "ip -f inet addr show $iface"
        if ($out -match 'inet\s+(\d+\.\d+\.\d+\.\d+)') { return $Matches[1] }
    }
    # fallback: whatever interface owns the default route
    $out = Invoke-Adb -s $serial shell "ip route"
    if ($out -match 'src\s+(\d+\.\d+\.\d+\.\d+)') { return $Matches[1] }
    return $null
}

function Get-DeviceModel([string]$serial) {
    $m = (Invoke-Adb -s $serial shell "getprop ro.product.model").Trim()
    if ($m) { return $m }
    return $serial
}

# Given a list of candidate serials, return exactly one. Auto-picks when there
# is only one (or when -Device narrows it to one); otherwise shows a menu.
function Select-Device([string]$what, [string[]]$serials) {
    $serials = @($serials | Where-Object { $_ } | Select-Object -Unique)
    if ($serials.Count -eq 0) { return $null }

    if ($Device) {
        $hit = @($serials | Where-Object { $_ -like "*$Device*" })
        if ($hit.Count -eq 1) { return $hit[0] }
        if ($hit.Count -gt 1) { $serials = $hit }   # narrowed but still ambiguous
        elseif ($hit.Count -eq 0) {
            Write-Host "  -Device '$Device' matched none of the $what devices; ignoring it." -ForegroundColor Yellow
        }
    }

    if ($serials.Count -eq 1) { return $serials[0] }

    # Build labels (model name where we can get it cheaply)
    $rows = foreach ($sn in $serials) {
        $name = if ($sn -match ':\d+$') { $sn } else { "{0}  ({1})" -f $sn, (Get-DeviceModel $sn) }
        [pscustomobject]@{ Serial = $sn; Label = $name }
    }

    Write-Host ""
    Write-Host "Found $($serials.Count) $what devices:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $rows.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $rows[$i].Label)
    }

    if ($NoPause) {
        Write-Host "  (-NoPause: using [1] $($rows[0].Label))" -ForegroundColor DarkGray
        return $rows[0].Serial
    }

    do {
        try { $pick = (Read-Host "Which one? (1-$($rows.Count), Enter = 1)").Trim() }
        catch { throw "Multiple $what devices found. Re-run with -Device <name> to choose." }
        if ($pick -eq '') { $pick = '1' }
    } while (-not ($pick -match '^\d+$') -or [int]$pick -lt 1 -or [int]$pick -gt $rows.Count)

    Write-Host ""
    return $rows[[int]$pick - 1].Serial
}

Invoke-Adb start-server | Out-Null

# --- discovery: retries until a device appears or you quit ------------------
$target = $null
$attempt = 0
while (-not $target) {
$attempt++

# --- 1. already connected wirelessly? --------------------------------------
$wireless = @(Get-AdbDevices | Where-Object { $_.State -eq 'device' -and $_.Serial -match ':\d+$' } | ForEach-Object { $_.Serial })
if ($wireless.Count -gt 0 -and -not $Reconnect -and -not $Ip) {
    $target = Select-Device 'already-connected wireless' $wireless
    Write-Host "Using wireless device: $target" -ForegroundColor Green
}

# --- 2. explicit IP, then cached IP ----------------------------------------
if (-not $target) {
    Write-Host "Looking for the phone over Wi-Fi..."
    $tries = @()
    if ($Ip)                                    { $tries += "${Ip}:$Port" }
    elseif (-not $Reconnect -and (Test-Path $cacheFile)) { $tries += (Get-Content $cacheFile -Raw).Trim() }

    foreach ($t in $tries) {
        if ($t -and (Test-WirelessConnect $t)) { $target = $t; break }
    }
}

# --- 3. mDNS discovery (Android 11+ wireless debugging, no cable needed) ----
if (-not $target) {
    Write-Host "Asking mDNS what's advertising adb on this network..."
    $mdns = Invoke-Adb mdns services
    $found = @([regex]::Matches($mdns, '_adb-tls-connect\._tcp\s+(\d+\.\d+\.\d+\.\d+:\d+)') |
        ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)

    if (-not $found) { Write-Host "  nothing advertising." -ForegroundColor DarkGray }
    else {
        # When a cable is attached, use the phone's Wi-Fi IP to identify its
        # rotating Android 11+ TLS port. This avoids asking the user to choose
        # between every other phone advertising adb on the same network.
        $usbNow = @(Get-AdbDevices | Where-Object {
            $_.State -eq 'device' -and $_.Serial -notmatch ':\d+$'
        } | ForEach-Object { $_.Serial })
        $matchingMdns = @()
        foreach ($usb in $usbNow) {
            $usbIp = Get-DeviceWifiIp $usb
            if ($usbIp) {
                $matchingMdns += @($found | Where-Object { $_ -like "${usbIp}:*" })
            }
        }
        $matchingMdns = @($matchingMdns | Select-Object -Unique)

        if ($matchingMdns.Count -eq 1) {
            $chosen = $matchingMdns[0]
            Write-Host "  matched USB phone to $chosen" -ForegroundColor DarkGray
        } else {
            $chosen = Select-Device 'advertised (mDNS)' $found
        }

        $ordered = @($chosen)
        # put the chosen one first, still try the rest if it refuses
        $ordered += @($found | Where-Object { $_ -ne $chosen })
        foreach ($t in $ordered) {
            if (Test-WirelessConnect $t) { $target = $t; break }
        }
    }
}

# --- 4. fall back to the cable ---------------------------------------------
if (-not $target) {
    $usbSerials = @(Get-AdbDevices | Where-Object { $_.State -eq 'device' -and $_.Serial -notmatch ':\d+$' } | ForEach-Object { $_.Serial })
    $usbSerial = Select-Device 'USB' $usbSerials
    if (-not $usbSerial) {
        Write-Host ""
        Write-Warning "No phone reachable over Wi-Fi and none on USB."
        Write-Host "Plug the phone in over USB with Developer options > USB debugging on" -ForegroundColor Yellow
        Write-Host "(accept the 'Allow USB debugging?' prompt), or turn on Wireless debugging." -ForegroundColor Yellow
        Write-Host "You only need the cable once per phone reboot / Wi-Fi change." -ForegroundColor Yellow
        if ($NoPause) { Exit-Run 1 }
        Write-Host ""
        $again = Read-Host "Fix that, then press Enter to look again (or Q to quit)"
        if ($again.Trim().ToLower() -in @('q', 'quit', 'n', 'no')) { Exit-Run 1 }
        Start-Sleep -Seconds 1   # let a just-enabled adb start advertising
        continue                 # retry the whole discovery loop
    }

    Write-Host "USB device $usbSerial - switching it to wireless."
    $deviceIp = Get-DeviceWifiIp $usbSerial
    if (-not $deviceIp) { throw "Could not read the phone's Wi-Fi IP. Is it on Wi-Fi (not just mobile data)?" }

    Invoke-Adb -s $usbSerial tcpip $Port | Out-Host

    $target = "${deviceIp}:$Port"
    Write-Host "  waiting for $target to become reachable ..." -NoNewline
    if (-not (Wait-TcpEndpoint $target)) {
        Write-Host " timed out" -ForegroundColor DarkGray
        throw "Phone restarted adb on $target, but Windows cannot reach that port. Check that the phone and PC are on the same non-guest Wi-Fi and that client/AP isolation is off."
    }
    Write-Host " ready" -ForegroundColor Green

    if (-not (Test-WirelessConnect $target)) {
        Start-Sleep -Seconds 1
        if (-not (Test-WirelessConnect $target)) { throw "adb connect $target failed. Same Wi-Fi network as this PC?" }
    }
}
}  # end discovery retry loop

# --- 5. remember it ---------------------------------------------------------
New-Item -ItemType Directory -Force -Path (Split-Path $cacheFile) | Out-Null
Set-Content -Path $cacheFile -Value $target -Encoding utf8

Write-Host ""
Write-Host "Connected: $target  - the cable can come out now." -ForegroundColor Green
Write-Host ""
}

# --- 6. developer tools on or off? ------------------------------------------
if ($DevTools -and $NoDevTools) { throw "Pick one of -DevTools / -NoDevTools, not both." }

if ($PublishFree)     { $enableDevTools = $false }
elseif ($DevTools)    { $enableDevTools = $true }
elseif ($NoDevTools)  { $enableDevTools = $false }
else {
    Write-Host "Developer tools (ENABLE_DEVELOPER_TOOLS)?"
    Write-Host "  [Y] on   - in-app dev menu / debug affordances"
    Write-Host "  [N] off  - behaves like a normal build"
    do {
        try {
            $answer = (Read-Host "Enable developer tools? (Y/n)").Trim().ToLower()
        } catch {
            throw "No console to prompt on. Pass -DevTools or -NoDevTools instead."
        }
        if ($answer -eq '') { $answer = 'y' }
    } while ($answer -notin @('y', 'yes', 'n', 'no'))
    $enableDevTools = $answer -in @('y', 'yes')
    Write-Host ""
}

Write-Host ("Developer tools: {0}" -f $(if ($enableDevTools) { 'ON' } else { 'off' })) -ForegroundColor Cyan

# --- 7. run or build-apk? ---------------------------------------------------
if ($Apk -and $Run) { throw "Pick one of -Apk / -Run, not both." }

if ($PublishFree) { $mode = 'package' }
elseif ($Apk)  { $mode = 'apk' }
elseif ($Run)  { $mode = 'run' }
else {
    Write-Host "What do you want to do?"
    Write-Host "  [R] flutter run  - hot reload, dev session (needs PC connected)"
    Write-Host "  [A] build APK    - real installable app, stays after unplugging"
    do {
        try { $m = (Read-Host "Run or build Apk? (R/a)").Trim().ToLower() }
        catch { throw "No console to prompt on. Pass -Run or -Apk instead." }
        if ($m -eq '') { $m = 'r' }
    } while ($m -notin @('r', 'run', 'a', 'apk'))
    $mode = if ($m -in @('a', 'apk')) { 'apk' } else { 'run' }
    Write-Host ""
}

# shared --dart-define args
$defineArgs = @()
if ($EnvFile -and $EnvFile -ne 'none') {
    $envPath = Join-Path $appDir "env\$EnvFile.json"
    if (-not (Test-Path $envPath)) {
        $available = Get-ChildItem (Join-Path $appDir 'env') -Filter '*.json' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike '*.example.json' } |
            ForEach-Object { $_.BaseName }
        throw "env file not found: $envPath`nAvailable: $($available -join ', ')"
    }
    $defineArgs += "--dart-define-from-file=$envPath"
}
$defineArgs += "--dart-define=ENABLE_DEVELOPER_TOOLS=$($enableDevTools.ToString().ToLower())"
$unlockPremium = [bool]($FreePremium -or $PublishFree)
$defineArgs += "--dart-define=UNLOCK_PREMIUM_FEATURES=$($unlockPremium.ToString().ToLower())"
Write-Host ("Premium access: {0}" -f $(if ($unlockPremium) { 'FREE / unlocked' } else { 'entitlement-controlled' })) -ForegroundColor Cyan

# Build provenance: stamp the commit / branch / time being built so that
# Developer Tools > Build shows exactly what landed on the device, not a guess
# (see apps/main_app/lib/dev/build_info.dart). Best-effort — a missing git or a
# non-repo checkout just leaves the in-app defaults ('local').
$gitCommit = ''
$gitBranch = ''
try { $gitCommit = (& git -C $repoRoot rev-parse --short HEAD 2>$null) } catch { }
try { $gitBranch = (& git -C $repoRoot rev-parse --abbrev-ref HEAD 2>$null) } catch { }
if ($gitCommit) { $defineArgs += "--dart-define=GIT_COMMIT=$($gitCommit.Trim())" }
if ($gitBranch) { $defineArgs += "--dart-define=GIT_BRANCH=$($gitBranch.Trim())" }
$defineArgs += "--dart-define=BUILD_TIME=$(Get-Date -Format 'MM-dd HH:mm')"

# clean first?
if ($PublishFree)  { $doClean = $true }
elseif ($Clean)    { $doClean = $true }
elseif ($NoPause)  { $doClean = $false }
else {
    do {
        try { $c = (Read-Host "Run 'flutter clean' first? (y/N)").Trim().ToLower() }
        catch { $c = 'n' }
        if ($c -eq '') { $c = 'n' }
    } while ($c -notin @('y', 'yes', 'n', 'no'))
    $doClean = $c -in @('y', 'yes')
    Write-Host ""
}

# flutter logs plenty to stderr; don't let that masquerade as a failure.
$ErrorActionPreference = 'Continue'

if ($doClean) {
    Write-Host "flutter clean" -ForegroundColor DarkGray
    Push-Location $appDir
    try {
        & flutter clean
        if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Host "`n  flutter clean failed ($LASTEXITCODE)" -ForegroundColor Red; Exit-Run $LASTEXITCODE }
        Write-Host "flutter pub get" -ForegroundColor DarkGray
        & flutter pub get
        if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Host "`n  flutter pub get failed ($LASTEXITCODE)" -ForegroundColor Red; Exit-Run $LASTEXITCODE }
    } finally { if ((Get-Location).Path -eq $appDir) { Pop-Location } }
    Write-Host ""
}

if ($mode -eq 'run') {
    $flutterArgs = @('run', '-d', $target) + $defineArgs
    if ($Release) { $flutterArgs += '--release' }

    Write-Host "flutter $($flutterArgs -join ' ')" -ForegroundColor DarkGray
    Write-Host ""
    Push-Location $appDir
    try { & flutter @flutterArgs; $code = $LASTEXITCODE } finally { Pop-Location }
    if ($code -ne 0) { Write-Host "`n  flutter run exited with code $code" -ForegroundColor Red }
    Exit-Run $code
}

# --- 8. build APK + install -------------------------------------------------
$flutterArgs = @('build', 'apk', '--release') + $defineArgs

Write-Host "flutter $($flutterArgs -join ' ')" -ForegroundColor DarkGray
Write-Host ""
Push-Location $appDir
try { & flutter @flutterArgs; $code = $LASTEXITCODE } finally { Pop-Location }
if ($code -ne 0) {
    Write-Host "`n  flutter build apk exited with code $code" -ForegroundColor Red
    Exit-Run $code
}

$builtApk = Get-ChildItem (Join-Path $appDir 'build\app\outputs\flutter-apk') -Filter 'app-release.apk' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $builtApk) { throw "Build reported success but no app-release.apk was found." }

$sizeMb = [math]::Round($builtApk.Length / 1MB, 1)
Write-Host ""
Write-Host "Built $($builtApk.Name) ($sizeMb MB)" -ForegroundColor Green

if ($mode -eq 'package') {
    $versionMatch = Select-String -LiteralPath (Join-Path $appDir 'pubspec.yaml') -Pattern '^version:\s*(\S+)\s*$' | Select-Object -First 1
    $version = if ($versionMatch) { $versionMatch.Matches[0].Groups[1].Value } else { Get-Date -Format 'yyyyMMdd-HHmm' }
    $releaseDir = Join-Path $repoRoot 'output\releases'
    New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null
    $publishApk = Join-Path $releaseDir "aumazing-free-premium-$version.apk"
    Copy-Item -LiteralPath $builtApk.FullName -Destination $publishApk -Force
    Write-Host "Publish package: $publishApk" -ForegroundColor Green
    Exit-Run 0
}

Write-Host "Installing on $target ..." -ForegroundColor Cyan

$installOut = Invoke-Adb -s $target install -r "$($builtApk.FullName)"
Write-Host $installOut.Trim()
if ($installOut -notmatch 'Success') {
    Write-Host "  install failed." -ForegroundColor Red
    Exit-Run 1
}
Write-Host "Installed." -ForegroundColor Green

# work out the applicationId so we can launch it
$gradle = Get-ChildItem (Join-Path $appDir 'android\app') -Filter 'build.gradle*' -ErrorAction SilentlyContinue | Select-Object -First 1
$pkg = $null
if ($gradle) {
    $txt = Get-Content $gradle.FullName -Raw
    if ($txt -match 'applicationId\s*=?\s*"([^"]+)"') { $pkg = $Matches[1] }
}

if (-not $NoLaunch -and $pkg) {
    Write-Host "Launching $pkg ..." -ForegroundColor Cyan
    Invoke-Adb -s $target shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 | Out-Null
} elseif (-not $pkg) {
    Write-Host "(Could not read applicationId; open the app from the phone's launcher.)" -ForegroundColor DarkGray
}

Exit-Run 0
