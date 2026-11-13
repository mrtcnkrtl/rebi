import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/screens/profile_screen.dart';

import 'helpers/app_harness.dart';

void main() {
  test('hesap silme: kullanıcı kendi dilinde yazar, sunucuya hep aynı onay metni gider', () {
    loadTestI18n('tr');
    expect(typedDeletePhrase, 'HESABIMI_SIL');
    loadTestI18n('en');
    expect(typedDeletePhrase, 'DELETE');
    expect(accountDeletePhrase, 'HESABIMI_SIL', reason: 'backend/main.py _ACCOUNT_DELETE_CONFIRM');
  });
}
