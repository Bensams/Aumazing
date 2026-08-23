$ErrorActionPreference = "Stop"

$routerDb = Join-Path $env:APPDATA "9router\db\data.sqlite"
$routerKey = & python -c "import sqlite3; print(sqlite3.connect(r'$routerDb').execute('select key from apiKeys where isActive=1 limit 1').fetchone()[0])"
$routerKey = $routerKey.Trim()
if (-not $routerKey) {
  throw "No active 9Router API key was found."
}

$env:ROUTER_API_KEY = $routerKey
$env:ROUTER_BASE_URL = "http://127.0.0.1:20128/v1"
$env:ROUTER_MODEL = "auto"
$env:GEMINI_API_KEY = $routerKey
$env:GOOGLE_GEMINI_BASE_URL = "http://127.0.0.1:8787"

$adapter = Join-Path $PSScriptRoot "server.mjs"
$env:PATH = "$PSScriptRoot;$env:PATH"
$existingAdapter = Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
  Where-Object { $_.CommandLine -like "*gemini_router_adapter*server.mjs*" }
if ($existingAdapter) {
  $existingAdapter | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }
}
Start-Process -FilePath "node.exe" -ArgumentList "`"$adapter`"" -WindowStyle Hidden | Out-Null
Start-Sleep -Milliseconds 800

$munder = "C:\Program Files\Munder Difflin\Munder Difflin.exe"
if (-not (Test-Path -LiteralPath $munder)) {
  throw "Munder Difflin was not found at $munder"
}

$main = Get-CimInstance Win32_Process -Filter "Name='Munder Difflin.exe'" |
  Where-Object { $_.CommandLine -notmatch "--type=" } |
  Select-Object -First 1
if ($main) {
  Stop-Process -Id $main.ProcessId -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
}

Start-Process -FilePath $munder -WorkingDirectory "E:\HarnessAgent" | Out-Null
Write-Host "Started Munder Difflin with Gemini CLI -> adapter -> 9Router -> auto (pro first, flash fallback)"
