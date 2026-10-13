import 'package:flutter/foundation.dart';

/// Bir hata kaydı. Kişisel veri sızmasın diye yalnızca tür, kısaltılmış ileti ve yığın taşınır;
/// kullanıcı kimliği, e-posta ya da istek gövdesi eklenmez.
class CrashReport {
  const CrashReport({required this.type, required this.message, required this.stack, required this.fatal, this.library});

  /// `error.runtimeType`
  final String type;
  final String message;
  final String stack;

  /// Uygulamayı çökertecek türden mi (yakalanmamış asenkron hata) yoksa çizim hatası mı.
  final bool fatal;
  final String? library;
}

/// Hata raporlama servisi (Sentry, Crashlytics…) için tek takılma noktası. Servis seçilince bu arayüzü
/// uygulayan sınıf `CrashReporting.reporter`'a atanır; uygulama kodu başka hiçbir yere dokunmaz.
/// Hata raporlayıcının kendisi hata verirse yutulur: raporlama uygulamayı asla düşürmemeli.
abstract interface class CrashReporter {
  void record(CrashReport report);
}

/// Varsayılan: yalnızca konsola yazar (servis seçilene kadar).
class ConsoleCrashReporter implements CrashReporter {
  const ConsoleCrashReporter();

  @override
  void record(CrashReport report) {
    debugPrint('${report.fatal ? 'Yakalanmamış hata' : 'Hata'} (${report.type}): ${report.message}\n${report.stack}');
  }
}

class CrashReporting {
  CrashReporting._();

  static const maxMessageLength = 300;
  static const maxStackLength = 4000;

  /// Aynı hata bu süre içinde tekrar gelirse (örn. her karede çizim hatası) bir kez raporlanır.
  static const dedupeWindow = Duration(seconds: 60);

  static CrashReporter reporter = const ConsoleCrashReporter();

  /// Testlerde saati sabitlemek için.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  static final Map<String, DateTime> _recent = {};

  static void report(Object error, StackTrace? stack, {required bool fatal, String? library}) {
    try {
      final message = _truncate(error.toString(), maxMessageLength);
      final trace = _truncate((stack ?? StackTrace.empty).toString(), maxStackLength);
      final now = clock();
      final key = '${error.runtimeType}|$message|${trace.hashCode}';
      final last = _recent[key];
      if (last != null && now.difference(last) < dedupeWindow) return;
      if (_recent.length > 50) _recent.removeWhere((_, at) => now.difference(at) >= dedupeWindow);
      _recent[key] = now;
      reporter.record(CrashReport(type: error.runtimeType.toString(), message: message, stack: trace, fatal: fatal, library: library));
    } catch (_) {
      /* raporlama hatası yutulur */
    }
  }

  @visibleForTesting
  static void reset() {
    _recent.clear();
    reporter = const ConsoleCrashReporter();
    clock = DateTime.now;
  }

  static String _truncate(String text, int max) => text.length <= max ? text : '${text.substring(0, max)}…';
}

/// Çerçeve ve yakalanmamış asenkron hataları [CrashReporting]'e yönlendirir. Çizim hataları ekranda
/// yine `ErrorWidget.builder` ile gösterilir; burada yalnızca raporlama bağlanır.
void installCrashHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    CrashReporting.report(details.exception, details.stack, fatal: false, library: details.library);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    CrashReporting.report(error, stack, fatal: true);
    return true;
  };
}
