import 'package:flutter/foundation.dart';

import 'local_store.dart';

/// Üçüncü taraf yapay zekâ (Google Gemini API) ile veri paylaşımı için uygulama içi izin.
///
/// App Store 5.1.1(i) / 5.1.2(i): veri gönderilmeden önce neyin, kime gittiği uygulamanın kendi ekranında
/// söylenmeli ve kullanıcıdan izin alınmalı; yalnızca KVKK/açık rıza metninde geçmesi yetmez. Sunucudaki
/// `ai_processing_allowed` hukuki kayıttır; bu bayrak o kaydın yanında, gönderimden hemen önce sorulan izni tutar.
/// Kullanıcı başına ve sürümlüdür: metin anlamca değişirse sürüm artırılıp izin yeniden istenir.
const aiSharingVersion = 'v1';

String aiSharingKey(String userId) => 'rebi-ai-sharing-${aiSharingVersion}_$userId';

bool hasAiSharingConsent(String? userId) {
  if (userId == null || userId.isEmpty) return false;
  return LocalStore.instance.getString(aiSharingKey(userId)) == '1';
}

Future<void> setAiSharingConsent(String userId, bool allowed) async {
  if (userId.isEmpty) return;
  if (allowed) {
    await LocalStore.instance.setString(aiSharingKey(userId), '1');
  } else {
    await LocalStore.instance.remove(aiSharingKey(userId));
  }
  aiSharingChanges.value++;
}

/// İzin verildiğinde ya da geri alındığında artar; açık izin kutuları bunu dinleyip kapanır.
final ValueNotifier<int> aiSharingChanges = ValueNotifier<int>(0);
