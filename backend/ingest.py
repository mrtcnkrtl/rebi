"""
REBI AI - Bilgi Tabanı Yükleme Scripti (ingest.py) v2
========================================================
Excel ve PDF dosyalarını yapısal metadata ile etiketleyerek
Supabase knowledge_base tablosuna yükler.

v2 Farkı:
- Kategori ve Alt Kategori metadata olarak eklenir
- Null karakter (\x00) temizlenir
- Akış Şeması Verisi ayrıca etiketlenir
- Supabase metadata filtreleri ile doğrudan aranabilir

Kullanım:
    cd backend
    source venv/bin/activate
    python ingest.py
"""

import os
import sys
import time
from pathlib import Path

from dotenv import load_dotenv
from google import genai
from google.genai import types
from supabase import create_client
import pandas as pd
from PyPDF2 import PdfReader

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

DOCUMENTS_DIR = Path(__file__).resolve().parent / "documents"
EMBEDDING_MODEL = "gemini-embedding-001"
EMBEDDING_DIMENSIONS = 1536
CHUNK_SIZE = 500
CHUNK_OVERLAP = 50
BATCH_SIZE = 20


def validate_env():
    missing = []
    if not SUPABASE_URL or "your-project" in SUPABASE_URL:
        missing.append("SUPABASE_URL")
    if not SUPABASE_KEY or SUPABASE_KEY.endswith("your-service-role-key"):
        missing.append("SUPABASE_SERVICE_KEY")
    if not GEMINI_API_KEY or GEMINI_API_KEY == "your-gemini-api-key":
        missing.append("GEMINI_API_KEY")
    if missing:
        print(f"\n  ❌ HATA: Eksik: {', '.join(missing)}\n")
        sys.exit(1)


def log(icon, msg):
    print(f"  {icon}  {msg}")


def progress_bar(current, total, width=30, label=""):
    if total == 0:
        return
    filled = int(width * current / total)
    bar = "█" * filled + "░" * (width - filled)
    pct = current / total * 100
    end = "\n" if current == total else "\r"
    print(f"  ▐{bar}▌ {pct:5.1f}%  {label}", end=end, flush=True)


def sanitize_text(text: str) -> str:
    """Null karakter ve sorunlu unicode'ları temizler."""
    if not text:
        return ""
    return text.replace("\x00", "").replace("\u0000", "").strip()


def chunk_text(text: str) -> list[str]:
    text = sanitize_text(text)
    if not text:
        return []
    if len(text) <= CHUNK_SIZE:
        return [text]
    chunks = []
    start = 0
    while start < len(text):
        end = start + CHUNK_SIZE
        chunk = text[start:end].strip()
        if chunk:
            chunks.append(chunk)
        start = end - CHUNK_OVERLAP
    if chunks and len(chunks[-1]) < CHUNK_OVERLAP:
        chunks.pop()
    return chunks


def generate_embeddings(client, texts: list[str]) -> list[list[float]]:
    clean_texts = [sanitize_text(t) or "boş" for t in texts]
    result = client.models.embed_content(
        model=EMBEDDING_MODEL,
        contents=clean_texts,
        config=types.EmbedContentConfig(output_dimensionality=EMBEDDING_DIMENSIONS),
    )
    return [e.values for e in result.embeddings]


def upsert_to_supabase(supabase_client, records):
    supabase_client.table("knowledge_base").insert(records).execute()


# ══════════════════════════════════════════════════════════════════════
# EXCEL İŞLEME - Kategori/Alt Kategori metadata ile
# ══════════════════════════════════════════════════════════════════════

def process_excel(filepath: Path, gemini_client, supabase_client) -> int:
    """Excel dosyasını yapısal metadata ile işler."""
    filename = filepath.name
    log("📖", f"'{filename}' okunuyor...")

    try:
        xls = pd.ExcelFile(filepath, engine="openpyxl")
    except Exception as e:
        log("⚠️", f"Excel açma hatası: {e}")
        return 0

    total_upserted = 0

    for sheet_name in xls.sheet_names:
        df = pd.read_excel(xls, sheet_name=sheet_name)
        df = df.dropna(how="all")

        if sheet_name == "Akış Şeması Verisi":
            # Akış şeması: Source → Target [Label] yapısı
            log("🔀", f"  Akış şeması işleniyor ({len(df)} düğüm)...")
            count = process_flow_chart(df, filename, gemini_client, supabase_client)
            total_upserted += count
            continue

        if sheet_name == "Master Veri":
            log("📊", f"  Master Veri işleniyor ({len(df)} satır)...")
            count = process_master_data(df, filename, sheet_name, gemini_client, supabase_client)
            total_upserted += count
            continue

        # Genel sheet
        log("📄", f"  Sheet '{sheet_name}' işleniyor ({len(df)} satır)...")
        count = process_generic_sheet(df, filename, sheet_name, gemini_client, supabase_client)
        total_upserted += count

    return total_upserted


