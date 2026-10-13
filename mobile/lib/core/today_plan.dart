import 'api.dart';
import 'routine_logic.dart';

/// Günlük su hedefi (ml). Sunucudaki `WATER_TARGET_ML` ile aynıdır; hedef dolunca
/// sunucu su hatırlatıcısını da göndermez (`backend/today_plan.py`).
const waterTargetMl = 2000;

/// Bugünün ilerlemesi: `GET /today/plan` ve `GET /me/snapshot` içindeki `progress`.
class DayProgress {
  const DayProgress({
    this.waterMl = 0,
    this.nutritionLogged = false,
    this.morningDone = false,
    this.eveningDone = false,
    this.spfRefreshes = 0,
    this.makeupLogged = false,
    this.makeupUsed = false,
    this.makeupRemoved = false,
  });

  factory DayProgress.fromJson(Object? json) {
    final j = json is Map ? json.cast<String, dynamic>() : const <String, dynamic>{};
    final makeup = j['makeup'] is Map ? (j['makeup'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    return DayProgress(
      waterMl: _int(j['water_ml_total']),
      nutritionLogged: j['nutrition_logged'] == true,
      morningDone: j['routine_morning_done'] == true,
      eveningDone: j['routine_evening_done'] == true,
      spfRefreshes: _int(j['spf_refreshes']),
      makeupLogged: makeup['logged'] == true,
      makeupUsed: makeup['used'] == true,
      makeupRemoved: makeup['removed'] == true,
    );
  }

  final int waterMl;
  final bool nutritionLogged;
  final bool morningDone;
  final bool eveningDone;
  final int spfRefreshes;
  final bool makeupLogged;
  final bool makeupUsed;
  final bool makeupRemoved;

  double get waterFraction => (waterMl / waterTargetMl).clamp(0.0, 1.0);

  DayProgress copyWith({
    int? waterMl,
    bool? nutritionLogged,
    bool? morningDone,
    bool? eveningDone,
    int? spfRefreshes,
    bool? makeupLogged,
    bool? makeupUsed,
    bool? makeupRemoved,
  }) =>
      DayProgress(
        waterMl: waterMl ?? this.waterMl,
        nutritionLogged: nutritionLogged ?? this.nutritionLogged,
        morningDone: morningDone ?? this.morningDone,
        eveningDone: eveningDone ?? this.eveningDone,
        spfRefreshes: spfRefreshes ?? this.spfRefreshes,
        makeupLogged: makeupLogged ?? this.makeupLogged,
        makeupUsed: makeupUsed ?? this.makeupUsed,
        makeupRemoved: makeupRemoved ?? this.makeupRemoved,
      );

  /// Henüz sunucuya ulaşmamış bir olayın etkisini ekler. Kuralları sunucudaki toplama
  /// (`_aggregate_daily_events`) ile aynıdır; sunucu olayı alınca kendi toplamını döndürür.
  DayProgress withEvent(String type, Map<String, dynamic> payload) {
    switch (type) {
      case 'water_intake':
        return copyWith(waterMl: waterMl + _int(payload['ml']));
      case 'routine_completed_block':
        return copyWith(
          morningDone: morningDone || payload['morning'] == true,
          eveningDone: eveningDone || payload['evening'] == true,
        );
      case 'spf_refresh':
        return copyWith(spfRefreshes: spfRefreshes + 1);
      case 'nutrition':
        return copyWith(nutritionLogged: true);
      case 'makeup':
        var used = makeupUsed;
        var removed = makeupRemoved;
        if (payload['used'] != null) used = payload['used'] == true;
        if (payload['removed'] == true) {
          used = true;
          removed = true;
        }
        const removalMethods = {'double', 'cleanser', 'water', 'wipe'};
        if (removalMethods.contains('${payload['method'] ?? ''}'.trim().toLowerCase())) {
          used = true;
          removed = true;
        }
        return copyWith(makeupLogged: true, makeupUsed: used, makeupRemoved: removed);
      default:
        return this;
    }
  }
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

/// Sunucunun ürettiği saat aralıklı hatırlatıcı. Saatler yerel duvar saatidir.
class Reminder {
  const Reminder({
    required this.id,
    required this.title,
    required this.body,
    required this.start,
    required this.end,
    this.everyMinutes,
    this.logEvent,
  });

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
        id: '${j['id'] ?? ''}',
        title: '${j['title'] ?? ''}',
        body: '${j['body'] ?? ''}',
        start: '${j['start'] ?? ''}',
        end: '${j['end'] ?? ''}',
        everyMinutes: j['every_minutes'] is num ? (j['every_minutes'] as num).toInt() : null,
        logEvent: j['log_event'] is String && (j['log_event'] as String).isNotEmpty ? j['log_event'] as String : null,
      );

  final String id;
  final String title;
  final String body;
  final String start;
  final String end;
  final int? everyMinutes;

  /// Kullanıcı hatırlatıcıya yanıt verdiğinde gönderilecek olay tipi.
  final String? logEvent;

  /// `"07:30"` → 450; biçim bozuksa null.
  static int? minutesOf(String hhmm) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm.trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return null;
    return h * 60 + min;
  }
}

enum ReminderPhase { now, upcoming, past }

/// Hatırlatıcı penceresi `now` anında açık mı, yaklaşıyor mu, geçti mi.
ReminderPhase reminderPhase(Reminder r, DateTime now) {
  final start = Reminder.minutesOf(r.start);
  final end = Reminder.minutesOf(r.end);
  if (start == null || end == null) return ReminderPhase.past;
  final minute = now.hour * 60 + now.minute;
  if (minute < start) return ReminderPhase.upcoming;
  if (minute > end) return ReminderPhase.past;
  return ReminderPhase.now;
}

/// Hatırlatıcıya dokunulunca yapılacak iş: bir gün içi olay kaydı ya da bir ekrana gitme.
class ReminderAction {
  const ReminderAction(this.labelKey, {this.type, this.payload = const {}, this.route});

