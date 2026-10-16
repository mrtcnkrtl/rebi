import 'dart:convert';

import 'api.dart';
import 'today_plan.dart';

/// Kullanıcının kapatıp açabildiği hatırlatıcı kategorileri (`backend/today_plan.py`).
const reminderCategories = ['routine', 'water', 'makeup', 'nutrition', 'spf', 'lip_balm', 'checkin', 'restock'];

/// Hatırlatıcı kimliği → kategori.
const reminderCategoryOf = {
  'routine_morning': 'routine',
  'routine_evening': 'routine',
  'water_intake': 'water',
  'makeup_log': 'makeup',
  'makeup_removal': 'makeup',
  'nutrition_log': 'nutrition',
  'spf_refresh': 'spf',
  'lip_balm': 'lip_balm',
  'restock_check': 'restock',
  'daily_checkin': 'checkin',
};

/// Su hatırlatıcısının seçilebilir aralıkları (dakika).
const waterIntervalChoices = [60, 90, 120, 180];

/// Günlük su hedefi: varsayılan ve seçilebilir değerler (ml). Sunucudaki `WATER_TARGET_ML` / `WATER_TARGET_CHOICES` ile aynıdır.
const defaultWaterTargetMl = 2000;
const waterTargetChoices = [1500, 1750, 2000, 2250, 2500, 3000];

/// En erken uyanma, en geç uyku ve ikisi arasındaki en kısa süre (dakika). Sunucuyla aynıdır.
const earliestWakeMinutes = 4 * 60;
const latestSleepMinutes = 23 * 60 + 59;
const minAwakeMinutes = 9 * 60;

