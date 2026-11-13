import 'api.dart';

/// Rebi Plus ön bilgilendirme ve mesafeli satış onayı. Kanıt backend tablosundadır.
const salesConsentVersion = 'v1';

Future<void> recordSalesConsent(String? userId) async {
  if (userId == null || userId.isEmpty) {
    throw Exception('Ödeme onayı için kullanıcı oturumu bulunamadı.');
  }
  final res = await apiPost('/sales-consent/accept', {
    'user_id': userId,
    'document_version': salesConsentVersion,
    'pre_info_accepted': true,
    'distance_contract_accepted': true,
  });
  if (!res.ok) throw Exception(detailOr(res.data, 'Ödeme onayı kaydedilemedi.'));
}
