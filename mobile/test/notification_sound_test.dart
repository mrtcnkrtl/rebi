import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/notification_sound.dart';

/// Bildirim sesi: dosyalar iki platformda yerinde, geçerli ve platform sınırları içinde; kanal ve ses adları (Android, iOS, manifest,
/// kaynak küçültme) birbirini tutuyor. Biri bozulursa bildirim sessizce sistem varsayılan sesine düşer, bu yüzden dosyada denetlenir.
/// Sunucu tarafının aynı adları kullandığı `backend/tests/test_push_sound_contract.py`'de denetlenir.
void main() {
  final android = File('android/app/src/main/res/raw/$reminderSoundResource.wav');
  final ios = File('ios/Runner/$reminderSoundFile');

  /// 16 bit PCM WAV: (örnekleme, kanal, bit, örnekler -1..1).
  ({int rate, int channels, int bits, Float64List samples}) readWav(File f) {
    final b = f.readAsBytesSync();
    final v = ByteData.sublistView(b);
    expect(String.fromCharCodes(b.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(b.sublist(8, 12)), 'WAVE');
    var pos = 12;
    int rate = 0, channels = 0, bits = 0;
    Float64List? samples;
    while (pos + 8 <= b.length) {
      final id = String.fromCharCodes(b.sublist(pos, pos + 4));
      final size = v.getUint32(pos + 4, Endian.little);
      final body = pos + 8;
      if (id == 'fmt ') {
        expect(v.getUint16(body, Endian.little), 1, reason: 'doğrusal PCM (iOS ve Android çalar)');
        channels = v.getUint16(body + 2, Endian.little);
        rate = v.getUint32(body + 4, Endian.little);
        bits = v.getUint16(body + 14, Endian.little);
      } else if (id == 'data') {
        final n = size ~/ 2;
        samples = Float64List(n);
        for (var i = 0; i < n; i++) {
          samples[i] = v.getInt16(body + i * 2, Endian.little) / 32768;
        }
      }
      pos = body + size + (size.isOdd ? 1 : 0);
    }
    return (rate: rate, channels: channels, bits: bits, samples: samples!);
  }

  group('ses dosyası', () {
    test('Android ve iOS dosyaları yerinde ve birebir aynı', () {
      expect(android.existsSync(), isTrue, reason: 'res/raw/$reminderSoundResource.wav');
      expect(ios.existsSync(), isTrue, reason: 'ios/Runner/$reminderSoundFile');
      expect(android.readAsBytesSync(), ios.readAsBytesSync());
    });

    test('geçerli, kısa ve duyulur: 16 bit mono WAV, 0,5–3 sn, kırpılma yok, tık yok', () {
      final w = readWav(android);
      expect((w.rate, w.channels, w.bits), (44100, 1, 16));
      final seconds = w.samples.length / w.rate;
      expect(seconds, inInclusiveRange(.5, 3), reason: 'bildirim sesi kısa olur (iOS sınırı 30 sn)');
      expect(android.lengthSync(), lessThan(400 * 1024));

      final peak = w.samples.map((s) => s.abs()).reduce(math.max);
      expect(peak, lessThan(.95), reason: 'kırpılma / bozulma yok');
      expect(peak, greaterThan(.5), reason: 'yeterince duyulur');
      final rms = math.sqrt(w.samples.fold<double>(0, (a, s) => a + s * s) / w.samples.length);
      expect(20 * math.log(rms) / math.ln10, greaterThan(-26), reason: 'telefonda ortam gürültüsünde de duyulur');

      expect(w.samples.first.abs(), lessThan(.01), reason: 'başlangıçta tık yok (yumuşak giriş)');
      expect(w.samples.last.abs(), lessThan(.002), reason: 'sonda aniden kesilmez (yumuşak kapanış)');
    });
  });

  group('platform bağlantıları', () {
    test('Android: kaynak küçültme sesi silmez', () {
      final keep = File('android/app/src/main/res/raw/keep.xml').readAsStringSync();
      expect(keep, contains('@raw/$reminderSoundResource'));
    });

    test('Android: FCM varsayılan kanalı yeni kanal; eski kanal bırakılan listede', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:value="$reminderChannelId"'));
      expect(reminderChannelId, isNot(isIn(legacyReminderChannelIds)));
      expect(legacyReminderChannelIds, contains('rebi_reminders'), reason: 'sessiz/varsayılan sesli v1 kanalı silinir');
    });

    test('iOS: ses dosyası projeye ve "Copy Bundle Resources"a eklidir (yoksa iOS varsayılan sesi çalar)', () {
      final project = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      expect(project, contains('$reminderSoundFile in Resources'));
      expect(RegExp(r'path = ' + RegExp.escape(reminderSoundFile) + r';').hasMatch(project), isTrue);
      expect(project, contains('lastKnownFileType = audio.wav'));
    });

    test('yerel bildirimler kanalı ve sesi bu sabitlerle kurar', () {
      final src = File('lib/core/local_notifications.dart').readAsStringSync();
      expect(src, contains('const _channelId = reminderChannelId;'));
      expect(src, contains('RawResourceAndroidNotificationSound(reminderSoundResource)'));
      expect(src, contains('sound: reminderSoundFile'));
      expect(src, contains('legacyReminderChannelIds'));
    });
  });
}
