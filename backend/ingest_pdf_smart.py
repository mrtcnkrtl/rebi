"""
REBI AI - Akıllı PDF Yükleme (ingest_pdf_smart.py)
=====================================================
Belirli PDF'leri cümle sınırlarına dikkat ederek,
bölüm başlıklarını tanıyarak ve doğru metadata
etiketleriyle Supabase'e yükler.

Farklar:
- Cümle ortasından kırılmaz (sentence-aware chunking)
- Bölüm/konu tespiti ile otomatik kategori ataması
- Mevcut veriyi silmez, sadece EKLER
- Null karakter + bozuk unicode temizliği
- Daha büyük chunk (800 char) → bağlam korunur

Kullanım:
    cd backend
    source venv/bin/activate
    python ingest_pdf_smart.py

PDF kaynakları (repo içi):
    - documents/ : akne + dermakozmetik (varsa)
    - DATA/      : doğal ürünler ve diğer ek PDF'ler (*.pdf)
"""

import os
import re
import sys
import time
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent
DOCUMENTS_DIR = BACKEND_DIR / "documents"
DATA_DIR = BACKEND_DIR / "DATA"

from dotenv import load_dotenv
from google import genai
from google.genai import types
from supabase import create_client
from PyPDF2 import PdfReader

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

EMBEDDING_MODEL = "gemini-embedding-001"
EMBEDDING_DIMENSIONS = 1536
CHUNK_SIZE = 800
CHUNK_OVERLAP = 80
BATCH_SIZE = 20

# ══════════════════════════════════════════════════════════════════════
# Doğal ürün / fitokozmetik — alt kategori = Tedavi Ajanı sorgu planı ile uyumlu
# ══════════════════════════════════════════════════════════════════════

NATURAL_TOPIC_RULES = [
    {
        "alt_kategori": "Kanıt Seviyesi",
        "keywords": [
            r"kanıt", r"klinik çalışma", r"randomize", r"RCT", r"meta[\s-]?analiz",
            r"sistematik", r"derleme", r"ölçek", r"skor", r"istatistik",
            r"güvenilirlik", r"limitasyon", r"bias", r"GRADE", r"Cochrane",
        ],
    },
    {
        "alt_kategori": "Klinik Etkinlik",
        "keywords": [
            r"etkinlik", r"iyileş", r"azalma", r"artış", r"%\s*\d",
            r"hafta", r"gün\s*\d", r"tedavi sonuc", r"yan etki",
            r"hasta", r"olgu", r"kohort",
        ],
    },
    {
        "alt_kategori": "Etki Mekanizması",
        "keywords": [
            r"mekanizma", r"antioksidan", r"polifenol", r"flavonoid",
            r"inflamat", r"serbest radikal", r"bariyer", r"TEWL",
            r"keratinosit", r"kolajen", r"elastin", r"UV",
        ],
    },
    {
        "alt_kategori": "Mekanizma",
        "keywords": [
            r"doğal", r"bitki", r"fito", r"herbal", r"botanical",
            r"ekstrakt", r"yağ\s*\(", r"uçucu yağ", r"esansiyel",
            r"bal", r"propolis", r"aloe", r"çay ağacı", r"lavanta",
            r"kamfer", r"mentol", r"shea", r"jojoba", r"argan",
        ],
    },
    {
        "alt_kategori": "Genel",
        "keywords": [
            r"güvenli", r"toksisite", r"alerji", r"patch test", r"hassas",
            r"hamile", r"emzir", r"kullanım öner", r"rehber", r"özet",
        ],
    },
]


# ══════════════════════════════════════════════════════════════════════
# Konu Tespit Kuralları
# ══════════════════════════════════════════════════════════════════════

