import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/analyze/analyze_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/checkin_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/history_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/legal_screen.dart';
import 'screens/me_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/reminders_screen.dart';
import 'screens/shelf_screen.dart';
import 'screens/subscribe_screen.dart';
import 'screens/themes_screen.dart';
import 'state/auth_controller.dart';
import 'ui/shell/app_shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

/// `?next=` yalnızca uygulama içi bir yola izin verir (açık yönlendirme olmasın).
String safeNext(String? next) {
  if (next == null || next.isEmpty || !next.startsWith('/') || next.startsWith('//')) return '/dashboard';
  return next;
}

/// Açılış ↔ giriş geçişi: kısa bir solma ve hafif yukarı kayma (varsayılan sert geçişin yerine).
CustomTransitionPage<void> _softPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, .03), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Karşılama sayfası: dönüşte (girişten geri) zemin yumuşakça belirir; çıkışta sayfa düzeyinde solma yoktur (zemin yerinde
/// kalır, arkada kâğıt rengi parlamaz). Çıkış/giriş sırasında içeriği süzüp soldurmayı sayfanın kendisi yapar
/// (`LandingScreen`, rotanın `animation` ve `secondaryAnimation`ı ile).
CustomTransitionPage<void> _landingPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 340),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child),
  );
}

Map<String, dynamic>? _extraMap(Object? extra) => extra is Map ? extra.cast<String, dynamic>() : null;

/// Web `App.jsx` rotaları. `/dashboard*` korumalıdır (web: `ProtectedRoute`).
/// [splash] true ise oturum yokken uygulama animasyonlu açılışla başlar (yalnızca gerçek uygulamada): açılış ayrı bir rota
/// değil, karşılamanın içinde oynayan giriş sekansıdır (`landingIntroPending`).
GoRouter buildRouter(AuthController auth, {bool splash = false}) {
  if (splash && auth.user == null) landingIntroPending = true;
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: auth.user != null ? '/dashboard' : '/',
    refreshListenable: auth,
    redirect: (context, state) {
      final path = state.uri.path;
      final user = auth.user;
      // Sıfırlama bağlantısıyla gelindi: yeni parola belirlenene kadar yalnızca bu ekran açılabilir.
      if (user != null && auth.recoveryPending) return path == '/auth' ? null : '/auth';
      if (path.startsWith('/dashboard') && user == null) {
        return '/auth?next=${Uri.encodeComponent(state.uri.toString())}';
      }
      // Geçersiz/süresi dolmuş e-posta bağlantısı: nedenini giriş ekranı gösterir.
      if (user == null && auth.linkError != null && path == '/') return '/auth';
      if (path == '/auth' && user != null && !auth.authFlowInProgress) {
        return safeNext(state.uri.queryParameters['next']);
      }
      return null;
    },
    // Bilinmeyen yol → ana sayfa (web: `<Route path="*" element={<Navigate to="/" />} />`).
    onException: (context, state, router) => router.go('/'),
    routes: [
      // Yasal metinler formların üstünde açılır; geri dönüldüğünde form korunur.
      GoRoute(
        path: '/kvkk',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const LegalScreen(kind: 'kvkk'),
      ),
      GoRoute(
        path: '/riza',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const LegalScreen(kind: 'riza'),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => AppShell(location: state.uri, child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => _landingPage(state, const LandingScreen()),
          ),
          GoRoute(
            path: '/auth',
            pageBuilder: (context, state) => _softPage(
              state,
              AuthScreen(next: safeNext(state.uri.queryParameters['next']), startInSignup: state.uri.queryParameters['mode'] == 'signup'),
            ),
          ),
          GoRoute(path: '/rebi', builder: (context, state) => const ChatScreen()),
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => DashboardScreen(nav: _extraMap(state.extra)),
          ),
          GoRoute(
            path: '/dashboard/analyze',
            builder: (context, state) => AnalyzeScreen(
              key: ValueKey('analyze-${state.uri.queryParameters['photo'] == '1'}'),
              photoOnly: state.uri.queryParameters['photo'] == '1',
            ),
          ),
          GoRoute(path: '/dashboard/checkin', builder: (context, state) => const CheckInScreen()),
          // `extra: {'prompt': '...'}` ile açılırsa mesaj sohbete hazır yazılıp gönderilir (ör. Rafım'dan "yerine ne kullanabilirim?").
          GoRoute(
            path: '/dashboard/chat',
            builder: (context, state) => ChatScreen(initialPrompt: _extraMap(state.extra)?['prompt'] as String?),
          ),
          GoRoute(path: '/dashboard/shelf', builder: (context, state) => const ShelfScreen()),
          GoRoute(path: '/dashboard/themes', builder: (context, state) => const ThemesScreen()),
          GoRoute(path: '/dashboard/subscribe', builder: (context, state) => const SubscribeScreen()),
          GoRoute(path: '/dashboard/routine', builder: (context, state) => const DashboardScreen(planOnly: true)),
          GoRoute(path: '/dashboard/profile', builder: (context, state) => const MeScreen()),
          GoRoute(path: '/dashboard/account', builder: (context, state) => const ProfileScreen()),
          GoRoute(path: '/dashboard/history', builder: (context, state) => const HistoryScreen()),
          GoRoute(path: '/dashboard/reminders', builder: (context, state) => const RemindersScreen()),
        ],
      ),
    ],
  );
}
