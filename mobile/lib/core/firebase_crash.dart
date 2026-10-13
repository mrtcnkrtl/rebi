import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'crash_reporter.dart';

/// Crashlytics çağrılarını soyutlar; testlerde sahtesi kullanılır.
abstract interface class CrashlyticsPort {
  Future<void> setCollectionEnabled(bool enabled);
  Future<void> recordError(Object error, StackTrace stack, {required bool fatal, String? reason});
}

class _FirebaseCrashlyticsPort implements CrashlyticsPort {
  FirebaseCrashlytics get _c => FirebaseCrashlytics.instance;

  @override
  Future<void> setCollectionEnabled(bool enabled) => _c.setCrashlyticsCollectionEnabled(enabled);

  @override
  Future<void> recordError(Object error, StackTrace stack, {required bool fatal, String? reason}) =>
      _c.recordError(error, stack, fatal: fatal, reason: reason);
}

/// [CrashReporter]'ı Firebase Crashlytics'e bağlar. Yalnızca Firebase başarıyla başlatıldıktan sonra
/// (`FIREBASE_ENABLED=true` ve proje dosyaları var) kurulur; aksi halde konsol raporlayıcısı kalır.
/// Debug derlemelerinde toplama kapalıdır (geliştirme hataları panoyu doldurmasın).
class FirebaseCrashReporter implements CrashReporter {
  FirebaseCrashReporter._(this._port);

  final CrashlyticsPort _port;

  /// Kurulamazsa (Firebase eklentisi hazır değil) null döner; uygulama konsol raporlayıcısıyla sürer.
  static Future<CrashReporter?> create({CrashlyticsPort? port, bool? collect}) async {
    try {
      final p = port ?? _FirebaseCrashlyticsPort();
      await p.setCollectionEnabled(collect ?? !kDebugMode);
      return FirebaseCrashReporter._(p);
    } catch (e) {
      debugPrint('Crashlytics başlatılamadı, hata raporlama konsolda: $e');
      return null;
    }
  }

  @override
  void record(CrashReport report) {
    final error = '${report.type}: ${report.message}';
    // Gönderim beklenmez; başarısızlığı uygulamayı etkilemez.
    unawaited(
      _port
          .recordError(error, StackTrace.fromString(report.stack), fatal: report.fatal, reason: report.library)
          .catchError((Object _) {}),
    );
  }
}
