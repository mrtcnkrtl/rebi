import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter/rendering.dart' show debugDisableShadows;
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:rebi/core/skin_photos.dart';
import 'package:rebi/screens/journal_screen.dart';
import 'package:rebi/ui/components/photo_picker.dart';

import 'helpers/app_harness.dart';
import 'helpers/visual.dart';

class FakePhotoStore implements SkinPhotoStore {
  FakePhotoStore(this.photos);

  final List<SkinPhoto> photos;
  final uploads = <String>[];

  @override
  Future<List<SkinPhoto>> list(String userId) async => sortNewestFirst(photos);

  @override
  Future<void> upload(String userId, File file, String extension) async {
    uploads.add(extension);
    photos.add(SkinPhoto(path: '$userId/new.$extension', url: '', takenAt: DateTime.now()));
  }
}

SkinPhoto _photo(DateTime at) => SkinPhoto(path: 'u/${at.millisecondsSinceEpoch}.jpg', url: '', takenAt: at);

void main() {
  final original = skinPhotoStore;
  final originalPicker = journalPhotoPicker;
  tearDown(() {
    skinPhotoStore = original;
    journalPhotoPicker = originalPicker;
  });

  String md(DateTime d) => DateFormat.MMMd('tr').format(d);

  testWidgets('fotoğraf izni yoksa önce izin istenir; verilince günlük açılır', (tester) async {
    skinPhotoStore = FakePhotoStore([]);
    final backend = FakeBackend()..privacyPhoto = false;
    final h = await pumpApp(tester, location: '/dashboard/journal', backend: backend);
    expect(find.text(tr('mobileJournal.consentTitle')), findsOneWidget);
    expect(find.text(tr('mobileJournal.capture')), findsNothing, reason: 'izinsiz çekim düğmesi yok');

    await tapText(tester, tr('mobileJournal.consentCta'));
    expect(h.backend.privacyPhoto, isTrue);
    expect(find.text(tr('mobileJournal.emptyTitle')), findsOneWidget);
    expect(find.text(tr('mobileJournal.capture')), findsOneWidget);
  });

  testWidgets('iki ve daha fazla fotoğrafta ilk ile seçilen karşılaştırılır', (tester) async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 28));
    final mid = first.add(const Duration(days: 14));
    final last = first.add(const Duration(days: 21));
    skinPhotoStore = FakePhotoStore([_photo(mid), _photo(first), _photo(last)]);
    await pumpApp(tester, location: '/dashboard/journal', backend: FakeBackend()..privacyPhoto = true);

    expect(find.text('${tr('mobileJournal.before')} · ${md(first)}'), findsOneWidget);
    expect(find.text('${tr('mobileJournal.after')} · ${md(last)}'), findsOneWidget, reason: 'varsayılan "sonra" en yeni');
    expect(find.text(tr('mobileJournal.apart', {'n': 21})), findsOneWidget);
    expect(find.text(tr('mobileJournal.all', {'n': 3})), findsOneWidget);

    await tapText(tester, md(mid));
    expect(find.text('${tr('mobileJournal.after')} · ${md(mid)}'), findsOneWidget);
    expect(find.text(tr('mobileJournal.apart', {'n': 14})), findsOneWidget);
  });

  testWidgets('son fotoğraf bu haftaysa çekim ikincil olur ve sıradaki günü söyler', (tester) async {
    final today = DateTime.now();
    skinPhotoStore = FakePhotoStore([_photo(today.subtract(const Duration(days: 2)))]);
    await pumpApp(tester, location: '/dashboard/journal', backend: FakeBackend()..privacyPhoto = true);
    expect(find.text(tr('mobileJournal.oneBody')), findsOneWidget);
    expect(find.text(tr('mobileJournal.captureEarly')), findsOneWidget);
    expect(find.textContaining(tr('mobileJournal.next', {'day': ''}).trim()), findsOneWidget);
  });

  testWidgets('ipuçlarından kamera seçilince fotoğraf yüklenir ve olay kaydedilir', (tester) async {
    final store = FakePhotoStore([]);
    skinPhotoStore = store;
    ImageSource? asked;
    journalPhotoPicker = (source) async {
      asked = source;
      return PickedPhoto(XFile('selfie.jpg'), Uint8List(0));
    };
    final h = await pumpApp(tester, location: '/dashboard/journal', backend: FakeBackend()..privacyPhoto = true);
    await tapText(tester, tr('mobileJournal.capture'));
    expect(find.text(tr('mobileJournal.tipLight')), findsOneWidget);
    await tapText(tester, tr('mobileJournal.camera'));

    expect(asked, ImageSource.camera);
    expect(store.uploads, ['jpg']);
    final meta = [
      for (final r in h.backend.calls('/daily_tracking/ingest'))
        if ((jsonDecode(r.body) as Map)['type'] == 'photo_meta') jsonDecode(r.body) as Map,
    ];
    expect(meta, hasLength(1));
    expect(meta.single['payload']['flow'], 'journal');
    expect(find.text(tr('mobileJournal.saved')), findsOneWidget);
  });

  test('sıradaki fotoğraf günü: son fotoğraftan bir hafta sonra', () {
    final now = DateTime(2026, 11, 13, 10);
    expect(nextJournalPhotoDay(const [], now), isNull, reason: 'hiç yoksa hemen');
    expect(nextJournalPhotoDay([_photo(DateTime(2026, 11, 6, 9))], now), isNull, reason: '7. gün geldi');
    expect(nextJournalPhotoDay([_photo(DateTime(2026, 11, 10, 9))], now), DateTime(2026, 11, 16));
  });

  test('çekim zamanı dosya adından okunur', () {
    final at = DateTime(2026, 11, 1, 12);
    expect(photoTime('${at.millisecondsSinceEpoch}.jpg', null), at);
    expect(photoTime('kapak.jpg', '2026-10-01T10:00:00Z'), DateTime.parse('2026-10-01T10:00:00Z').toLocal());
  });

  group('görsel', () {
    setUpAll(() async {
      if (screenshotsEnabled) await loadBrandFonts();
    });

    for (final (name, count, photoOk) in [('gunluk-izin', 0, false), ('gunluk-bos', 0, true), ('gunluk-karsilastir', 3, true)]) {
      testWidgets(name, (tester) async {
        if (!screenshotsEnabled) return;
        final now = DateTime.now();
        skinPhotoStore = FakePhotoStore([for (var i = 0; i < count; i++) _photo(now.subtract(Duration(days: 3 + i * 10)))]);
        debugDisableShadows = false;
        try {
          await pumpApp(tester, location: '/dashboard/journal', backend: FakeBackend()..privacyPhoto = photoOk, realFonts: true, size: const Size(390, 1100));
          await shoot(tester, name);
        } finally {
          debugDisableShadows = true;
        }
      });
    }
  });
}