# PDF 1: Akne - alt kategori tespiti
AKNE_TOPIC_RULES = [
    {
        "alt_kategori": "Epidemiyoloji",
        "keywords": [
            r"prevalans", r"insidans", r"DALY", r"GBD", r"\d+/100[,.]?000",
            r"yaş.?spesifik", r"AAPC", r"küresel", r"ülke bazında",
            r"popülasyon", r"artış.*oran", r"batı avrupa", r"kuzey afrika",
        ],
    },
    {
        "alt_kategori": "Sınıflandırma",
        "keywords": [
            r"derece\s*[1-4]", r"komedon", r"papül", r"püstül", r"nodül",
            r"kistik", r"fulminans", r"neonatal", r"cosmetica", r"mekanik",
            r"hormonal akne", r"blackhead", r"whitehead", r"sınıflandır",
            r"lesyon.?tür", r"hafif.*orta.*şiddet", r"Grade",
        ],
    },
    {
        "alt_kategori": "Nedenler",
        "keywords": [
            r"patogenez", r"androjen", r"5α-DHT", r"testosteron",
            r"sebum", r"sebase", r"C\.\s*acnes", r"Cutibacterium",
            r"inflamat", r"sitokin", r"IL-?\d", r"TNF", r"IGF",
            r"komedogenez", r"folikül", r"hiperkeratinizasyon",
            r"genetik", r"kalıtım", r"heritabilite", r"GWAS",
            r"stres", r"kortizol", r"HPA", r"uyku", r"PSQI",
            r"diyet", r"glisemik", r"süt ürün", r"insülin",
            r"hormonal", r"premenstrüel", r"PCOS",
        ],
    },
    {
        "alt_kategori": "Tedavi",
        "keywords": [
            r"tedavi", r"topikal", r"sistemik", r"retinoid", r"izotretinoin",
            r"antibiyotik", r"benzoil peroksit", r"salisilik asit",
            r"adapalen", r"klindamisin", r"doksisiklin",
            r"protokol", r"müdahale",
        ],
    },
]

# PDF 2: Dermakozmetik - alt kategori tespiti
DERMA_TOPIC_RULES = [
    {
        "alt_kategori": "Kanıt Seviyesi",
        "keywords": [
            r"Level\s*[123][ab]?", r"RCT", r"kanıt seviye", r"kanıt merkez",
            r"randomize", r"meta-analiz", r"sistematik.*derleme",
            r"konsensüs", r"fikir birliğ", r"uzman.*fikir",
            r"Oxford", r"kalite.*çalışma",
        ],
    },
    {
        "alt_kategori": "Klinik Etkinlik",
        "keywords": [
            r"etkinlik", r"azalma.*%", r"iyileşm.*%", r"artış.*%",
            r"%\d+", r"MASI skoru", r"SMD", r"tedavi.*hafif",
            r"tedavi.*orta", r"tedavi.*şiddet", r"protokol",
            r"sabah.*akşam", r"haftada", r"günde",
        ],
    },
    {
        "alt_kategori": "Etki Mekanizması",
        "keywords": [
            r"mekanizma", r"kolajen sentez", r"hücre döngüsü",
            r"lipogenez", r"bariyer", r"TEWL", r"stratum corneum",
            r"keratinosit", r"melanin", r"tirosinaz", r"okluzif",
            r"penetrasyon", r"restorasyon", r"inhibisyon",
            r"AhR", r"HSD1", r"diferensiasyon",
        ],
    },
    {
        "alt_kategori": "Mekanizma",
        "keywords": [
            r"retinoid", r"tretinoin", r"retinol", r"retinaldehyde",
            r"niasinamid", r"vitamin\s*C", r"askorbik", r"azelai",
            r"salisilik", r"benzoil", r"seramid", r"hyaluronik",
            r"peptid", r"kolajen", r"güneş.*filtre", r"çinko.*oksit",
            r"petrolatum", r"vazelin", r"traneksamik", r"kojik",
            r"hidrokinon", r"arbutin", r"çay.*ağacı",
        ],
    },
    {
        "alt_kategori": "Genel",
        "keywords": [
            r"cilt.*tipi", r"kuru.*cilt", r"yağlı.*cilt", r"karma.*cilt",
            r"hassas.*cilt", r"normal.*cilt", r"amplifikasyon",
            r"risk.*faktör", r"multifaktori",
        ],
    },
]