def process_master_data(df, filename, sheet_name, gemini_client, supabase_client) -> int:
    """Master Veri sayfasını Kategori + Alt Kategori metadata ile işler."""
    all_chunks = []
    columns = list(df.columns)

    for idx, (_, row) in enumerate(df.iterrows()):
        progress_bar(idx + 1, len(df), label=f"Satır {idx+1}/{len(df)}")

        # Yapısal metadata çıkar
        kategori = sanitize_text(str(row.get("Kategori", ""))) if pd.notna(row.get("Kategori")) else ""
        alt_kategori = sanitize_text(str(row.get("Alt Kategori", ""))) if pd.notna(row.get("Alt Kategori")) else ""
        dosya = sanitize_text(str(row.get("Dosya", ""))) if pd.notna(row.get("Dosya")) else ""
        kaynak = sanitize_text(str(row.get("Kaynak", ""))) if pd.notna(row.get("Kaynak")) else ""

        # İçerik ve Detay alanlarını birleştir
        icerik = sanitize_text(str(row.get("İçerik", ""))) if pd.notna(row.get("İçerik")) else ""
        detay = sanitize_text(str(row.get("Detay", ""))) if pd.notna(row.get("Detay")) else ""
        sayisal = str(row.get("Sayısal Veri", "")) if pd.notna(row.get("Sayısal Veri")) else ""

        # Metin oluştur
        text_parts = []
        if icerik:
            text_parts.append(icerik)
        if detay and detay != icerik:
            text_parts.append(detay)
        if sayisal:
            text_parts.append(f"Sayısal veri: {sayisal}")

        full_text = " ".join(text_parts)
        if not full_text.strip():
            continue

        # Chunk'la
        for chunk in chunk_text(full_text):
            all_chunks.append({
                "content": chunk,
                "metadata": {
                    "source": filename,
                    "sheet": sheet_name,
                    "kategori": kategori,
                    "alt_kategori": alt_kategori,
                    "dosya": dosya,
                    "kaynak": kaynak,
                    "row": idx + 2,
                },
            })

    return _embed_and_upload(all_chunks, filename, gemini_client, supabase_client)


def process_flow_chart(df, filename, gemini_client, supabase_client) -> int:
    """Akış şeması verisini node ilişkileri olarak yükler."""
    all_chunks = []

    for _, row in df.iterrows():
        source = sanitize_text(str(row.get("Source", "")))
        target = sanitize_text(str(row.get("Target", "")))
        label = sanitize_text(str(row.get("Label", "")))

        text = f"{source} → {target}: {label}"

        all_chunks.append({
            "content": text,
            "metadata": {
                "source": filename,
                "sheet": "Akış Şeması Verisi",
                "kategori": "Akış Şeması",
                "alt_kategori": "Düğüm İlişkisi",
                "node_source": source,
                "node_target": target,
            },
        })

    return _embed_and_upload(all_chunks, filename, gemini_client, supabase_client)


def process_generic_sheet(df, filename, sheet_name, gemini_client, supabase_client) -> int:
    """Genel sheet'ler için satır bazlı işleme."""
    all_chunks = []
    columns = list(df.columns)

    for idx, (_, row) in enumerate(df.iterrows()):
        progress_bar(idx + 1, len(df), label=f"Satır {idx+1}/{len(df)}")
        parts = []
        for col in columns:
            val = row[col]
            if pd.notna(val):
                parts.append(f"{col}: {sanitize_text(str(val))}")
        if parts:
            text = " | ".join(parts)
            for chunk in chunk_text(text):
                all_chunks.append({
                    "content": chunk,
                    "metadata": {
                        "source": filename,
                        "sheet": sheet_name,
                        "kategori": "Genel",
                        "alt_kategori": sheet_name,
                        "row": idx + 2,
                    },
                })

    return _embed_and_upload(all_chunks, filename, gemini_client, supabase_client)


# ══════════════════════════════════════════════════════════════════════
# PDF İŞLEME - Null char fix ile
# ══════════════════════════════════════════════════════════════════════

def process_pdf(filepath: Path, gemini_client, supabase_client) -> int:
    """PDF dosyasını null char temizliği ile işler."""
    filename = filepath.name
    log("📖", f"'{filename}' okunuyor...")

    try:
        reader = PdfReader(str(filepath))
    except Exception as e:
        log("⚠️", f"PDF açma hatası: {e}")
        return 0

    all_chunks = []
    total_pages = len(reader.pages)

    for i, page in enumerate(reader.pages):
        progress_bar(i + 1, total_pages, label=f"Sayfa {i+1}/{total_pages}")
        try:
            text = page.extract_text()
        except Exception:
            continue

        text = sanitize_text(text)
        if not text:
            continue

        for chunk in chunk_text(text):
            all_chunks.append({
                "content": chunk,
                "metadata": {
                    "source": filename,
                    "kategori": "PDF Döküman",
                    "alt_kategori": "Sayfa İçeriği",
                    "page": i + 1,
                },
            })

    return _embed_and_upload(all_chunks, filename, gemini_client, supabase_client)


