"""
app/config.py
Configuration loader for the Aumazing AI Assessment API.

Reads environment variables from a `.env` file (if present) and exports
them as module-level constants used throughout the application.
"""

import os
from pathlib import Path

from dotenv import load_dotenv

# ──────────────────────────────────────────────────────────────────────
# Load .env from the project root (ai_assessment/)
# ──────────────────────────────────────────────────────────────────────
_ENV_PATH = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(dotenv_path=_ENV_PATH)

# ──────────────────────────────────────────────────────────────────────
# Supabase configuration
# ──────────────────────────────────────────────────────────────────────
SUPABASE_URL: str = os.getenv(
    "SUPABASE_URL",
    "https://lzvvjlcfoyczikaszrbp.supabase.co",
)
SUPABASE_SERVICE_KEY: str = os.getenv("SUPABASE_SERVICE_KEY", "")

# ──────────────────────────────────────────────────────────────────────
# API server configuration
# ──────────────────────────────────────────────────────────────────────
AI_API_HOST: str = os.getenv("AI_API_HOST", "0.0.0.0")
AI_API_PORT: int = int(os.getenv("AI_API_PORT", "8000"))
