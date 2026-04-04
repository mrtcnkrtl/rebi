"""
REBI AI - Duplike Veri Temizleme Scripti
==========================================
Metadata'siz eski kayıtları temizler ve veritabanını optimize eder.

Kullanım:
    cd backend
    source venv/bin/activate
    python cleanup_duplicates.py
"""

import os
from dotenv import load_dotenv
from supabase import create_client

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY")

if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
    print("❌ SUPABASE_URL ve SUPABASE_SERVICE_KEY gerekli!")
    exit(1)

supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

print("=" * 60)
print("REBI - Duplike Veri Temizleme")
print("=" * 60)

# 1. Toplam kayıt sayısını kontrol et
print("\n📊 Veritabanı Durumu:")
total_result = supabase.table("knowledge_base").select("id", count="exact").execute()
total_count = total_result.count if hasattr(total_result, 'count') else len(total_result.data)
print(f"   Toplam kayıt: {total_count}")

# 2. Metadata'siz kayıtları bul
print("\n🔍 Metadata'siz kayıtlar aranıyor...")
no_metadata_result = supabase.table("knowledge_base").select("id, metadata").is_("metadata->kategori", "null").execute()
no_metadata_count = len(no_metadata_result.data)

# Alternatif kontrol: metadata boş veya kategori yok
if no_metadata_count == 0:
    all_records = supabase.table("knowledge_base").select("id, metadata").limit(10000).execute()
    no_metadata_ids = []
    for record in all_records.data:
        metadata = record.get("metadata", {})
        if not metadata or not metadata.get("kategori"):
            no_metadata_ids.append(record["id"])
    no_metadata_count = len(no_metadata_ids)
    print(f"   Metadata'siz kayıt bulundu: {no_metadata_count}")
else:
    no_metadata_ids = [r["id"] for r in no_metadata_result.data]
    print(f"   Metadata'siz kayıt bulundu: {no_metadata_count}")

# 3. Metadata'lı kayıtları say
print("\n✅ Metadata'lı kayıtlar:")
with_metadata_count = total_count - no_metadata_count
print(f"   Metadata'lı kayıt: {with_metadata_count}")

# 4. Kullanıcı onayı
if no_metadata_count == 0:
    print("\n✨ Temizlenecek kayıt yok! Veritabanı zaten temiz.")
    exit(0)

print(f"\n⚠️  {no_metadata_count} adet metadata'siz kayıt silinecek.")
response = input("Devam etmek istiyor musunuz? (evet/hayır): ").strip().lower()

if response not in ["evet", "e", "yes", "y"]:
    print("❌ İşlem iptal edildi.")
    exit(0)

# 5. Batch silme (Supabase limit: 1000 per request)
print(f"\n🗑️  Kayıtlar siliniyor...")
BATCH_SIZE = 1000
deleted_count = 0

for i in range(0, len(no_metadata_ids), BATCH_SIZE):
    batch = no_metadata_ids[i:i + BATCH_SIZE]
    try:
        result = supabase.table("knowledge_base").delete().in_("id", batch).execute()
        deleted_count += len(batch)
        print(f"   ✅ {deleted_count}/{no_metadata_count} kayıt silindi...")
    except Exception as e:
        print(f"   ❌ Hata: {e}")
        print(f"   Batch: {len(batch)} kayıt")

# 6. Sonuç
print("\n" + "=" * 60)
print("✨ Temizleme Tamamlandı!")
print("=" * 60)
print(f"   Silinen kayıt: {deleted_count}")
print(f"   Kalan kayıt: {total_count - deleted_count}")
print("\n💡 İpucu: VACUUM ANALYZE çalıştırmak için Supabase SQL Editor'ü kullanın:")
print("   VACUUM ANALYZE knowledge_base;")