def build_pdf_jobs() -> list[dict]:
    """
    İşlenecek PDF listesi: documents/ (klasik) + DATA/ (doğal ürün vb.).
    Eksik dosyalar atlanır; hiç PDF yoksa boş liste.
    """
    jobs: list[dict] = []

    p_akne = DOCUMENTS_DIR / "Akne Türleri, Nedenleri ve Etki Yüzdeleri_ Bilimse.pdf"
    if p_akne.is_file():
        jobs.append({
            "path": p_akne,
            "short_name": "Akne Bilimsel",
            "default_kategori": "Akne Vulgaris",
            "topic_rules": AKNE_TOPIC_RULES,
            "doc_type": "pdf_bilimsel",
        })

    p_derma_a = DOCUMENTS_DIR / "dermakozmetik olarak sorunlara yönelik bilimsel ol.pdf"
    p_derma_b = DOCUMENTS_DIR / "dermakozmetik oltttarak sorunlara yönelik bilimsel ol.pdf"
    p_derma = p_derma_a if p_derma_a.is_file() else p_derma_b
    if p_derma.is_file():
        jobs.append({
            "path": p_derma,
            "short_name": "Dermakozmetik Bilimsel",
            "default_kategori": "Tedavi Ajanı",
            "topic_rules": DERMA_TOPIC_RULES,
            "doc_type": "pdf_bilimsel",
        })

    if DATA_DIR.is_dir():
        for path in sorted(DATA_DIR.glob("*.pdf")):
            if not path.is_file():
                continue
            jobs.append({
                "path": path,
                "short_name": (path.stem[:60] or path.name[:60]),
                "default_kategori": "Tedavi Ajanı",
                "topic_rules": NATURAL_TOPIC_RULES,
                "doc_type": "pdf_dogal_urun",
            })

    return jobs


# ══════════════════════════════════════════════════════════════════════
# Yardımcı fonksiyonlar
# ══════════════════════════════════════════════════════════════════════

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
    """Null karakter, bozuk unicode ve gereksiz boşlukları temizler."""
    if not text:
        return ""
    text = text.replace("\x00", "")
    text = text.replace("\u0000", "")
    # Bozuk _x0000_ pattern'ı (PyPDF2 bazen bunu üretir)
    text = re.sub(r"_x[0-9a-fA-F]{4}_", "", text)
    # Fazla boşlukları düzelt (satır içi)
    text = re.sub(r"[ \t]+", " ", text)
    # 3+ ardışık yeni satırı 2'ye indir
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def sentence_aware_chunk(text: str) -> list[str]:
    """
    Cümle sınırlarına saygı duyarak parçalar.
    Veriyi korur: cümle ortasından KIRMAZ.
    """
    text = sanitize_text(text)
    if not text:
        return []
    if len(text) <= CHUNK_SIZE:
        return [text]

    # Cümle sınırları: '. ', '! ', '? ', '\n' sonrasında
    sentence_endings = re.compile(r'(?<=[.!?])\s+|(?<=\n)\s*')
    sentences = sentence_endings.split(text)
    sentences = [s.strip() for s in sentences if s.strip()]

    chunks = []
    current_chunk = ""

    for sentence in sentences:
        # Eğer tek cümle bile chunk_size'dan büyükse, karakter bazlı böl
        if len(sentence) > CHUNK_SIZE:
            if current_chunk:
                chunks.append(current_chunk.strip())
                current_chunk = ""
            # Büyük cümleyi kelime sınırında böl
            words = sentence.split()
            temp = ""
            for word in words:
                if len(temp) + len(word) + 1 > CHUNK_SIZE:
                    if temp:
                        chunks.append(temp.strip())
                    temp = word
                else:
                    temp = f"{temp} {word}" if temp else word
            if temp:
                current_chunk = temp
            continue

        # Normal durum: cümleyi mevcut chunk'a ekle
        test = f"{current_chunk} {sentence}" if current_chunk else sentence

        if len(test) <= CHUNK_SIZE:
            current_chunk = test
        else:
            # Mevcut chunk'ı kaydet, yeni başla
            if current_chunk:
                chunks.append(current_chunk.strip())
            current_chunk = sentence

    # Son kalan parçayı ekle
    if current_chunk.strip():
        # Çok küçükse öncekiyle birleştir
        if len(current_chunk.strip()) < 50 and chunks:
            chunks[-1] = f"{chunks[-1]} {current_chunk.strip()}"
        else:
            chunks.append(current_chunk.strip())

    return chunks


