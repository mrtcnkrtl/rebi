import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'api.dart';
import 'consent_recovery.dart';
import 'demo_user.dart';
import 'local_store.dart';

/// Sürümlü KVKK + açık rıza kaydı. Asıl kanıt backend tablosundadır.
const legalConsentVersion = 'v2';

/// Kayıt formundaki seçimlerin Supabase `user_metadata` içindeki anahtarı.
const _metadataKey = 'legal_consent';

String _storageKey(String userId) => 'rebi_legal_consent_${legalConsentVersion}_$userId';

class ConsentPermissions {
  const ConsentPermissions({this.ai = false, this.location = false, this.photo = false});

  final bool ai;
  final bool location;
  final bool photo;
}

Future<void> saveLegalConsent(String userId, String? acceptedAt, ConsentPermissions p) async {
  if (userId.isEmpty) return;
  await LocalStore.instance.setJson(_storageKey(userId), {
    'version': legalConsentVersion,
    'kvkk': true,
    'riza': true,
    'ai': p.ai,
    'location': p.location,
    'photo': p.photo,
    'acceptedAt': acceptedAt ?? DateTime.now().toUtc().toIso8601String(),
  });
}

Future<Map<String, dynamic>> recordLegalConsent(String? userId, ConsentPermissions p) async {
  if (userId == null || userId.isEmpty) {
    throw Exception('Rıza kaydı için kullanıcı oturumu bulunamadı.');
  }
  final res = await apiPost('/legal-consent/accept', {
    'user_id': userId,
    'document_version': legalConsentVersion,
    'kvkk_accepted': true,
    'explicit_consent_accepted': true,
    'ai_processing_accepted': p.ai,
    'location_processing_accepted': p.location,
    'photo_processing_accepted': p.photo,
  });
  if (!res.ok) {
    // Sunucu açıklama (`detail`) vermeden hata döndürdüyse (ör. 500 "Internal Server Error", ağ geçidi hatası)
    // kullanıcıya ve destek ekibine durum kodu da gösterilir; yalnız "oluşturulamadı" nedeni anlatmaz.
    final detail = detailOr(res.data, '');
    throw Exception(detail.isNotEmpty ? detail : 'Rıza kaydı oluşturulamadı (sunucu yanıtı: ${res.status}).');
  }
  await saveLegalConsent(userId, res.data['accepted_at']?.toString(), p);
  notifyConsentChanged();
  return res.data;
}

/// Kayıt formunda verilen rıza. E-posta onayı beklenirken oturum olmadığı için sunucuya o an yazılamaz; seçimler
/// Supabase kullanıcı bilgisine (`user_metadata`) konur ve ilk oturum açılışında [syncPendingLegalConsent] ile kayda geçer.
/// Kanıt yine sunucudaki `legal_consents` satırıdır; buradaki değer yalnızca seçimi taşır.
Map<String, dynamic> legalConsentMetadata(ConsentPermissions p, [DateTime? now]) => {
      'version': legalConsentVersion,
      'kvkk': true,
      'riza': true,
      'ai': p.ai,
      'location': p.location,
      'photo': p.photo,
      'accepted_at_client': (now ?? DateTime.now()).toUtc().toIso8601String(),
    };

/// `user_metadata` içindeki bekleyen rıza; yok, eksik onaylı ya da eski sürümse null.
ConsentPermissions? pendingConsentFromMetadata(Map<String, dynamic>? userMetadata) {
  final raw = userMetadata?[_metadataKey];
  if (raw is! Map) return null;
  if (raw['version'] != legalConsentVersion || raw['kvkk'] != true || raw['riza'] != true || raw['ai'] != true) return null;
  return ConsentPermissions(ai: true, location: raw['location'] == true, photo: raw['photo'] == true);
}

/// Kayıtta verilen rızayı ilk oturum açılışında sunucuya yazar (e-posta onayı bağlantısı da dahil).
/// Giriş ekranında rıza kutusu olmadığı için rıza buradan kayda geçer. Hiçbir hata fırlatmaz ve girişi engellemez:
/// yazılamazsa oturum açık ama rıza eksik kalır, açılış paketi bunu görüp rıza kutusunu açar.
/// Sunucuda zaten kayıt varsa üzerine yazmaz (kullanıcının sonradan değiştirdiği izinleri bozmamak için).
Future<void> syncPendingLegalConsent(User user) async {
  if (user.id.isEmpty || user.id == demoUserId) return;
  final pending = pendingConsentFromMetadata(user.userMetadata);
  if (pending == null) return;
  if (LocalStore.instance.getJson(_storageKey(user.id)) != null) return;
  try {
    final status = await apiGet('/legal-consent/status', query: {'user_id': user.id});
    if (!status.ok) return;
    if (status.data['accepted'] == true) {
      await saveLegalConsent(
        user.id,
        status.data['accepted_at']?.toString(),
        ConsentPermissions(
          ai: status.data['ai_processing_accepted'] == true,
          location: status.data['location_processing_accepted'] == true,
          photo: status.data['photo_processing_accepted'] == true,
        ),
      );
      notifyConsentChanged();
      return;
    }
    await recordLegalConsent(user.id, pending);
  } catch (_) {
    /* çevrimdışı ya da sunucu hatası: rıza kutusu yedek olarak açılır */
  }
}
