
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/crash_reporter.dart';
import 'package:rebi/core/device_location.dart';

class _Recorder implements CrashReporter {
  final reports = <CrashReport>[];

  @override
  void record(CrashReport report) => reports.add(report);
}

class _Throwing implements CrashReporter {
  @override
  void record(CrashReport report) => throw StateError('servis çöktü');
}

void main() {
  late _Recorder recorder;
  late DateTime now;

  setUp(() {
    recorder = _Recorder();
    now = DateTime(2026, 10, 13, 12);
    CrashReporting.reset();
    CrashReporting.reporter = recorder;
    CrashReporting.clock = () => now;
  });

  tearDown(CrashReporting.reset);

  group('CrashReporting.report', () {
    test('tür, ileti, yığın ve bayrakları iletir', () {
      CrashReporting.report(const FormatException('bozuk'), StackTrace.fromString('#0 f (a.dart:1)'), fatal: true, library: 'rendering');
      final r = recorder.reports.single;
      expect(r.type, 'FormatException');
      expect(r.message, contains('bozuk'));
      expect(r.stack, contains('a.dart:1'));
      expect(r.fatal, isTrue);
      expect(r.library, 'rendering');
    });

    test('yığın yoksa boş yığınla da çalışır', () {
      CrashReporting.report('düz metin hata', null, fatal: false);
      expect(recorder.reports.single.type, 'String');
    });

    test('uzun ileti ve yığın kısaltılır', () {
      CrashReporting.report(Exception('x' * 1000), StackTrace.fromString('y' * 9000), fatal: false);
      final r = recorder.reports.single;
      expect(r.message.length, CrashReporting.maxMessageLength + 1, reason: 'kesilen metin + …');
      expect(r.message.endsWith('…'), isTrue);
      expect(r.stack.length, CrashReporting.maxStackLength + 1);
    });

    test('aynı hata süre dolmadan tekrar raporlanmaz, sonra yine raporlanır', () {
      final stack = StackTrace.fromString('#0 çizim');
      CrashReporting.report(StateError('taşma'), stack, fatal: false);
      CrashReporting.report(StateError('taşma'), stack, fatal: false);
      now = now.add(const Duration(seconds: 59));
      CrashReporting.report(StateError('taşma'), stack, fatal: false);
      expect(recorder.reports, hasLength(1));

      now = now.add(const Duration(seconds: 2));
      CrashReporting.report(StateError('taşma'), stack, fatal: false);
      expect(recorder.reports, hasLength(2));
    });

    test('farklı hatalar ayrı ayrı raporlanır', () {
      final stack = StackTrace.fromString('#0 a');
      CrashReporting.report(StateError('bir'), stack, fatal: false);
      CrashReporting.report(StateError('iki'), stack, fatal: false);
      CrashReporting.report(StateError('bir'), StackTrace.fromString('#0 b'), fatal: false);
      expect(recorder.reports, hasLength(3));
    });

    test('raporlayıcı hata verirse yutulur', () {
      CrashReporting.reporter = _Throwing();
      expect(() => CrashReporting.report(StateError('x'), null, fatal: true), returnsNormally);
    });
  });

  group('installCrashHandlers', () {
    late FlutterExceptionHandler? oldOnError;
    late void Function(FlutterErrorDetails) oldPresent;
    late bool Function(Object, StackTrace)? oldPlatformOnError;

    setUp(() {
      oldOnError = FlutterError.onError;
      oldPresent = FlutterError.presentError;
      oldPlatformOnError = PlatformDispatcher.instance.onError;
      FlutterError.presentError = (_) {};
    });

    tearDown(() {
      FlutterError.onError = oldOnError;
      FlutterError.presentError = oldPresent;
      PlatformDispatcher.instance.onError = oldPlatformOnError;
    });

    test('çerçeve hatası raporlanır, ölümcül sayılmaz', () {
      installCrashHandlers();
      FlutterError.onError!(FlutterErrorDetails(exception: StateError('çizim'), stack: StackTrace.current, library: 'widgets library'));
      final r = recorder.reports.single;
      expect(r.fatal, isFalse);
      expect(r.library, 'widgets library');
      expect(r.type, 'StateError');
    });

    test('yakalanmamış asenkron hata ölümcül raporlanır ve işlenmiş sayılır', () {
      installCrashHandlers();
      final handled = PlatformDispatcher.instance.onError!(StateError('async'), StackTrace.current);
      expect(handled, isTrue, reason: 'uygulama kapanmasın');
      expect(recorder.reports.single.fatal, isTrue);
    });
  });

  group('konum yuvarlama', () {
    test('iki ondalığa (~1 km) yuvarlar', () {
      expect(roundCoordinate(41.015137), 41.02);
      expect(roundCoordinate(28.979530), 28.98);
      expect(roundCoordinate(-33.8688), -33.87);
      expect(roundCoordinate(0.004), 0.0);
    });
  });
}