def detect_topic(text: str, rules: list[dict]) -> str:
    """Metin içeriğine göre en uygun alt kategoriyi belirler."""
    scores = {}
    text_lower = text.lower()

    for rule in rules:
        alt_kat = rule["alt_kategori"]
        score = 0
        for kw in rule["keywords"]:
            matches = len(re.findall(kw, text_lower, re.IGNORECASE))
            score += matches
        if score > 0:
            scores[alt_kat] = score

    if not scores:
        return "Genel"

    return max(scores, key=scores.get)


def generate_embeddings(client, texts: list[str]) -> list[list[float]]:
    clean_texts = [sanitize_text(t) or "bos" for t in texts]
    result = client.models.embed_content(
        model=EMBEDDING_MODEL,
        contents=clean_texts,
        config=types.EmbedContentConfig(output_dimensionality=EMBEDDING_DIMENSIONS),
    )
    return [e.values for e in result.embeddings]


# ══════════════════════════════════════════════════════════════════════
# PDF İşleme
# ══════════════════════════════════════════════════════════════════════

def process_pdf(
    filepath: Path,
    short_name: str,
    default_kategori: str,
    topic_rules: list[dict],
    gemini_client,
    supabase_client,
    doc_type: str = "pdf_bilimsel",
) -> int:
    """
    Tek bir PDF'i akıllıca işler:
    1. Sayfa sayfa oku
    2. Null char temizle
    3. Cümle sınırlarına göre parçala
    4. Konu tespiti ile metadata ata
    5. Embed + upload
    """
    filename = filepath.name
    log("📖", f"'{short_name}' okunuyor...")
    log("📄", f"  Dosya: {filename}")

    try:
        reader = PdfReader(str(filepath))
    except Exception as e:
        log("❌", f"  PDF açılamadı: {e}")
        return 0

    total_pages = len(reader.pages)
    log("📐", f"  {total_pages} sayfa bulundu")

    all_chunks = []
    topic_stats = {}
    skipped_pages = 0

    for i, page in enumerate(reader.pages):
        progress_bar(i + 1, total_pages, label=f"Sayfa {i+1}/{total_pages}")

        try:
            raw_text = page.extract_text()
        except Exception:
            skipped_pages += 1
            continue

        if not raw_text:
            skipped_pages += 1
            continue

        text = sanitize_text(raw_text)
        if not text or len(text) < 20:
            skipped_pages += 1
            continue

        # Konu tespiti (sayfa bazında)
        page_topic = detect_topic(text, topic_rules)
        topic_stats[page_topic] = topic_stats.get(page_topic, 0) + 1

        # Cümle-farkında parçalama
        chunks = sentence_aware_chunk(text)

        for chunk_idx, chunk in enumerate(chunks):
            # Chunk bazında daha spesifik konu tespiti
            chunk_topic = detect_topic(chunk, topic_rules)

            all_chunks.append({
                "content": chunk,
                "metadata": {
                    "source": filename,
                    "short_name": short_name,
                    "kategori": default_kategori,
                    "alt_kategori": chunk_topic,
                    "page": i + 1,
                    "chunk_index": chunk_idx,
                    "doc_type": doc_type,
                },
            })

    log("📊", f"  {len(all_chunks)} parça oluşturuldu ({skipped_pages} sayfa atlandı)")
    log("🏷️", f"  Konu dağılımı:")
    for topic, count in sorted(topic_stats.items(), key=lambda x: -x[1]):
        log("  ", f"    {topic}: {count} sayfa")

    if not all_chunks:
        log("⚠️", "  Parça yok, atlanıyor.")
        return 0

    # Embed + Upload
    log("🤖", f"  Gemini ile vektörleştiriliyor...")
    chunks_upserted = 0

    for i in range(0, len(all_chunks), BATCH_SIZE):
        batch = all_chunks[i: i + BATCH_SIZE]
        texts = [c["content"] for c in batch]
        progress_bar(
            min(i + BATCH_SIZE, len(all_chunks)),
            len(all_chunks),
            label="Embed + Upload",
        )

        try:
            embeddings = generate_embeddings(gemini_client, texts)
            records = []
            for chunk_data, embedding in zip(batch, embeddings):
                records.append({
                    "content": chunk_data["content"],
                    "metadata": chunk_data["metadata"],
                    "embedding": embedding,
                })
            supabase_client.table("knowledge_base").insert(records).execute()
            chunks_upserted += len(records)
        except Exception as e:
            log("⚠️", f"  Batch hatası (satır {i}): {str(e)[:120]}")

        time.sleep(0.3)

    return chunks_upserted


