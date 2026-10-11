import 'api.dart';

Future<Map<String, dynamic>> _check(ApiResponse res) async {
  if (!res.ok) throw Exception(detailOr(res.data, 'Gizlilik tercihi işlemi başarısız.'));
  return res.data;
}

Future<Map<String, dynamic>> getPrivacyPreferences(String userId) async =>
    _check(await apiGet('/privacy-preferences', query: {'user_id': userId}));

Future<Map<String, dynamic>> updatePrivacyPreferences(
  String userId, {
  required bool location,
  required bool photo,
}) async =>
    _check(await apiPost('/privacy-preferences', {
      'user_id': userId,
      'ai_processing_allowed': true,
      'location_processing_allowed': location,
      'photo_processing_allowed': photo,
    }));
