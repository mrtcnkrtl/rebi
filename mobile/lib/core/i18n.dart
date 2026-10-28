import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'interpolate.dart';
import 'local_store.dart';

/// UI dilleri: TR/EN (webdeki `SUPPORTED_LANGS` ile aynı).
const supportedLangs = ['tr', 'en'];
const _fallbackLang = 'en';
const _langKey = 'rebi-lang';

/// Webdeki i18next + `localePacks.js` karşılığı.
/// Metinler web ile aynı JSON dosyalarından okunur (`assets/locales`, kaynak: `frontend/src/locales`).
class I18n extends ChangeNotifier {
  I18n._();

  static final I18n instance = I18n._();

  final Map<String, Map<String, dynamic>> _common = {};
  final Map<String, Map<String, dynamic>> _analyzeWizard = {};
  final Map<String, Map<String, dynamic>> _severityTests = {};

  /// Yalnızca mobilde olan metinler (`assets/mobile_locales`); web ile eşitleme testine girmez.
  final Map<String, Map<String, dynamic>> _mobile = {};

  String _lang = 'tr';

  /// Webdeki `i18n.resolvedLanguage`.
  String get lang => _lang;

  /// `tr` dışındaki dillerde backend'in `*_localized` alanları tercih edilir.
  bool get prefersLocalized => _lang != 'tr';

  Future<void> init() async {
    for (final lng in supportedLangs) {
      _common[lng] = await _load(lng, 'common');
      _analyzeWizard[lng] = await _load(lng, 'analyzeWizard');
      _severityTests[lng] = await _load(lng, 'severityTests');
      _mobile[lng] = await _load(lng, 'mobile', dir: 'mobile_locales');
    }
    _lang = _detect();
    // i18next `caches: ["localStorage"]`: algılanan dil saklanır.
    await LocalStore.instance.setString(_langKey, _lang);
  }

  /// Sadece testler için: varlık yüklemeden sözlük verir.
  @visibleForTesting
  void debugLoad({
    required Map<String, Map<String, dynamic>> common,
    Map<String, Map<String, dynamic>> analyzeWizard = const {},
    Map<String, Map<String, dynamic>> severityTests = const {},
    Map<String, Map<String, dynamic>> mobile = const {},
    String lang = 'tr',
  }) {
    _common
      ..clear()
      ..addAll(common);
    _analyzeWizard
      ..clear()
      ..addAll(analyzeWizard);
    _severityTests
      ..clear()
      ..addAll(severityTests);
    _mobile
      ..clear()
      ..addAll(mobile);
    _lang = lang;
  }

  static Future<Map<String, dynamic>> _load(String lng, String ns, {String dir = 'locales'}) async {
    try {
      final raw = await rootBundle.loadString('assets/$dir/$lng/$ns.json');
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  /// Sıra: kayıtlı tercih → cihaz dili → `en` (webde localStorage → navigator → fallback).
  String _detect() {
    final stored = _normalize(LocalStore.instance.getString(_langKey));
    if (stored != null) return stored;
    for (final locale in ui.PlatformDispatcher.instance.locales) {
      final n = _normalize(locale.languageCode);
      if (n != null) return n;
    }
    return _fallbackLang;
  }

  static String? _normalize(String? code) {
    if (code == null) return null;
    final base = code.toLowerCase().split(RegExp('[-_]')).first;
    return supportedLangs.contains(base) ? base : null;
  }

  Future<void> changeLanguage(String lng) async {
    final n = _normalize(lng) ?? _fallbackLang;
    await LocalStore.instance.setString(_langKey, n);
    if (n == _lang) return;
    _lang = n;
    notifyListeners();
  }

  static dynamic _lookup(Map<String, dynamic>? root, String key) {
    dynamic cur = root;
    for (final part in key.split('.')) {
      if (cur is Map && cur.containsKey(part)) {
        cur = cur[part];
      } else {
        return null;
      }
    }
    return cur;
  }

  dynamic _resolve(String key) {
    return _lookup(_common[_lang], key) ??
        _lookup(_mobile[_lang], key) ??
        _lookup(_common[_fallbackLang], key) ??
        _lookup(_mobile[_fallbackLang], key);
  }

  /// `t("chat.usageBadgeDay", {rem: 3, lim: 5})`
  String t(String key, [Map<String, Object?> vars = const {}, String? defaultValue]) {
    final v = _resolve(key);
    if (v is String) return interpolate(v, vars);
    if (v != null && v is! Map && v is! List) return v.toString();
    return defaultValue ?? key;
  }

  /// `t(key, { returnObjects: true })` dizi metinleri için.
  List<String> tList(String key, List<String> defaultValue) {
    final v = _resolve(key);
    if (v is List) return v.map((e) => e.toString()).toList();
    return defaultValue;
  }

  /// `useAnalyzeWizardPack()` — dil dosyası yoksa İngilizce paket.
  Map<String, dynamic> get analyzeWizardPack =>
      (_analyzeWizard[_lang]?.isNotEmpty ?? false) ? _analyzeWizard[_lang]! : (_analyzeWizard[_fallbackLang] ?? {});

  /// `useSeverityTestsPack()`
  Map<String, dynamic> get severityTestsPack =>
      (_severityTests[_lang]?.isNotEmpty ?? false) ? _severityTests[_lang]! : (_severityTests[_fallbackLang] ?? {});
}

/// Paket içinden güvenli metin okuma: `pack.errors.pickPhotoFirst` → `P(pack)['errors.pickPhotoFirst']`.
class Pack {
  const Pack(this.data);

  final Map<String, dynamic> data;

  dynamic raw(String path) => I18n._lookup(data, path);

  String s(String path) {
    final v = raw(path);
    return v == null ? '' : v.toString();
  }

  /// `pack.gender[id] || id`
  String or(String path, String fallback) {
    final v = raw(path);
    if (v == null) return fallback;
    final s = v.toString();
    return s.isEmpty ? fallback : s;
  }

  Map<String, dynamic> map(String path) {
    final v = raw(path);
    return v is Map ? v.cast<String, dynamic>() : const {};
  }

  List<dynamic> list(String path) {
    final v = raw(path);
    return v is List ? v : const [];
  }
}

extension I18nContext on BuildContext {
  /// Dil değişince yeniden çizilmek için `watch` kullanır.
  I18n get i18n => watch<I18n>();
}
