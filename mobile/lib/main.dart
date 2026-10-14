import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/env.dart';
import 'core/crash_reporter.dart';
import 'core/firebase_crash.dart';
import 'core/firebase_push.dart';
import 'core/i18n.dart';
import 'core/local_notifications.dart';
import 'core/local_store.dart';
import 'core/notification_ports.dart';
import 'router.dart';
import 'ui/tw.dart';

Future<void> main() async {
  await bootstrap();
  _installErrorBoundary();
  // Firebase yalnızca proje dosyaları eklenip FIREBASE_ENABLED=true verildiğinde başlatılır.
  final PushClient push = Env.firebaseEnabled ? await FirebasePushClient.create() : const NoPushClient();
  // Hata raporlama Firebase'e bağlı: yalnızca Firebase gerçekten başlatıldıysa Crashlytics devreye girer.
  if (Env.firebaseEnabled && Firebase.apps.isNotEmpty) {
    final reporter = await FirebaseCrashReporter.create();
    if (reporter != null) CrashReporting.reporter = reporter;
  }
  runApp(RebiApp(notifier: await LocalNotificationsNotifier.create(), push: push));
}

/// Uygulama çizilmeden önceki hazırlık: yerel depo, Supabase oturumu, tarih biçimleri, çeviriler.
/// Uçtan uca testler de bunu kullanır (hata sınırı test çerçevesininkini ezmesin diye ayrı).
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Inter'], await rootBundle.loadString('assets/fonts/Inter-LICENSE.txt'));
    yield LicenseEntryWithLineBreaks(['Fraunces'], await rootBundle.loadString('assets/fonts/Fraunces-LICENSE.txt'));
  });
  await LocalStore.init();
  if (Env.supabaseConfigured) {
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  }
  await initializeDateFormatting();
  await I18n.instance.init();
}

/// Web `ErrorBoundary.jsx` karşılığı: çizimde hata olursa boş/kırmızı ekran yerine
/// kullanıcı dostu kart gösterilir; geliştirmede hata metni de yazılır.
void _installErrorBoundary() {
  installCrashHandlers();
  ErrorWidget.builder = (details) => _ErrorCard(details: details);
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Tw.teal50,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 448),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(color: Tw.surface, borderRadius: BorderRadius.circular(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Tw.red100, borderRadius: BorderRadius.circular(16)),
                  child: const Text('😥', style: TextStyle(fontSize: 30)),
                ),
                const SizedBox(height: 16),
                Text('Bir Sorun Oluştu', style: tx(20, w: 7)),
                const SizedBox(height: 8),
                Text('Sayfa yüklenirken bir hata meydana geldi.', textAlign: TextAlign.center, style: tx(14, c: Tw.gray500)),
                if (kDebugMode) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Tw.red50, borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      details.exceptionAsString(),
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                      style: tx(12, c: Tw.red700).copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Material(
                  color: Tw.teal600,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      final ctx = rootNavigatorKey.currentContext;
                      if (ctx != null) GoRouter.of(ctx).go('/');
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      child: Text('Ana Sayfaya Dön', style: tx(14, w: 5, c: Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