  /// `mobileToday.actions.*` çeviri anahtarı.
  final String labelKey;
  final String? type;
  final Map<String, dynamic> payload;
  final String? route;
}

/// Hatırlatıcı kimliğine göre sunulan eylemler (`docs/MOBIL-API.md` olay tipleri).
/// Eylemi olmayan hatırlatıcılar (ör. dudak balsamı) yalnızca bilgi verir.
List<ReminderAction> reminderActions(Reminder r) => switch (r.id) {
      'routine_morning' => const [
          ReminderAction('done', type: 'routine_completed_block', payload: {'morning': true}),
        ],
      'routine_evening' => const [
          ReminderAction('done', type: 'routine_completed_block', payload: {'evening': true}),
        ],
      'makeup_log' => const [
          ReminderAction('yes', type: 'makeup', payload: {'used': true}),
          ReminderAction('no', type: 'makeup', payload: {'used': false}),
        ],
      'makeup_removal' => const [
          ReminderAction('removed', type: 'makeup', payload: {'removed': true, 'method': 'double'}),
        ],
      'water_intake' => const [
          ReminderAction('water250', type: 'water_intake', payload: {'ml': 250}),
          ReminderAction('water500', type: 'water_intake', payload: {'ml': 500}),
        ],
      'spf_refresh' => const [ReminderAction('done', type: 'spf_refresh')],
      'nutrition_log' => const [
          ReminderAction('junkYes', type: 'nutrition', payload: {'junk_food': true}),
          ReminderAction('junkNo', type: 'nutrition', payload: {'junk_food': false}),
        ],
      'daily_checkin' => const [ReminderAction('open', route: '/dashboard/checkin')],
      _ => const [],
    };

/// `GET /today/plan` yanıtı: rutin, hava, havaya göre öneriler, hatırlatıcılar, ilerleme.
class TodayPlan {
  const TodayPlan({
    required this.logDate,
    required this.hasRoutine,
    required this.routine,
    required this.weather,
    required this.weatherSource,
    required this.environmentAdvice,
    required this.reminders,
    required this.progress,
    required this.checkinDone,
  });

  factory TodayPlan.fromJson(Map<String, dynamic> j) => TodayPlan(
        logDate: '${j['log_date'] ?? ''}',
        hasRoutine: j['has_routine'] == true,
        routine: asRoutine(j['routine']),
        weather: j['weather'] is Map ? (j['weather'] as Map).cast<String, dynamic>() : const {},
        weatherSource: '${j['weather_source'] ?? 'default'}',
        environmentAdvice: asRoutine(j['environment_advice']),
        reminders: [
          for (final r in (j['reminders'] is List ? j['reminders'] as List : const []))
            if (r is Map) Reminder.fromJson(r.cast<String, dynamic>()),
        ],
        progress: DayProgress.fromJson(j['progress']),
        checkinDone: j['checkin_done'] == true,
      );

  final String logDate;
  final bool hasRoutine;
  final List<RoutineItem> routine;
  final Map<String, dynamic> weather;

  /// `live` | `tracking` | `profile` | `default`
  final String weatherSource;
  final List<RoutineItem> environmentAdvice;
  final List<Reminder> reminders;
  final DayProgress progress;
  final bool checkinDone;

  /// Hava verisi gerçek bir kaynaktan mı geldi (varsayılan değerler değil).
  bool get hasRealWeather => weatherSource != 'default';

  TodayPlan withProgress(DayProgress next) => TodayPlan(
        logDate: logDate,
        hasRoutine: hasRoutine,
        routine: routine,
        weather: weather,
        weatherSource: weatherSource,
        environmentAdvice: environmentAdvice,
        reminders: reminders,
        progress: next,
        checkinDone: checkinDone,
      );
}

/// Konum verilirse canlı hava (konum izni gerekir); verilmezse sunucu bugünkü kayıttan,
/// profildeki son koordinattan ya da varsayılan değerlerden hava seçer.
Future<TodayPlan?> fetchTodayPlan(String userId, {double? lat, double? lon}) async {
  final res = await apiGet('/today/plan', query: {
    'user_id': userId,
    'lat': lat?.toString(),
    'lon': lon?.toString(),
  });
  return res.ok ? TodayPlan.fromJson(res.data) : null;
}
