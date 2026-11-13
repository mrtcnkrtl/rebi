"""
Süreç boyu paylaşılan Supabase istemcisi (service role).

Her istekte yeni istemci kurmak bağlantı havuzunu çöpe atar: her çağrı yeniden TCP + TLS el sıkışır.
İstemci (httpx havuzu) iş parçacıkları arasında paylaşılabilir; sorgu zincirleri (`table(...)`) her
çağrıda yeni bir oluşturucu döndürür, ortak durum tutmaz.
"""

from __future__ import annotations

import os
import threading

from config import SUPABASE_SERVICE_KEY, SUPABASE_URL, get_logger

log = get_logger("supabase_client")


def _timeout_seconds(name: str, default: float) -> float:
    try:
        return max(1.0, float(os.getenv(name, "") or default))
    except ValueError:
        return default


# Takılan bir REST çağrısı bir iş parçacığını (ve istemciyi) 2 dakika tutmasın.
REST_TIMEOUT_SECONDS = _timeout_seconds("SUPABASE_REST_TIMEOUT_SECONDS", 15.0)
STORAGE_TIMEOUT_SECONDS = _timeout_seconds("SUPABASE_STORAGE_TIMEOUT_SECONDS", 30.0)

_client = None
_lock = threading.Lock()


def get_shared_client():
    """Paylaşılan istemci; SUPABASE_URL tanımlı değilse None. İlk çağrıda kurulur."""
    global _client
    if not SUPABASE_URL:
        return None
    if _client is None:
        with _lock:
            if _client is None:
                from supabase import create_client
                from supabase.lib.client_options import SyncClientOptions

                client = create_client(
                    SUPABASE_URL,
                    SUPABASE_SERVICE_KEY,
                    options=SyncClientOptions(
                        postgrest_client_timeout=REST_TIMEOUT_SECONDS,
                        storage_client_timeout=STORAGE_TIMEOUT_SECONDS,
                    ),
                )
                # Alt istemciler tembel kurulur; iki iş parçacığı aynı anda kurmasın diye burada kur.
                _ = client.postgrest
                _ = client.storage
                _client = client
    return _client


def reset_shared_client() -> None:
    """Testler için: bir sonraki çağrıda istemci yeniden kurulur."""
    global _client
    with _lock:
        _client = None