# ══════════════════════════════════════════════════════════════════════
# ORTAK: Embed + Upload
# ══════════════════════════════════════════════════════════════════════

def _embed_and_upload(all_chunks, filename, gemini_client, supabase_client) -> int:
    if not all_chunks:
        log("⚠️", f"'{filename}' - parça yok, atlanıyor.")
        return 0

    log("📊", f"  → {len(all_chunks)} parça oluşturuldu")
    log("🤖", f"  Gemini ile vektörleştiriliyor...")

    chunks_upserted = 0

    for i in range(0, len(all_chunks), BATCH_SIZE):
        batch = all_chunks[i: i + BATCH_SIZE]
        texts = [c["content"] for c in batch]

        progress_bar(min(i + BATCH_SIZE, len(all_chunks)), len(all_chunks), label="Embedding + Upload")

        try:
            embeddings = generate_embeddings(gemini_client, texts)

            records = []
            for chunk_data, embedding in zip(batch, embeddings):
                records.append({
                    "content": chunk_data["content"],
                    "metadata": chunk_data["metadata"],
                    "embedding": embedding,
                })

            upsert_to_supabase(supabase_client, records)
            chunks_upserted += len(records)
        except Exception as e:
            log("⚠️", f"  Batch hatası: {str(e)[:100]}")

        time.sleep(0.3)

    return chunks_upserted


# ══════════════════════════════════════════════════════════════════════
# ANA FONKSİYON
# ══════════════════════════════════════════════════════════════════════

def main():
    print()
    print("╔══════════════════════════════════════════════════╗")
    print("║   🌿 REBI AI - Bilgi Tabanı Yükleme v2          ║")
    print("║   🏷️  Yapısal Metadata + Null Char Fix           ║")
    print("╚══════════════════════════════════════════════════╝")
    print()

    validate_env()

    gemini_client = genai.Client(api_key=GEMINI_API_KEY)
    supabase_client = create_client(SUPABASE_URL, SUPABASE_KEY)

    # Eski verileri temizle
    log("🗑️", "Eski veriler temizleniyor...")
    try:
        supabase_client.table("knowledge_base").delete().gt("id", 0).execute()
        log("✅", "Eski kayıtlar silindi.")
    except Exception as e:
        log("⚠️", f"Silme hatası (devam ediliyor): {e}")

    log("🔗", f"Supabase: {SUPABASE_URL}")
    log("🤖", f"Model: {EMBEDDING_MODEL} ({EMBEDDING_DIMENSIONS} boyut)")
    log("✂️", f"Chunk: {CHUNK_SIZE} karakter, overlap: {CHUNK_OVERLAP}")

    if not DOCUMENTS_DIR.exists():
        log("❌", f"Klasör bulunamadı: {DOCUMENTS_DIR}")
        sys.exit(1)

    supported = (".pdf", ".xlsx", ".xls")
    files = sorted([f for f in DOCUMENTS_DIR.iterdir() if f.suffix.lower() in supported])

    if not files:
        log("⚠️", "Dosya bulunamadı.")
        sys.exit(0)

    print()
    log("📂", f"Kaynak: {DOCUMENTS_DIR}")
    log("📋", f"Dosya sayısı: {len(files)}")
    for f in files:
        log("  ", f"  → {f.name} ({f.stat().st_size/1024:.1f} KB)")
    print()
    print("─" * 55)

    total_chunks = 0
    success = 0
    fail = 0
    start = time.time()

    for idx, filepath in enumerate(files, 1):
        print(f"\n  [{idx}/{len(files)}] 📄 {filepath.name}")
        print("  " + "─" * 50)

        try:
            suffix = filepath.suffix.lower()
            if suffix in (".xlsx", ".xls"):
                count = process_excel(filepath, gemini_client, supabase_client)
            elif suffix == ".pdf":
                count = process_pdf(filepath, gemini_client, supabase_client)
            else:
                continue

            total_chunks += count
            success += 1
            log("✅", f"Tamamlandı: {count} parça yüklendi")
        except Exception as e:
            fail += 1
            log("❌", f"HATA: {e}")

    elapsed = time.time() - start
    print(f"""
{'═' * 55}
  🏁 YÜKLEME TAMAMLANDI
  {'─' * 37}
  ✅ Başarılı:  {success}/{len(files)}
  ❌ Başarısız: {fail}
  📦 Toplam:   {total_chunks} parça
  ⏱️  Süre:     {elapsed:.1f}s
{'═' * 55}
""")


if __name__ == "__main__":
    main()
