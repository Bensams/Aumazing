# Gemini CLI → 9Router adapter

This local adapter translates Gemini CLI's native `generateContent`/streaming
requests into OpenAI-compatible `/v1/chat/completions` requests for 9Router,
then translates the response stream back into Gemini-style SSE.

## Start

Create a 9Router API key in its dashboard, then run:

```powershell
.\tools\gemini_router_adapter\start.ps1 -RouterApiKey "YOUR_9ROUTER_KEY"
```

The adapter listens on `http://127.0.0.1:8787`.

## Use with Gemini CLI

In a new PowerShell window:

```powershell
$env:GEMINI_API_KEY = "YOUR_9ROUTER_KEY"
$env:GOOGLE_GEMINI_BASE_URL = "http://127.0.0.1:8787"
# Use a Gemini CLI-valid alias. The adapter rewrites it to the 9Router model.
gemini --skip-trust -m "flash"
```

Do not put either key in this repository. The adapter uses the incoming
authorization header unless `ROUTER_API_KEY` is supplied to `start.ps1`.

If Gemini CLI reports `"[DONE]" is not valid JSON`, restart the adapter after
updating it. Gemini expects every streamed `data:` event to contain JSON, so
the adapter deliberately does not forward OpenAI's `data: [DONE]` sentinel.
