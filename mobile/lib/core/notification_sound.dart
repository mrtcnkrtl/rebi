/// Rebi bildirim sesi ve kanalı: Android kanalı, iOS ses dosyası ve sunucu (FCM) aynı adları kullanır; tek kaynak burasıdır.
/// Ses `tool/make_notification_sound.py` ile üretilir (özgün, sentezlenmiş iki notalı "çınlama"; harici dosya/lisans yok).
/// `backend/tests/test_push_sound_contract.py` bu sabitleri sunucudakilerle karşılaştırır, `test/notification_sound_test.dart`
/// dosyaların yerinde ve geçerli olduğunu denetler.
library;

/// Android bildirim kanalı. **Kanalın sesi oluştuktan sonra değiştirilemez**; sesi değiştirirsen kimliği artır (`_v3`…) ve eskisini
/// [legacyReminderChannelIds]e ekle. `AndroidManifest.xml` (`default_notification_channel_id`) ve sunucu aynı kimliği kullanır.
const reminderChannelId = 'rebi_reminders_v2';

/// Artık kullanılmayan kanallar: uygulama açılırken silinir (v1 varsayılan sistem sesiyle açılmıştı).
const legacyReminderChannelIds = ['rebi_reminders'];

/// Android: `android/app/src/main/res/raw/rebi_chime.wav` (uzantısız ad; `keep.xml` kaynak küçültmeden korur).
const reminderSoundResource = 'rebi_chime';

/// iOS: `ios/Runner/rebi_chime.wav` (uygulama paketinde; iOS bildirim sesini paket kökünden çalar, en çok 30 sn).
const reminderSoundFile = 'rebi_chime.wav';
