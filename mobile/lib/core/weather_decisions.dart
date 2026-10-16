/// "Bugün havaya göre": güneş kremi, nemlendirici ve dudak balsamı kararları (`GET /today/plan` →
/// `weather_decisions`). Sunucu yapılandırılmış veri gönderir; cümleleri uygulama kendi dilinde kurar
/// (`mobileToday.decisions.*`). Alan yoksa (eski sunucu) [WeatherDecisions.fromJson] null döner ve ekran
/// `environment_advice` listesine düşer.
library;

/// UV'nin yüksek olduğu saat aralığı (konumun yerel duvar saati).
class UvWindow {
  const UvWindow({required this.start, required this.end, this.peak});

  final String start;
  final String end;
  final String? peak;
}

class SpfDecision {
  const SpfDecision({
    required this.spf,
    required this.level,
    required this.uv,
    required this.refresh,
    this.refreshEveryMinutes,
    this.window,
  });

  /// `"30"`, `"30+"`, `"50"`, `"50+"`.
  final String spf;

  /// `low` | `moderate` | `high` | `extreme`.
  final String level;
  final int uv;

  /// Gün içinde tazeleme gerekiyor mu (UV ≥ 5).
  final bool refresh;
  final int? refreshEveryMinutes;

  /// Gerçek saatlik UV biliniyorsa yüksek UV aralığı.
  final UvWindow? window;
}

class MoistureDecision {
  const MoistureDecision({required this.kind, required this.humidity, required this.temperature, required this.nightMask});

  /// `intense` | `barrier` | `boost` | `light` | `light_hot` | `standard`.
  final String kind;
  final int humidity;
  final int temperature;

  /// Çok kuru havada geceye oklüzif maske önerilir.
  final bool nightMask;
}

class LipBalmDecision {
  const LipBalmDecision({required this.needed, this.reason});

  final bool needed;

  /// `cold` | `dry` | `both`; gerek yoksa null.
  final String? reason;
}

class WeatherDecisions {
  const WeatherDecisions({required this.spf, required this.moisture, required this.lipBalm});

  /// Sunucu bu alanı göndermiyorsa ya da bozuksa null.
  static WeatherDecisions? fromJson(Object? json) {
    if (json is! Map) return null;
    final spf = json['spf'], moisture = json['moisture'], lip = json['lip_balm'];
    if (spf is! Map || moisture is! Map || lip is! Map) return null;
    final window = spf['window'];
    return WeatherDecisions(
      spf: SpfDecision(
        spf: '${spf['spf'] ?? '30'}',
        level: '${spf['level'] ?? 'low'}',
        uv: _int(spf['uv']),
        refresh: spf['refresh'] == true,
        refreshEveryMinutes: spf['refresh_every_minutes'] is num ? (spf['refresh_every_minutes'] as num).toInt() : null,
        window: window is Map && '${window['start'] ?? ''}'.isNotEmpty && '${window['end'] ?? ''}'.isNotEmpty
            ? UvWindow(start: '${window['start']}', end: '${window['end']}', peak: window['peak'] == null ? null : '${window['peak']}')
            : null,
      ),
      moisture: MoistureDecision(
        kind: '${moisture['kind'] ?? 'standard'}',
        humidity: _int(moisture['humidity']),
        temperature: _int(moisture['temperature']),
        nightMask: moisture['night_mask'] == true,
      ),
      lipBalm: LipBalmDecision(
        needed: lip['needed'] == true,
        reason: lip['reason'] == null ? null : '${lip['reason']}',
      ),
    );
  }

  final SpfDecision spf;
  final MoistureDecision moisture;
  final LipBalmDecision lipBalm;
}

int _int(Object? v) => v is num ? v.round() : int.tryParse('${v ?? ''}') ?? 0;
