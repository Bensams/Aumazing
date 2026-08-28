param(
  [string]$RouterApiKey = $env:ROUTER_API_KEY,
  [string]$RouterBaseUrl = $(if ($env:ROUTER_BASE_URL) { $env:ROUTER_BASE_URL } else { "http://127.0.0.1:20128/v1" }),
  [string]$Model = $(if ($env:ROUTER_MODEL) { $env:ROUTER_MODEL } else { "auto" }),
  [int]$Port = 8787
)

$env:ROUTER_API_KEY = $RouterApiKey
$env:ROUTER_BASE_URL = $RouterBaseUrl
$env:ROUTER_MODEL = $Model
$env:ADAPTER_PORT = "$Port"

node "$PSScriptRoot\server.mjs"