# ══════════════════════════════════════════════════════════════════════
# Ana Fonksiyon
# ══════════════════════════════════════════════════════════════════════

def main():
    print()
    print("╔═══════════════════════════════════════════════════════╗")
    print("║  🌿 REBI AI - Akıllı PDF Yükleme                     ║")
    print("║  🧠 Cümle-farkında parçalama + Konu tespiti           ║")
    print("║  🏷️  Flow Engine uyumlu metadata                      ║")
    print("╚═══════════════════════════════════════════════════════╝")
    print()

    # Env check
    missing = []
    if not SUPABASE_URL:
        missing.append("SUPABASE_URL")
    if not SUPABASE_KEY:
        missing.append("SUPABASE_SERVICE_KEY")
    if not GEMINI_API_KEY:
        missing.append("GEMINI_API_KEY")
    if missing:
        log("❌", f"Eksik: {', '.join(missing)}")
        sys.exit(1)

    gemini_client = genai.Client(api_key=GEMINI_API_KEY)
    supabase_client = create_client(SUPABASE_URL, SUPABASE_KEY)

    log("🔗", f"Supabase: {SUPABASE_URL}")
    log("🤖", f"Model: {EMBEDDING_MODEL} ({EMBEDDING_DIMENSIONS} boyut)")
    log("✂️", f"Chunk: {CHUNK_SIZE} char (cümle-farkında), overlap yok")
    jobs = build_pdf_jobs()
    if not jobs:
        log("❌", f"Hiç PDF bulunamadı. Şunları kontrol et: {DOCUMENTS_DIR}, {DATA_DIR}")
        sys.exit(1)

    log("📋", f"Hedef: {len(jobs)} PDF dosyası")
    print()

    for pdf_info in jobs:
        fpath = pdf_info["path"]
        if not fpath.exists():
            log("⚠️", f"Atlanıyor (yok): {fpath}")
            continue
        size_mb = fpath.stat().st_size / (1024 * 1024)
        log("📄", f"  {pdf_info['short_name']}: {fpath.name} ({size_mb:.1f} MB)")

    print()
    print("─" * 58)

    total_chunks = 0
    per_file_counts: list[tuple[str, int]] = []
    start = time.time()

    for idx, job in enumerate(jobs, start=1):
        fpath = job["path"]
        if not fpath.exists():
            continue
        label = job.get("short_name", fpath.name)
        print(f"\n  [{idx}/{len(jobs)}] 📚 {label}")
        print("  " + "─" * 54)
        n = process_pdf(
            filepath=fpath,
            short_name=job["short_name"],
            default_kategori=job["default_kategori"],
            topic_rules=job["topic_rules"],
            gemini_client=gemini_client,
            supabase_client=supabase_client,
            doc_type=job.get("doc_type", "pdf_bilimsel"),
        )
        total_chunks += n
        per_file_counts.append((label, n))
        log("✅", f"  Tamamlandı: {n} parça yüklendi")

    elapsed = time.time() - start

    lines = [f"  {'─' * 42}", "  Dosya bazında:"]
    for name, c in per_file_counts:
        lines.append(f"    • {name[:44]:<44} {c:>5} parça")
    lines.append(f"  📦 Toplam:                 {total_chunks:>5} parça")
    lines.append(f"  ⏱️  Süre:                   {elapsed:.1f}s")
    summary_body = "\n".join(lines)

    print(f"""
{'═' * 58}
  🏁 PDF YÜKLEME TAMAMLANDI
{summary_body}
  🏷️  Metadata:               kategori + alt_kategori + sayfa
  🧠 Chunking:               Cümle-farkında (800 char max)
{'═' * 58}

  ℹ️  Mevcut veri korundu, yeni parçalar EKLENDI.
  ℹ️  Flow Engine bu verileri metadata filtresi ile sorgulayabilir.
""")


if __name__ == "__main__":
    main()
