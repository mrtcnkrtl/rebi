import 'api.dart';
import 'day_log.dart';
import 'reminder_settings.dart';
import 'routine_logic.dart';
import 'weather_decisions.dart';

/// Varsayılan günlük su hedefi (ml). Kullanıcı ayardan değiştirebilir; gerçek hedef `TodayPlan.waterTarget`tır.
/// Hedef dolunca sunucu su hatırlatıcısını da göndermez (`backend/today_plan.py`).
const waterTargetMl = defaultWaterTargetMl;

/// Bugünün ilerlemesi: `GET /today/plan` ve `GET /me/snapshot` içindeki `progress`.
class DayProgress {
  const DayProgress({
    this.waterMl = 0,
    this.nutritionLogged = false,
    this.nutrition = const {},
    this.morningDone = false,
    this.eveningDone = false,
    this.stepsDone = const {},
    this.spfRefreshes = 0,
    this.makeupLogged = false,
    this.makeupUsed = false,
    this.makeupRemoved = false,
    this.removalMethod,
    this.finishedProducts = const [],
  });

  factory DayProgress.fromJson(Object? json) {
    final j = json is Map ? json.cast<String, dynamic>() : const <String, dynamic>{};
    final makeup = j['makeup'] is Map ? (j['makeup'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final steps = j['routine_steps'] is Map ? (j['routine_steps'] as Map) : const {};
    final method = '${makeup['removal_method'] ?? ''}'.trim().toLowerCase();
    return DayProgress(
      waterMl: _int(j['water_ml_total']),
      nutritionLogged: j['nutrition_logged'] == true,
      nutrition: j['nutrition'] is Map ? (j['nutrition'] as Map).cast<String, dynamic>() : const {},
      morningDone: j['routine_morning_done'] == true,
      eveningDone: j['routine_evening_done'] == true,
      stepsDone: {
        for (final block in routineBlocks)
          if (steps[block] is List) block: {for (final v in steps[block] as List) if (v is num) v.toInt()},
      },
      spfRefreshes: _int(j['spf_refreshes']),
      makeupLogged: makeup['logged'] == true,
      makeupUsed: makeup['used'] == true,
      makeupRemoved: makeup['removed'] == true,
      removalMethod: cleansingMethods.contains(method) ? method : null,
      finishedProducts: [
        for (final p in (j['products_finished'] is List ? j['products_finished'] as List : const []))
          if (p is Map && '${p['product'] ?? ''}'.trim().isNotEmpty) '${p['product']}'.trim(),
      ],
    );
  }

  final int waterMl;
  final bool nutritionLogged;

  /// Beslenme seçimleri (`snacks`, `sweets`, `junk_food`…); gün içinde birleştirilir.
  final Map<String, dynamic> nutrition;
  final bool morningDone;
  final bool eveningDone;

  /// İşaretli rutin adımları: blok (`morning` / `evening`) → `step_order` değerleri.
  final Map<String, Set<int>> stepsDone;
  final int spfRefreshes;
  final bool makeupLogged;
  final bool makeupUsed;
  final bool makeupRemoved;

  /// Makyajın nasıl temizlendiği (`double`, `cleanser`, `water`, `wipe`, `none`).
  final String? removalMethod;

  /// Bugün "bitti" olarak işaretlenen ürünlerin adları.
  final List<String> finishedProducts;

  double get waterFraction => waterFractionFor(waterTargetMl);

  /// Verilen hedefe göre doluluk (0–1).
  double waterFractionFor(int target) => (waterMl / target).clamp(0.0, 1.0);

  bool blockDone(String block) => block == 'morning' ? morningDone : eveningDone;

  Set<int> stepsOf(String block) => stepsDone[block] ?? const {};

  DayProgress copyWith({
    int? waterMl,
    bool? nutritionLogged,
    Map<String, dynamic>? nutrition,
    bool? morningDone,
    bool? eveningDone,
    Map<String, Set<int>>? stepsDone,
    int? spfRefreshes,
    bool? makeupLogged,
    bool? makeupUsed,
    bool? makeupRemoved,
    String? removalMethod,
    List<String>? finishedProducts,
  }) =>
      DayProgress(
        waterMl: waterMl ?? this.waterMl,
        nutritionLogged: nutritionLogged ?? this.nutritionLogged,
        nutrition: nutrition ?? this.nutrition,
        morningDone: morningDone ?? this.morningDone,
        eveningDone: eveningDone ?? this.eveningDone,
        stepsDone: stepsDone ?? this.stepsDone,
        spfRefreshes: spfRefreshes ?? this.spfRefreshes,
        makeupLogged: makeupLogged ?? this.makeupLogged,
        makeupUsed: makeupUsed ?? this.makeupUsed,
        makeupRemoved: makeupRemoved ?? this.makeupRemoved,
        removalMethod: removalMethod ?? this.removalMethod,
        finishedProducts: finishedProducts ?? this.finishedProducts,
      );

  /// Henüz sunucuya ulaşmamış bir olayın etkisini ekler. Kuralları sunucudaki toplama
  /// (`_aggregate_daily_events`) ile aynıdır; sunucu olayı alınca kendi toplamını döndürür.
  DayProgress withEvent(String type, Map<String, dynamic> payload) {
    switch (type) {
      case 'water_intake':
        final ml = _int(payload['ml']).clamp(-maxWaterEntryMl, maxWaterEntryMl);
        return copyWith(waterMl: (waterMl + ml).clamp(0, 1 << 30));
      case 'routine_completed_block':
        // Son olay geçerlidir: `false` bloğu yeniden açar.
        return copyWith(
          morningDone: payload.containsKey('morning') ? payload['morning'] == true : morningDone,
          eveningDone: payload.containsKey('evening') ? payload['evening'] == true : eveningDone,
        );
      case 'routine_step':
        final block = '${payload['block'] ?? ''}'.trim().toLowerCase();
        final step = payload['step_order'];
        if (!routineBlocks.contains(block) || step is! num) return this;
        final next = {...stepsOf(block)};
        if (payload['done'] == true) {
          next.add(step.toInt());
        } else {
          next.remove(step.toInt());
        }
        return copyWith(stepsDone: {...stepsDone, block: next});
      case 'spf_refresh':
        return copyWith(spfRefreshes: spfRefreshes + 1);
      case 'nutrition':
        return copyWith(nutritionLogged: true, nutrition: {...nutrition, ...payload});
      case 'product_finished':
        final name = '${payload['product'] ?? ''}'.trim();
        if (name.isEmpty || finishedProducts.length >= maxFinishedProductsPerDay) return this;
        return copyWith(finishedProducts: [...finishedProducts, name]);
      case 'makeup':
        var used = makeupUsed;
        var removed = makeupRemoved;
        if (payload['used'] != null) used = payload['used'] == true;
        if (payload['removed'] == true) {
          used = true;
          removed = true;
        }
        final method = '${payload['method'] ?? ''}'.trim().toLowerCase();
        if (cleansingMethods.contains(method) && method != 'none') {
          used = true;
          removed = true;
        }
        return copyWith(
          makeupLogged: true,
          makeupUsed: used,
          makeupRemoved: removed,
          removalMethod: cleansingMethods.contains(method) ? method : removalMethod,
        );
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

/// Hatırlatıcının `now` anından sonraki ilk saati (`"13:00"`); bugün için kalmadıysa null.
/// `every_minutes` doluysa pencere boyunca o aralıkla tekrarlanır (sunucudaki `_slots` ile aynı).
String? nextReminderSlot(Reminder r, DateTime now) {
  final start = Reminder.minutesOf(r.start);
  final end = Reminder.minutesOf(r.end);
  if (start == null || end == null) return null;
  final minute = now.hour * 60 + now.minute;
  final every = r.everyMinutes;
  final slots = every == null || every <= 0 ? [start] : [for (var m = start; m <= end; m += every) m];
  for (final m in slots) {
    if (m > minute) {
      return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    }
  }
  return null;
}

/// Hatırlatıcıya dokunulunca yapılacak iş: bir gün içi olay kaydı, bir ekrana gitme ya da
/// bir seçim ekranı açma.
class ReminderAction {
  const ReminderAction(this.labelKey, {this.type, this.payload = const {}, this.route, this.sheet});

  /// `mobileToday.actions.*` çeviri anahtarı.
  final String labelKey;
  final String? type;
  final Map<String, dynamic> payload;
  final String? route;

  /// Bir seçim ekranı açar (ör. makyaj nasıl temizlendi); kayıt oradan gönderilir.
  final DaySheet? sheet;
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
      'makeup_removal' => const [ReminderAction('removed', sheet: DaySheet.cleansing)],
      'water_intake' => const [
          ReminderAction('water250', type: 'water_intake', payload: {'ml': 250}),
          ReminderAction('water500', type: 'water_intake', payload: {'ml': 500}),
        ],
      'spf_refresh' => const [ReminderAction('done', type: 'spf_refresh')],
      'nutrition_log' => const [
          ReminderAction('junkYes', sheet: DaySheet.nutrition),
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
    this.settings = const ReminderSettings(),
    this.decisions,
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
        settings: ReminderSettings.fromJson(j['reminder_settings']),
        decisions: WeatherDecisions.fromJson(j['weather_decisions']),
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

  /// Kullanıcının gün düzeni ve kapattığı hatırlatıcı kategorileri.
  final ReminderSettings settings;

  /// Havaya göre güneş kremi / nemlendirici / dudak balsamı kararları; eski sunucuda null (o zaman `environmentAdvice` gösterilir).
  final WeatherDecisions? decisions;

  /// Hava verisi gerçek bir kaynaktan mı geldi (varsayılan değerler değil).
  bool get hasRealWeather => weatherSource != 'default';

  /// Kullanıcının günlük su hedefi (ml).
  int get waterTarget => settings.waterTargetMl;

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
        settings: settings,
        decisions: decisions,
      );
}

/// Konum verilirse canlı hava (konum izni gerekir); verilmezse sunucu bugünkü kayıttan,
/// profildeki son koordinattan ya da varsayılan değerlerden hava seçer.
Future<TodayPlan?> fetchTodayPlan(String userId, {double? lat, double? lon}) async {
  final res = await apiGet('/today/plan', query: {
    'user_id': userId,
    'lat': lat?.toString(),
    'lon': lon?.toString(),
    'utc_offset_minutes': localUtcOffsetMinutes(),
  });
  return res.ok ? TodayPlan.fromJson(res.data) : null;
}
