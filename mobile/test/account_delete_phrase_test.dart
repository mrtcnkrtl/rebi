import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/screens/profile_screen.dart';
import 'package:rebi/screens/account/delete_card.dart' show deletePhraseMatches;

import 'helpers/app_harness.dart';

void main() {
  test('hesap silme: kullanıcı kendi dilinde yazar, sunucuya hep aynı onay metni gider', () {
    loadTestI18n('tr');
    expect(typedDeletePhrase, 'HESABIMI SİL');
    loadTestI18n('en');
    expect(typedDeletePhrase, 'DELETE');
    expect(accountDeletePhrase, 'HESABIMI_SIL', reason: 'backend/main.py _ACCOUNT_DELETE_CONFIRM');
  });

  test('Türkçe klavyenin yazabileceği her biçim kabul edilir (İ/ı/i, boşluk, alt çizgi, küçük harf)', () {
    loadTestI18n('tr');
    for (final typed in [
      'HESABIMI SİL',
      'HESABİMİ SİL', // büyük harf kilidinde i tuşu: noktalı İ
      'HESABIMI_SIL', // eski ifade
      'hesabımı sil',
      'hesabimi sil',
      '  Hesabımı   Sil ',
      'HESABIMISIL',
      'hesabımı-sil',
    ]) {
      expect(deletePhraseMatches(typed), isTrue, reason: typed);
    }
    for (final typed in ['', '   ', 'HESABIMI', 'SİL', 'HESABINI SİL', 'DELETE']) {
      expect(deletePhraseMatches(typed), isFalse, reason: typed);
    }
  });

  test('İngilizcede DELETE, küçük harfle de', () {
    loadTestI18n('en');
    expect(deletePhraseMatches('delete'), isTrue);
    expect(deletePhraseMatches(' Delete '), isTrue);
    expect(deletePhraseMatches('HESABIMI SİL'), isFalse);
  });
}
