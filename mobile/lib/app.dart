import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'core/i18n.dart';
import 'core/notification_ports.dart';
import 'router.dart';
import 'state/auth_controller.dart';
import 'state/home_sync_controller.dart';
import 'state/notifications_controller.dart';
import 'state/outbox_sync_controller.dart';
import 'state/theme_controller.dart';
import 'ui/tw.dart';

class RebiApp extends StatefulWidget {
  const RebiApp({super.key, this.notifier, this.push});

  /// Yerel bildirim kurucusu; verilmezse bildirimler kapalıdır (web, testler).
  final ReminderNotifier? notifier;

  /// Sunucu push istemcisi (Firebase); verilmezse yalnızca yerel bildirim.
  final PushClient? push;

  @override
  State<RebiApp> createState() => _RebiAppState();
}

class _RebiAppState extends State<RebiApp> {
  late final AuthController _auth = AuthController();
  late final ThemeController _theme = ThemeController(_auth);
  late final HomeSyncController _sync = HomeSyncController(_auth);
  late final OutboxSyncController _outbox = OutboxSyncController(_auth);
  late final NotificationsController _notifications = NotificationsController(
    _auth,
    notifier: widget.notifier ?? const UnsupportedNotifier(),
    push: widget.push ?? const NoPushClient(),
    appVersion: _appVersion,
  );

  static Future<String?> _appVersion() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _notifications.openRoute.addListener(_openFromNotification);
    _openFromNotification();
  }

  /// Bildirime dokunulunca ilgili ekrana gider (uygulama kapalıyken açıldıysa ilk ekran o olur).
  void _openFromNotification() {
    final route = _notifications.openRoute.value;
    if (route == null) return;
    _notifications.openRoute.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _router.go(route));
  }
  late final GoRouter _router = buildRouter(_auth);

  @override
  void dispose() {
    _router.dispose();
    _notifications.dispose();
    _outbox.dispose();
    _sync.dispose();
    _theme.dispose();
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<I18n>.value(value: I18n.instance),
        ChangeNotifierProvider<AuthController>.value(value: _auth),
        ChangeNotifierProvider<ThemeController>.value(value: _theme),
        ChangeNotifierProvider<HomeSyncController>.value(value: _sync),
        ChangeNotifierProvider<OutboxSyncController>.value(value: _outbox),
        ChangeNotifierProvider<NotificationsController>.value(value: _notifications),
      ],
      child: Consumer<I18n>(
        builder: (context, i18n, _) => MaterialApp.router(
          title: 'Rebi',
          debugShowCheckedModeBanner: false,
          routerConfig: _router,
          locale: Locale(i18n.lang),
          supportedLocales: [for (final l in supportedLangs) Locale(l)],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: _buildTheme(),
        ),
      ),
    );
  }

  ThemeData _buildTheme() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Tw.teal600, primary: Tw.teal600, surface: Colors.white),
      scaffoldBackgroundColor: Colors.white,
      splashFactory: InkSparkle.splashFactory,
    );
    // Web: Inter (Google Fonts). Yüklenemezse sistem yazı tipine düşer.
    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: Tw.gray900, displayColor: Tw.gray900),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Tw.teal600 : Colors.white),
        side: const BorderSide(color: Tw.gray300, width: 1.5),
      ),
      textSelectionTheme: const TextSelectionThemeData(cursorColor: Tw.teal600, selectionHandleColor: Tw.teal600),
    );
  }
}
