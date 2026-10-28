import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Webdeki `localStorage` karşılığı. Anahtar adları web ile aynı tutulur;
/// böylece iki platformun hangi veriyi cihazda sakladığı tek bakışta karşılaştırılabilir.
class LocalStore {
  LocalStore._(this._prefs);

  static late LocalStore instance;

  final SharedPreferences _prefs;

  static Future<void> init() async {
    instance = LocalStore._(await SharedPreferences.getInstance());
  }

  /// Başka bir izolatın (bildirim düğmesinin arka plan işi) yazdıklarını görmek için diskten yeniden okur.
  Future<void> reload() async {
    try {
      await _prefs.reload();
    } catch (_) {
      /* okunamadı: eldeki değerlerle devam */
    }
  }

  String? getString(String key) {
    try {
      return _prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> setString(String key, String value) async {
    try {
      await _prefs.setString(key, value);
    } catch (_) {
      /* web: localStorage dolu / erişilemez durumu gibi sessiz geç */
    }
  }

  Future<void> remove(String key) async {
    try {
      await _prefs.remove(key);
    } catch (_) {
      /* ignore */
    }
  }

  /// JSON değer okur; bozuksa null döner (webdeki `JSON.parse` + try/catch).
  dynamic getJson(String key) {
    final raw = getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> setJson(String key, Object? value) => setString(key, jsonEncode(value));
}
