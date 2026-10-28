import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/i18n.dart';
import 'package:rebi/core/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('çeviriler uygulama paketinden yüklenir (pubspec assets tanımlı)', () async {
    SharedPreferences.setMockInitialValues({'rebi-lang': 'tr'});
    await LocalStore.init();
    await I18n.instance.init();
    expect(I18n.instance.t('nav.home'), isNot('nav.home'));
    expect(Pack(I18n.instance.analyzeWizardPack).s('gender.female'), 'Kadın');
    expect(I18n.instance.severityTestsPack['acne'], isA<Map>());
    await I18n.instance.changeLanguage('en');
    expect(Pack(I18n.instance.analyzeWizardPack).s('gender.female'), 'Female');
  });

  setUp(() {
    I18n.instance.debugLoad(common: {
      'tr': {
        'a': {'hello': 'Merhaba {{name}}', 'empty': ''},
        'days': ['Pzt', 'Sal'],
      },
      'en': {
        'a': {'hello': 'Hello {{name}}', 'onlyEn': 'Only EN', 'empty': 'x'},
      },
    }, lang: 'tr');
  });

  test('etkin dil, yoksa İngilizce, yoksa varsayılan, yoksa anahtar', () {
    final i = I18n.instance;
    expect(i.t('a.hello', {'name': 'Ayşe'}), 'Merhaba Ayşe');
    expect(i.t('a.onlyEn'), 'Only EN');
    expect(i.t('a.missing', const {}, 'Yedek'), 'Yedek');
    expect(i.t('a.missing'), 'a.missing');
  });

  test('boş metin geçerli çeviridir (i18next returnEmptyString)', () {
    expect(I18n.instance.t('a.empty'), '');
  });

  test('dizi metinler', () {
    expect(I18n.instance.tList('days', const ['Mon']), ['Pzt', 'Sal']);
    expect(I18n.instance.tList('nope', const ['Mon']), ['Mon']);
  });

  test('tr dışında yerelleştirilmiş alanlar tercih edilir', () {
    expect(I18n.instance.prefersLocalized, isFalse);
  });
}
