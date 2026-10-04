# Rebi veri saklama politikası

Teknik uygulama `supabase/migrations/20260920174000_data_retention.sql` içindedir;
`purge_expired_rebi_data()` fonksiyonu sonraki migration'larda güncellenmiştir
(en son `20261004163000_push_notifications.sql`).

- Giriş sunumu IP hash’i: 180 gün
- Günlük mikro olaylar (`daily_events`): 400 gün
- Sunucudaki sohbet geçmişi (`chat_history`): 365 gün
- Gönderilen hatırlatıcı defteri (`push_sends`): 30 gün
- Kullanılmayan cihaz kayıtları (`device_tokens`): son görülmeden 180 gün sonra
- Günlük check-in kayıtları (`daily_logs`): 730 gün
- Aktif olmayan rutinler: 730 gün
- Artık bir rutin tarafından kullanılmayan değerlendirmeler: 730 gün
- Aktif profil ve aktif rutin: hesap açık olduğu sürece
- Hukuki rıza kanıtı: hesap açık olduğu sürece; hesap silmede cascade ile silinir
- Cilt fotoğrafları: kullanıcı silene veya hesabını kapatana kadar
- Tarayıcı check-in özeti: en fazla 120 gün
- Tarayıcı sohbet geçmişi: kullanıcı başına son 30 mesaj; kullanıcı temizleyene veya hesabını silene kadar

`pg_cron` bulunan Supabase projelerinde temizlik günlük otomatik zamanlanır.
Bulunmayan ortamlarda operasyon görevi günlük olarak şu fonksiyonu çağırmalıdır:

```sql
select public.purge_expired_rebi_data();
```

Hesap silme işlemi bu süreleri beklemez; fotoğraflar, uygulama tabloları ve Auth hesabı doğrudan kaldırılır.
