import 'api.dart';
import 'local_store.dart';

/// Sürümlü KVKK + açık rıza kaydı. Asıl kanıt backend tablosundadır.
const legalConsentVersion = 'v2';

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
  if (!res.ok) throw Exception(detailOr(res.data, 'Rıza kaydı oluşturulamadı.'));
  await saveLegalConsent(userId, res.data['accepted_at']?.toString(), p);
  return res.data;
}
