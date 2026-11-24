import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/analyze_draft.dart';
import 'package:rebi/core/local_store.dart';
import 'package:rebi/core/privacy_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const uid = '11111111-1111-4111-8111-111111111111';
  const other = '22222222-2222-4222-8222-222222222222';

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      analyzeDraftKey(uid): '{"step":2}',
      'rebi-weather-place_$uid': '{"mode":"manual"}',
      'rebi-weather-saved_$uid': '{"lat":41}',
      'rebi_step_choices_$uid': '{}',
      'rebi-chat-history_$uid': '[]',
      'rebi_analyze_draft_$other': '{"step":1}',
      'rebi-lang': 'tr',
    });
    await LocalStore.init();
  });

  test('hesap silinince o hesabın kimliğini taşıyan her yerel kayıt gider; başkasınınki ve cihaz ayarı kalır', () async {
    await clearUserLocalData(uid);

    final keys = (await SharedPreferences.getInstance()).getKeys();
    expect(keys.where((k) => k.contains(uid)), isEmpty);
    expect(keys, contains('rebi_analyze_draft_$other'));
    expect(keys, contains('rebi-lang'));
  });
}
