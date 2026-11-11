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
///
/// **Palet reçetesi.** İlk renk Orman en çok sevilen olduğu için tek ölçüdür; diğer temalar onun "DNA"sıyla, yalnızca tonu (hue)
/// değiştirilerek kurulur (OKLCH): birincil L≈.51 C≈.09 (beyaz yazı ≥ 5:1), derin sahne L≈.32 C≈.055–.065 (koyu ve sessiz,
/// krem yazı ≥ 9:1), açık ton L≈.92 C≈.025, vurgu L≈.68 C≈.10. Böylece hiçbir tema "bordo", "çamurlu kahve" ya da neon görünmez;
/// hepsi aynı olgunlukta durur. `test/design_system_test.dart` bu sınırları korur.
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
    primary: const Color(0xFF43774B),
    light: const Color(0xFFDCE9D9),
    dark: const Color(0xFF1E3A24),
    accent: const Color(0xFF6DA974),
  ),
  'pink': _theme(
    id: 'pink',
    label: 'Pudra',
    primary: const Color(0xFF954F69),
    light: const Color(0xFFF3DEE6),
    dark: const Color(0xFF4B2435),
    accent: const Color(0xFFD3829E),
  ),
  'lavender': _theme(
    id: 'lavender',
    label: 'Lavanta',
    primary: const Color(0xFF6B599C),
    light: const Color(0xFFE6E2F2),
    dark: const Color(0xFF34284E),
    accent: const Color(0xFF9686C8),
  ),
  // Rebi Plus — premium
  'sunset': _theme(
    id: 'sunset',
    label: 'Gün Batımı',
    premium: true,
    primary: const Color(0xFFA15236),
    light: const Color(0xFFF5E0D2),
    dark: const Color(0xFF4E261A),
    accent: const Color(0xFFD88761),
  ),
  'ocean': _theme(
    id: 'ocean',
    label: 'Derin Su',
    premium: true,
    primary: const Color(0xFF296D94),
    light: const Color(0xFFD8E7F1),
    dark: const Color(0xFF13334B),
    accent: const Color(0xFF5EA1CB),
  ),
  'noir': _theme(
    id: 'noir',
    label: 'Gece',
    premium: true,
    primary: const Color(0xFF3E528C),
    light: const Color(0xFFDFE4F2),
    dark: const Color(0xFF1F294A),
    accent: const Color(0xFF7B8FCD),
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
