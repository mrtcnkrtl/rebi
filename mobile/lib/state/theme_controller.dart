import 'package:flutter/material.dart';

import '../core/local_store.dart';
import '../core/subscription.dart';
import '../ui/tw.dart';
import 'auth_controller.dart';

/// Kullanıcının seçtiği vurgu rengi. Uygulamanın dili tektir ("klinik sıcaklık": krem kâğıt, orman yeşili
/// mürekkep, Fraunces + Inter); tema yalnızca düğme, seçim ve vurgu rengini değiştirir. Desen, emoji ya da
/// şekil farkı yoktur. Web'deki dokuz temadan çocuksu olanlar (kedi, ayıcık) bu yüzden kaldırıldı; kayıtlı
/// kimliği artık olmayan kullanıcı varsayılana (`teal`, "Orman") döner.
class RebiTheme {
  const RebiTheme({
    required this.id,
    required this.label,
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.deep,
    required this.accent,
    required this.cardBorder,
    required this.bg,
    this.premium = false,
  });

  final String id;
  final String label;

  /// Düğme dolgusu ve vurgu; üstüne beyaz yazı yazılır (AA kontrast).
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;

  /// Derin ton: Bugün üst sahnesinin zemini (üstüne krem yazı yazılır). Orman'da marka yeşili; koyu modda
  /// uyarlanmaz, yalnızca [stage] biraz koyulaştırır.
  final Color deep;
  final Color accent;
  final Color cardBorder;

  /// Sayfa arka planı: krem kâğıdın üstünde temanın çok hafif bir yıkaması.
  final Gradient bg;
  final bool premium;

  /// Yüzeyin ÜSTÜNDE metin/ikon olarak kullanılacak vurgu rengi: açık modda `primary`, koyu modda okunacak kadar açılmış hâli.
  /// (`primary` düğme dolgusudur ve üstüne beyaz yazı yazılır; koyu zeminde metin olarak soluk kalır.)
  Color get fg => Tw.dark ? Color.lerp(primary, Colors.white, .5)! : primary;

  /// Bugün üst sahnesinin zemin rengi: açık modda [deep], koyu modda koyu sayfa zemininde parlamasın diye biraz koyulaşmış hâli.
  Color get stage => Tw.dark ? Color.lerp(deep, Colors.black, .28)! : deep;

  /// Koyu mod için: açık tint ve koyu metin tonları uyarlanır; `primary` / `accent` aynı kalır.
  /// (`cardBorder` ve `bg` zaten koyu moda duyarlı renklerden kuruludur.)
  RebiTheme adaptedForDark() => RebiTheme(
        id: id,
        label: label,
        primary: primary,
        primaryLight: Tw.adapt(primaryLight),
        primaryDark: Tw.adaptText(primaryDark),
        deep: deep,
        accent: accent,
        cardBorder: cardBorder,
        bg: bg,
        premium: premium,
      );
}

/// Kâğıt zeminin üstünde tema renginin çok hafif yıkaması: yukarıdan aşağı solar.
LinearGradient _wash(Color tint) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: const [0, .42],
      colors: [tint.withValues(alpha: Tw.dark ? .09 : .55), tint.withValues(alpha: 0)],
    );

RebiTheme _theme({
  required String id,
  required String label,
  required Color primary,
  required Color light,
  required Color dark,
  required Color accent,
  bool premium = false,
}) =>
    RebiTheme(
      id: id,
      label: label,
      primary: primary,
      primaryLight: light,
      primaryDark: dark,
      deep: dark,
      accent: accent,
      cardBorder: Tw.gray100,
      bg: _wash(light),
      premium: premium,
    );

/// Sıra seçici ekranındaki sıradır. Ücretsiz dört vurgu rengi, Plus için üç koyu/derin ton.
Map<String, RebiTheme> _buildThemes() => {
  'teal': _theme(
    id: 'teal',
    label: 'Orman',
    primary: const Color(0xFF0F766E),
    light: const Color(0xFFD3E7DF),
    dark: const Color(0xFF0B3D38),
    accent: const Color(0xFF14B8A6),
  ),
  'green': _theme(
    id: 'green',
    label: 'Adaçayı',
    primary: const Color(0xFF47804E),
    light: const Color(0xFFDDE9D6),
    dark: const Color(0xFF22442A),
    accent: const Color(0xFF5E9A62),
  ),
  'pink': _theme(
    id: 'pink',
    label: 'Pudra',
    primary: const Color(0xFFA94F65),
    light: const Color(0xFFF1DCE0),
    dark: const Color(0xFF7A3548),
    accent: const Color(0xFFCC7387),
  ),
  'lavender': _theme(
    id: 'lavender',
    label: 'Lavanta',
    primary: const Color(0xFF6C5AA0),
    light: const Color(0xFFE4DFEE),
    dark: const Color(0xFF3B2E58),
    accent: const Color(0xFF8575B5),
  ),
  // Rebi Plus — premium
  'sunset': _theme(
    id: 'sunset',
    label: 'Gün Batımı',
    premium: true,
    primary: const Color(0xFFA9562E),
    light: const Color(0xFFF4DDCF),
    dark: const Color(0xFF773E24),
    accent: const Color(0xFFCF7C54),
  ),
  'ocean': _theme(
    id: 'ocean',
    label: 'Derin Su',
    premium: true,
    primary: const Color(0xFF2F7686),
    light: const Color(0xFFD5E7EA),
    dark: const Color(0xFF174C58),
    accent: const Color(0xFF3E8A9A),
  ),
  'noir': _theme(
    id: 'noir',
    label: 'Gece',
    premium: true,
    primary: const Color(0xFF3E4C7A),
    light: const Color(0xFFDDE1EE),
    dark: const Color(0xFF242E4E),
    accent: const Color(0xFF7C8BC4),
  ),
};

final _themeCache = <bool, Map<String, RebiTheme>>{};

/// Kullanıcının seçebileceği temalar. Renkler açık / koyu moda göre ayrı hesaplanır ve saklanır
/// (tint ve koyu tonlar koyu zeminde uyarlanır; ana ve vurgu renkleri değişmez).
Map<String, RebiTheme> get rebiThemes => _themeCache[Tw.dark] ??= {
      for (final e in _buildThemes().entries) e.key: Tw.dark ? e.value.adaptedForDark() : e.value,
    };

bool isPremiumThemeId(String id) => rebiThemes[id]?.premium ?? false;

const _themeKey = 'rebi-theme';
const _modeKey = 'rebi-theme-mode';

/// Kayıtlı görünüm modu: `light`, `dark`; başka değer ya da kayıt yoksa sistemi izler.
ThemeMode themeModeFromName(String? name) => switch (name) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

/// Web `ThemeProvider` + `ThemePremiumGate`.
class ThemeController extends ChangeNotifier {
  ThemeController(this._auth) {
    final saved = LocalStore.instance.getString(_themeKey);
    // Kaldırılmış bir tema (kedi, ayıcık) kayıtlıysa varsayılana dön.
    _themeId = saved != null && rebiThemes.containsKey(saved) ? saved : 'teal';
    _mode = themeModeFromName(LocalStore.instance.getString(_modeKey));
    _auth.addListener(_premiumGate);
    _premiumGate();
  }

  final AuthController _auth;
  late String _themeId;
  late ThemeMode _mode;

  String get themeId => _themeId;

  /// Açık / koyu / sistem. Renk temasından (`theme`) bağımsızdır.
  ThemeMode get mode => _mode;

  void setMode(ThemeMode next) {
    if (next == _mode) return;
    _mode = next;
    LocalStore.instance.setString(_modeKey, next.name);
    notifyListeners();
  }

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
