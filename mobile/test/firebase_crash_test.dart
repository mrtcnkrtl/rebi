import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/crash_reporter.dart';
import 'package:rebi/core/firebase_crash.dart';

class _FakePort implements CrashlyticsPort {
  bool? collection;
  final recorded = <({Object error, String stack, bool fatal, String? reason})>[];
  bool failCollection = false;
  bool failRecord = false;

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    if (failCollection) throw StateError('Firebase hazır değil');
    collection = enabled;
  }

  @override
  Future<void> recordError(Object error, StackTrace stack, {required bool fatal, String? reason}) async {
    if (failRecord) throw StateError('ağ yok');
    recorded.add((error: error, stack: stack.toString(), fatal: fatal, reason: reason));
  }
}

void main() {
  const report = CrashReport(type: 'StateError', message: 'bozuk durum', stack: '#0 f (a.dart:1)', fatal: true, library: 'widgets library');

  test('toplamayı ayarlar ve raporu türüyle birlikte iletir', () async {
    final port = _FakePort();
    final reporter = await FirebaseCrashReporter.create(port: port, collect: true);
    expect(reporter, isNotNull);
    expect(port.collection, isTrue);

    reporter!.record(report);
    await Future<void>.delayed(Duration.zero);
    final r = port.recorded.single;
    expect(r.error, 'StateError: bozuk durum');
    expect(r.stack, contains('a.dart:1'));
    expect(r.fatal, isTrue);
    expect(r.reason, 'widgets library');
  });

  test('debug derlemesinde (varsayılan) toplama kapalı kurulur', () async {
    final port = _FakePort();
    await FirebaseCrashReporter.create(port: port);
    expect(port.collection, isFalse, reason: 'testler debug modunda çalışır');
  });

  test('Firebase hazır değilse null döner (konsol raporlayıcısı kalır)', () async {
    final port = _FakePort()..failCollection = true;
    expect(await FirebaseCrashReporter.create(port: port, collect: true), isNull);
  });

  test('gönderim hatası yutulur ve uygulamayı etkilemez', () async {
    final port = _FakePort()..failRecord = true;
    final reporter = (await FirebaseCrashReporter.create(port: port, collect: true))!;
    expect(() => reporter.record(report), returnsNormally);
    await Future<void>.delayed(Duration.zero);
  });

  test('CrashReporting üzerinden bağlanınca raporlar Crashlytics\'e gider', () async {
    final port = _FakePort();
    CrashReporting.reset();
    addTearDown(CrashReporting.reset);
    CrashReporting.reporter = (await FirebaseCrashReporter.create(port: port, collect: true))!;
    CrashReporting.report(StateError('x'), StackTrace.fromString('#0 y'), fatal: false);
    await Future<void>.delayed(Duration.zero);
    expect(port.recorded, hasLength(1));
    expect(port.recorded.single.fatal, isFalse);
  });
}
