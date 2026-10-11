import 'package:flutter/material.dart';

import '../core/local_store.dart';
import '../core/subscription.dart';
import '../ui/tw.dart';
import 'auth_controller.dart';

/// Web `ThemeContext.jsx` içindeki tema tanımlarının birebir karşılığı.
class RebiTheme {
  const RebiTheme({
    required this.id,
    required this.label,
    required this.emoji,
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.accent,
    required this.cardBorder,
    required this.bg,
    this.pattern = '',
    this.shape = '',
    this.premium = false,
  });

  final String id;
  final String label;
  final String emoji;
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;
  final Color accent;
  final Color cardBorder;

  /// Sayfa arka planı (beyaz zemin üzerinde, webdeki `bg-gradient-*` sınıfları).
  final Gradient bg;
  final String pattern;
  final String shape;
  final bool premium;
}

Color _a(Color c, double opacity) => c.withValues(alpha: opacity);

LinearGradient _toB(List<Color> colors) =>
    LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors);

LinearGradient _toBr(List<Color> colors) =>
    LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors);

final Map<String, RebiTheme> rebiThemes = {
  'teal': RebiTheme(
    id: 'teal',
    label: 'Klasik Teal',
    emoji: '🌿',
    primary: const Color(0xFF0D9488),
    primaryLight: const Color(0xFFCCFBF1),
    primaryDark: const Color(0xFF115E59),
    accent: const Color(0xFF14B8A6),
    cardBorder: Tw.gray100,
    bg: _toB([_a(Tw.teal50, .5), Colors.white]),
  ),
  'pink': RebiTheme(
    id: 'pink',
    label: 'Pembe Kalp',
    emoji: '💗',
    primary: const Color(0xFFDB2777),
    primaryLight: const Color(0xFFFCE7F3),
    primaryDark: const Color(0xFF9D174D),
    accent: const Color(0xFFEC4899),
    cardBorder: Tw.pink100,
    bg: _toB([_a(Tw.pink50, .6), _a(Tw.rose50, .3)]),
    pattern: 'hearts',
  ),
  'green': RebiTheme(
    id: 'green',
    label: 'Yeşil Doğa',
    emoji: '🌱',
    primary: const Color(0xFF16A34A),
    primaryLight: const Color(0xFFDCFCE7),
    primaryDark: const Color(0xFF14532D),
    accent: const Color(0xFF22C55E),
    cardBorder: Tw.green100,
    bg: _toB([_a(Tw.green50, .5), _a(Tw.emerald50, .2)]),
    pattern: 'leaves',
  ),
  'lavender': RebiTheme(
    id: 'lavender',
    label: 'Lavanta Manzara',
    emoji: '🏔️',
    primary: const Color(0xFF7C3AED),
    primaryLight: const Color(0xFFEDE9FE),
    primaryDark: const Color(0xFF4C1D95),
    accent: const Color(0xFF8B5CF6),
    cardBorder: Tw.violet100,
    bg: _toB([_a(Tw.violet50, .5), _a(Tw.purple50, .2)]),
    pattern: 'landscape',
  ),
  'cat': RebiTheme(
    id: 'cat',
    label: 'Kedi Sever',
    emoji: '🐱',
    primary: const Color(0xFFEA580C),
    primaryLight: const Color(0xFFFFF7ED),
    primaryDark: const Color(0xFF9A3412),
    accent: const Color(0xFFF97316),
    cardBorder: Tw.orange100,
    bg: _toB([_a(Tw.orange50, .4), _a(Tw.amber50, .2)]),
    pattern: 'cats',
  ),
  'teddy': RebiTheme(
    id: 'teddy',
    label: 'Ayıcık',
    emoji: '🧸',
    primary: const Color(0xFFB45309),
    primaryLight: const Color(0xFFFEF3C7),
    primaryDark: const Color(0xFF78350F),
    accent: const Color(0xFFD97706),
    cardBorder: Tw.amber200,
    bg: _toB([_a(Tw.amber50, .55), _a(Tw.orange50, .25), _a(Tw.rose50, .2)]),
    pattern: 'bears',
  ),
  // Rebi Plus — premium
  'sunset': RebiTheme(
    id: 'sunset',
    label: 'Gün Batımı',
    emoji: '🌅',
    premium: true,
    primary: const Color(0xFFC026D3),
    primaryLight: const Color(0xFFFAE8FF),
    primaryDark: const Color(0xFF86198F),
    accent: const Color(0xFFF97316),
    cardBorder: Tw.fuchsia100,
    bg: _toBr([_a(Tw.fuchsia50, .7), _a(Tw.orange50, .4), _a(Tw.rose50, .5)]),
    pattern: 'sunburst',
    shape: 'sunburst',
  ),
  'ocean': RebiTheme(
    id: 'ocean',
    label: 'Derin Okyanus',
    emoji: '🌊',
    premium: true,
    primary: const Color(0xFF0369A1),
    primaryLight: const Color(0xFFE0F2FE),
    primaryDark: const Color(0xFF0C4A6E),
    accent: const Color(0xFF06B6D4),
    cardBorder: Tw.sky200,
    bg: _toB([_a(Tw.sky100, .5), _a(Tw.cyan50, .3), _a(Tw.blue50, .4)]),
    pattern: 'waves',
    shape: 'waves',
  ),
  'noir': RebiTheme(
    id: 'noir',
    label: 'Gece Şehir',
    emoji: '🌃',
    premium: true,
    primary: const Color(0xFF4338CA),
    primaryLight: const Color(0xFFE0E7FF),
    primaryDark: const Color(0xFF312E81),
    accent: const Color(0xFFA855F7),
    cardBorder: Tw.indigo200,
    bg: _toB([_a(Tw.indigo100, .4), _a(Tw.violet50, .3), _a(Tw.slate100, .5)]),
    pattern: 'stars',
    shape: 'angular',
  ),
};

bool isPremiumThemeId(String id) => rebiThemes[id]?.premium ?? false;

const _themeKey = 'rebi-theme';

/// Web `ThemeProvider` + `ThemePremiumGate`.
class ThemeController extends ChangeNotifier {
  ThemeController(this._auth) {
    _themeId = LocalStore.instance.getString(_themeKey) ?? 'teal';
    _auth.addListener(_premiumGate);
    _premiumGate();
  }

  final AuthController _auth;
  late String _themeId;

  String get themeId => _themeId;

  RebiTheme get theme => rebiThemes[_themeId] ?? rebiThemes['teal']!;

  void setThemeId(String id) {
    if (id == _themeId) return;
    _themeId = id;
    LocalStore.instance.setString(_themeKey, id);
    notifyListeners();
  }

  /// Plus olmayan kullanıcıda kayıtlı premium temayı teal'e çeker.
  void _premiumGate() {
    final user = _auth.user;
    if (user == null) return;
    if (!userHasRebiPlus(user) && isPremiumThemeId(_themeId)) setThemeId('teal');
  }

  @override
  void dispose() {
    _auth.removeListener(_premiumGate);
    super.dispose();
  }
}
