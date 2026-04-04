# Supabase Storage Kurulum Rehberi

Bu rehber, Rebi uygulaması için Supabase Storage bucket'ını nasıl oluşturacağınızı açıklar.

## Adım 1: Supabase Dashboard'a Giriş

1. [Supabase Dashboard](https://app.supabase.com) üzerinden projenize giriş yapın
2. Sol menüden **Storage** sekmesine tıklayın

## Adım 2: Bucket Oluşturma

### Yöntem 1: Dashboard Üzerinden (Önerilen)

1. **Storage** sayfasında **"New bucket"** butonuna tıklayın
2. Bucket bilgilerini girin:
   - **Name**: `skin-photos`
   - **Public bucket**: ✅ İşaretleyin (fotoğrafların herkese açık olması için)
   - **File size limit**: `5 MB` (veya istediğiniz maksimum boyut)
   - **Allowed MIME types**: `image/jpeg,image/png,image/webp`
3. **"Create bucket"** butonuna tıklayın

### Yöntem 2: SQL Editor Üzerinden

1. Supabase Dashboard'da **SQL Editor** sekmesine gidin
2. Aşağıdaki SQL'i çalıştırın:

```sql
-- Bucket oluştur
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'skin-photos',
  'skin-photos',
  true,
  5242880,  -- 5 MB
  ARRAY['image/jpeg', 'image/png', 'image/webp']
);
```

## Adım 3: RLS (Row Level Security) Politikaları

Storage bucket'ı oluşturduktan sonra, güvenlik politikalarını ayarlamanız gerekir.

### SQL Editor'de Çalıştırın:

```sql
-- Kullanıcılar sadece kendi fotoğraflarını yükleyebilir
CREATE POLICY "Users can upload own photos"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'skin-photos' 
  AND auth.uid()::text = (storage.foldername(name))[1]
);

-- Kullanıcılar sadece kendi fotoğraflarını silebilir
CREATE POLICY "Users can delete own photos"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'skin-photos' 
  AND auth.uid()::text = (storage.foldername(name))[1]
);

-- Herkes fotoğrafları görüntüleyebilir (public bucket)
CREATE POLICY "Anyone can view skin photos"
ON storage.objects FOR SELECT
USING (bucket_id = 'skin-photos');
```

### Alternatif: Dashboard Üzerinden

1. **Storage** → **skin-photos** bucket'ına tıklayın
2. **"Policies"** sekmesine gidin
3. **"New Policy"** butonuna tıklayın
4. Her politika için:
   - **Policy name**: Örn. "Users can upload own photos"
   - **Allowed operation**: INSERT / DELETE / SELECT
   - **Policy definition**: Yukarıdaki SQL koşullarını kullanın

## Adım 4: Test Etme

### Backend API ile Test

```bash
# Fotoğraf yükleme endpoint'ini test edin
curl -X POST http://localhost:8000/upload_photo?user_id=YOUR_USER_ID \
  -F "file=@test-photo.jpg"
```

### Frontend ile Test

1. Frontend'de fotoğraf yükleme özelliğini kullanın
2. Supabase Dashboard → Storage → skin-photos bucket'ında fotoğrafın göründüğünü kontrol edin

## Sorun Giderme

### "Bucket not found" Hatası

- Bucket adının tam olarak `skin-photos` olduğundan emin olun
- Supabase Dashboard'da bucket'ın oluşturulduğunu kontrol edin

### "Permission denied" Hatası

- RLS politikalarının doğru ayarlandığından emin olun
- Kullanıcının authenticated olduğundan emin olun
- Service role key kullanıyorsanız, RLS politikaları bypass edilir

### Fotoğraf Görünmüyor

- Bucket'ın **public** olarak işaretlendiğinden emin olun
- Fotoğraf URL'sinin doğru oluşturulduğunu kontrol edin:
  ```javascript
  const { data } = supabase.storage
    .from('skin-photos')
    .getPublicUrl(filePath)
  ```

## Güvenlik Notları

1. ✅ **Public bucket**: Fotoğraflar herkese açık olacak, bu yüzden hassas bilgi içermemeli
2. ✅ **File size limit**: Büyük dosyaları engellemek için limit koyun
3. ✅ **MIME type kontrolü**: Sadece görsel dosyalarına izin verin
4. ✅ **RLS politikaları**: Kullanıcılar sadece kendi klasörlerine yükleyebilmeli

## Ek Kaynaklar

- [Supabase Storage Docs](https://supabase.com/docs/guides/storage)
- [Storage RLS Policies](https://supabase.com/docs/guides/storage/security/access-control)
