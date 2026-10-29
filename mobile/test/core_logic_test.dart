import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/api.dart';
import 'package:rebi/core/checkin_stats.dart';
import 'package:rebi/core/consent_recovery.dart';
import 'package:rebi/core/daily_tracking.dart';
import 'package:rebi/core/image_quality.dart';
import 'package:rebi/core/interpolate.dart';
import 'package:rebi/router.dart';
import 'package:rebi/screens/analyze/analyze_screen.dart';
import 'package:rebi/screens/checkin_screen.dart';
import 'package:rebi/ui/components/severity_test.dart';

import 'helpers/app_harness.dart';

void main() {
  group('check-in serisi (web: lib/checkinStats.js)', () {
    final now = DateTime.utc(2026, 10, 10, 12);
    CheckInLogEntry e(String d) => CheckInLogEntry(d, true);

    test('bugünden geriye kesintisiz gün sayılır', () {
      expect(computeCheckInStreak([e('2026-10-10'), e('2026-10-09'), e('2026-10-08'), e('2026-10-06')], now: now), 3);
    });
    test('bugün yoksa dünden başlar', () {
      expect(computeCheckInStreak([e('2026-10-09'), e('2026-10-08')], now: now), 2);
    });
    test('dün de yoksa seri 0', () {
      expect(computeCheckInStreak([e('2026-10-08')], now: now), 0);
    });
    test('ay ve yıl sınırı', () {
      expect(ymdAddDays('2026-03-01', -1), '2026-02-28');
      expect(ymdAddDays('2026-01-01', -1), '2025-12-31');
    });
  });

  group('formatApiErrorDetail (web: lib/apiErrors.js)', () {
    setUp(loadTestI18n);
    test('string detail', () => expect(formatApiErrorDetail({'detail': 'Yetkisiz'}), 'Yetkisiz'));
    test('pydantic liste detayı birleştirilir', () {
      expect(
        formatApiErrorDetail({
          'detail': [
            {'msg': 'age alanı zorunlu'},
            'ikinci',
          ],
        }),
        'age alanı zorunlu ikinci',
      );
    });
    test('message alanı', () => expect(formatApiErrorDetail({'message': 'Hata'}), 'Hata'));
    test('boş gövde', () => expect(formatApiErrorDetail({}), 'İşlem tamamlanamadı. Bir süre sonra tekrar dene.'));
    test('null gövde', () => expect(formatApiErrorDetail(null), 'Sunucudan anlamlı bir yanıt alınamadı.'));
  });

  test('rıza hatası yalnızca 403 + "izni gerekli"', () {
    expect(isConsentError(403, {'detail': 'AI işleme izni gerekli'}), isTrue);
    expect(isConsentError(403, {'detail': 'Token ile user_id eşleşmiyor'}), isFalse);
    expect(isConsentError(401, {'detail': 'izni gerekli'}), isFalse);
  });

  test('interpolate: JS String() gibi sayı yazar, eksik değişken boş', () {
    expect(interpolate('{{n}} L su', {'n': 2.0}), '2 L su');
    expect(interpolate('{{n}} L su', {'n': 2.5}), '2.5 L su');
    expect(interpolate('{{a}}-{{b}}', {'a': 1}), '1-');
  });

  test('safeNext yalnızca uygulama içi yol kabul eder', () {
    expect(safeNext('/dashboard/chat'), '/dashboard/chat');
    expect(safeNext('//evil.com'), '/dashboard');
    expect(safeNext('https://evil.com'), '/dashboard');
    expect(safeNext(null), '/dashboard');
  });

  test('yerel zaman damgası saat dilimi içerir', () {
    final ts = localIsoTimestamp(DateTime(2026, 10, 4, 9, 12, 5));
    expect(ts, matches(RegExp(r'^2026-10-04T09:12:05[+-]\d{2}:\d{2}$')));
  });

  group('analiz sihirbazı hesapları', () {
    test('PSS-10 ters maddeler (4,5,7,8)', () {
      expect(pssScore(List.filled(10, 0)), 16);
      expect(pssScore(List.filled(10, 4)), 24);
      expect(pssScore([4, 4, 4, 0, 0, 4, 0, 0, 4, 4]), 40);
    });
    test('döngü evresi (UTC gece yarısından gün farkı)', () {
      final now = DateTime.utc(2026, 10, 10, 12);
      expect(calcCyclePhase('2026-10-08', 28, now: now), 'menstrual');
      expect(calcCyclePhase('2026-09-30', 28, now: now), 'follicular');
      expect(calcCyclePhase('2026-09-26', 28, now: now), 'ovulation');
      expect(calcCyclePhase('2026-09-20', 28, now: now), 'luteal');
      expect(calcCyclePhase('', 28, now: now), 'unknown');
    });
    test('şiddet skoru 1–10 aralığına normalize', () {
      expect(calculateSeverityScore({'a': 0, 'b': 0}, 6), 1);
      expect(calculateSeverityScore({'a': 3, 'b': 3}, 6), 10);
      expect(calculateSeverityScore({'a': 2, 'b': 1}, 6), 6);
    });
  });

  group('check-in su girişi', () {
    test('parseWaterMlInput', () {
      expect(parseWaterMlInput(''), isNull);
      expect(parseWaterMlInput('1500'), 1500);
      expect(parseWaterMlInput('1250,6'), 1251);
      expect(parseWaterMlInput('99999'), 8000);
      expect(parseWaterMlInput('-5'), isNull);
    });
    test('formatGlassesLabel', () {
      loadTestI18n();
      expect(formatGlassesLabel(0), '0 bardak');
      expect(formatGlassesLabel(2000), 'yaklaşık 8 bardak');
      expect(formatGlassesLabel(375), 'yaklaşık 1.5 bardak');
    });
  });

  group('foto kalite ölçümü (web: lib/imageQuality.js)', () {
    Uint8List solid(int w, int h, int v) {
      final b = Uint8List(w * h * 4);
      for (var i = 0; i < b.length; i += 4) {
        b[i] = v;
        b[i + 1] = v;
        b[i + 2] = v;
        b[i + 3] = 255;
      }
      return b;
    }

    test('karanlık ve düz görüntü: çok karanlık + bulanık', () {
      final q = computePhotoQuality(solid(20, 20, 20), 20, 20);
      expect(q.tooDark, isTrue);
      expect(q.tooBlurry, isTrue);
    });
    test('aydınlık ve dokulu görüntü: uygun', () {
      final rnd = math.Random(1);
      final b = Uint8List(40 * 40 * 4);
      for (var i = 0; i < b.length; i += 4) {
        final v = 60 + rnd.nextInt(180);
        b[i] = v;
        b[i + 1] = v;
        b[i + 2] = v;
        b[i + 3] = 255;
      }
      final q = computePhotoQuality(b, 40, 40);
      expect(q.tooDark, isFalse);
      expect(q.tooBlurry, isFalse);
      expect(q.meanLuma, greaterThan(.3));
    });
  });
}
