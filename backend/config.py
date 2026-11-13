import os
import logging
from pathlib import Path

from dotenv import load_dotenv

# backend/.env varsa buradan yükle ve shell'deki eski GEMINI_API_KEY vb. değişkenlerin üzerine yaz
# (aksi halde süresi dolmuş bir export, .env'deki yeni key'i gölgeler)
_env_file = Path(__file__).resolve().parent / ".env"
if _env_file.is_file():
    load_dotenv(_env_file, override=True)
else:
    load_dotenv(override=False)

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
# Central Gemini model id (env-overridable). gemini-2.0-flash was retired and now
# returns 404 on generateContent, so default to a current stable model.
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
# PDF/knowledge ingest hangi user_id ile yapıldıysa entity araması (chat yedeği) bunu da dener
KNOWLEDGE_CATALOG_USER_ID = os.getenv(
    "KNOWLEDGE_CATALOG_USER_ID",
    "00000000-0000-4000-8000-000000000001",
)
OPENWEATHER_API_KEY = os.getenv("OPENWEATHER_API_KEY", "")

# Ücretsiz literatür ipuçları (RAG değil): NCBI E-utilities + isteğe bağlı Europe PMC yedeği
def _env_flag(name: str, default: str = "1") -> bool:
    v = (os.getenv(name, default) or "").strip().lower()
    if not v:
        return False
    return v not in ("0", "false", "no", "off")


PUBMED_FREE_HINTS = _env_flag("PUBMED_FREE_HINTS", "1")
NCBI_API_KEY = os.getenv("NCBI_API_KEY", "").strip()
PUBMED_CONTACT_EMAIL = os.getenv("PUBMED_CONTACT_EMAIL", "").strip()

_LOCKED_ORIGINS = ("https://rebiovil.com", "https://www.rebiovil.com")
_DEV_ORIGINS = (
    "http://localhost:5173",
    "http://localhost:5174",
    "http://localhost:3000",
)


def cors_origins() -> list[str]:
    """Üretim listesindeki http:// kökenler düşer. Yerel Vite için ALLOW_HTTP_CORS=1."""
    raw = os.getenv("CORS_ORIGINS")
    if raw is None or not raw.strip():
        found = list(_DEV_ORIGINS)
    else:
        allow_http = (os.getenv("ALLOW_HTTP_CORS") or "").strip().lower() in {"1", "true", "yes", "on"}
        found = []
        for origin in raw.split(","):
            item = origin.strip().rstrip("/")
            if not item:
                continue
            if item.startswith("http://") and not allow_http:
                continue
            if item not in found:
                found.append(item)
    for origin in _LOCKED_ORIGINS:
        if origin not in found:
            found.append(origin)
    return found


# CORS origins - production için environment variable'dan alınır
CORS_ORIGINS = cors_origins()


def get_logger(name: str) -> logging.Logger:
    """Creates a configured logger for a given module."""
    logger = logging.getLogger(name)
    if not logger.handlers:
        handler = logging.StreamHandler()
        handler.setFormatter(logging.Formatter(
            "%(asctime)s [%(name)s] %(levelname)s: %(message)s",
            datefmt="%H:%M:%S",
        ))
        logger.addHandler(handler)
        logger.setLevel(logging.INFO)
    return logger