/// `"07:30"` → 450; biçim ya da aralık bozuksa null.
int? parseClock(String? value) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch((value ?? '').trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

String formatClock(int minutes) {
  final m = minutes.clamp(0, 24 * 60 - 1);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

bool isValidDay(int wake, int sleep) =>
    wake >= earliestWakeMinutes && sleep <= latestSleepMinutes && sleep - wake >= minAwakeMinutes;

/// Uyanma / uyku saati, su aralığı ve kapatılan kategoriler. Sunucudaki `reminder_settings` ile aynı şekil.
class ReminderSettings {
  const ReminderSettings({
    this.wakeTime = '07:30',
    this.sleepTime = '23:00',
    this.waterEveryMinutes = 120,
    this.waterTargetMl = defaultWaterTargetMl,
    this.enabled = const {},
  });

  /// Sunucu gibi hoşgörülüdür: bozuk alan varsayılana döner, tutarsız gün düzeni ikisini de sıfırlar.
  factory ReminderSettings.fromJson(Object? json) {
    final j = json is Map ? json.cast<String, dynamic>() : const <String, dynamic>{};
    const defaults = ReminderSettings();
    final wake = parseClock('${j['wake_time'] ?? ''}');
    final sleep = parseClock('${j['sleep_time'] ?? ''}');
    final validDay = wake != null && sleep != null && isValidDay(wake, sleep);
    final every = j['water_every_minutes'];
    final target = j['water_target_ml'];
    final stored = j['enabled'] is Map ? (j['enabled'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    return ReminderSettings(
      wakeTime: validDay ? formatClock(wake) : defaults.wakeTime,
      sleepTime: validDay ? formatClock(sleep) : defaults.sleepTime,
      waterEveryMinutes: every is int && waterIntervalChoices.contains(every) ? every : defaults.waterEveryMinutes,
      waterTargetMl: target is int && waterTargetChoices.contains(target) ? target : defaults.waterTargetMl,
      enabled: {for (final c in reminderCategories) c: stored[c] is bool ? stored[c] as bool : true},
    );
  }

  final String wakeTime;
  final String sleepTime;
  final int waterEveryMinutes;

  /// Günlük su hedefi (ml).
  final int waterTargetMl;

  /// Kategori → açık mı. Olmayan kategori açık sayılır.
  final Map<String, bool> enabled;

  bool isEnabled(String category) => enabled[category] != false;

  int get wakeMinutes => parseClock(wakeTime) ?? 7 * 60 + 30;
  int get sleepMinutes => parseClock(sleepTime) ?? 23 * 60;

  /// Gün düzeni sunucunun kabul edeceği aralıkta mı.
  bool get dayIsValid {
    final wake = parseClock(wakeTime);
    final sleep = parseClock(sleepTime);
    return wake != null && sleep != null && isValidDay(wake, sleep);
  }

  ReminderSettings copyWith({
    String? wakeTime,
    String? sleepTime,
    int? waterEveryMinutes,
    int? waterTargetMl,
    Map<String, bool>? enabled,
  }) =>
      ReminderSettings(
        wakeTime: wakeTime ?? this.wakeTime,
        sleepTime: sleepTime ?? this.sleepTime,
        waterEveryMinutes: waterEveryMinutes ?? this.waterEveryMinutes,
        waterTargetMl: waterTargetMl ?? this.waterTargetMl,
        enabled: enabled ?? this.enabled,
      );

  ReminderSettings withCategory(String category, bool on) => copyWith(enabled: {...enabled, category: on});

  Map<String, dynamic> toJson() => {
        'wake_time': wakeTime,
        'sleep_time': sleepTime,
        'water_every_minutes': waterEveryMinutes,
        'water_target_ml': waterTargetMl,
        'enabled': {for (final c in reminderCategories) c: isEnabled(c)},
      };

  /// Ayarlar aynı mı (kaydedilmemiş değişiklik var mı).
  bool sameAs(ReminderSettings other) => jsonEncode(toJson()) == jsonEncode(other.toJson());
}

/// Uyanma (`wake`) ya da uyku (`sleep`) saatine göre pencere: çapa, başlangıç ve bitiş farkı (dakika).
/// Sunucudaki `_WINDOW_OFFSETS` ile aynıdır; 07:30 / 23:00 için eski sabit pencereleri verir.
const _windowOffsets = <String, (String, int, int)>{
  'routine_morning': ('wake', 0, 120),
  'makeup_log': ('wake', 150, 210),
  'spf_refresh': ('wake', 210, 510),
  'lip_balm': ('wake', 270, 330),
  'restock_check': ('sleep', -300, -240),
  'routine_evening': ('sleep', -120, 0),
  'makeup_removal': ('sleep', -120, 0),
  'nutrition_log': ('sleep', -180, -150),
  'daily_checkin': ('sleep', -120, -30),
};

/// Hatırlatıcının yerel saat penceresi (`"07:30"`, `"09:30"`); kimlik bilinmiyorsa null.
({String start, String end})? reminderWindow(String reminderId, ReminderSettings s) {
  final wake = s.wakeMinutes;
  final sleep = s.sleepMinutes;
  if (reminderId == 'water_intake') return (start: formatClock(wake + 90), end: formatClock(sleep - 120));
  final offsets = _windowOffsets[reminderId];
  if (offsets == null) return null;
  final base = offsets.$1 == 'wake' ? wake : sleep;
  int clamp(int v) => v.clamp(wake, sleep);
  return (start: formatClock(clamp(base + offsets.$2)), end: formatClock(clamp(base + offsets.$3)));
}

/// Havaya ve yapılan işe bağlı olmayan, her gün tekrar eden hatırlatıcılar. Yarın için
/// bilinen tek şey budur (`planNotifications`); kapatılan kategoriler dışarıda kalır.
List<Reminder> dailyReminders(ReminderSettings s) => [
      for (final id in const [
        'routine_morning',
        'water_intake',
        'makeup_log',
        'nutrition_log',
        'routine_evening',
        'daily_checkin',
      ])
        if (s.isEnabled(reminderCategoryOf[id]!))
          Reminder(
            id: id,
            title: '',
            body: '',
            start: reminderWindow(id, s)!.start,
            end: reminderWindow(id, s)!.end,
            everyMinutes: id == 'water_intake' ? s.waterEveryMinutes : null,
          ),
    ];

/// `GET /me/reminder-settings`; başarısızlıkta (ağ yok, 401, 5xx) null.
Future<ReminderSettings?> fetchReminderSettings(String userId) async {
  final res = await apiGet('/me/reminder-settings', query: {'user_id': userId});
  return res.ok ? ReminderSettings.fromJson(res.data['settings']) : null;
}

class ReminderSettingsSave {
  const ReminderSettingsSave({this.settings, this.error});

  /// Sunucunun kabul ettiği güncel ayar; başarısızsa null.
  final ReminderSettings? settings;

  /// Sunucu reddettiyse nedeni (422 mesajı); ağ hatasında boş metin.
  final String? error;

  bool get ok => settings != null;
}

/// `PUT /me/reminder-settings`: ayarların hepsi gönderilir.
Future<ReminderSettingsSave> saveReminderSettings(String userId, ReminderSettings settings) async {
  try {
    final res = await apiPut('/me/reminder-settings', {'user_id': userId, ...settings.toJson()});
    if (res.ok) return ReminderSettingsSave(settings: ReminderSettings.fromJson(res.data['settings']));
    return ReminderSettingsSave(error: res.status == 422 ? formatApiErrorDetail(res.data) : '');
  } catch (_) {
    return const ReminderSettingsSave(error: '');
  }
}
