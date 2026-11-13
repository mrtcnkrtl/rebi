import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/reminder_settings.dart';
import '../../core/routine_logic.dart';
import '../../core/routine_tracking.dart';
import '../../state/auth_controller.dart';
import '../../state/notifications_controller.dart';
import '../../ui/brand/brand_button.dart';
import '../../ui/brand/brand_caps.dart';
import '../../ui/brand/brand_mark.dart';
import '../../ui/brand/motion.dart';
import '../../ui/brand/palette.dart';
import '../../ui/tw.dart';
import '../reminders/time_picker.dart';

/// İlk rutin oluşturulduktan hemen sonra, bir kez açılan üç adımlık karşılama.
///
/// Tasarım dili "klinik sıcaklık": krem kâğıt zemin, orman yeşili mürekkep, Fraunces başlık; her adımda tek odak ve
/// tek ana düğme. Kart yığını, süs ya da parıltı yok. Adımlar:
///   1. Rutinin hazır: kısa profil satırı + sabah/akşam adım sayısı ve tahmini süre. "Takibe başla" rutini kabul eder;
///      "Önce planı incele" bugünkü plan ekranına (kabul kartıyla) gider.
///   2. Günün kaçta başlıyor: uyanma/uyku saati (hatırlatıcı pencereleri buna göre hesaplanır).
///   3. Hatırlatayım mı: o saatlerden hesaplanan üç örnek bildirim ve izin isteği.
/// Kullanıcı 2. ve 3. adımı atlayabilir; rutin 1. adımda kabul edildiği için yarıda bırakmak takibi bozmaz.
class FirstDayScreen extends StatefulWidget {
  const FirstDayScreen({super.key, required this.nav});

  /// Analizden taşınan rutin ve meta (`/dashboard`'a giden `extra` ile aynı).
  final Map<String, dynamic> nav;

  @override
  State<FirstDayScreen> createState() => _FirstDayScreenState();
}

/// Bir bakım adımının ortalama süresi (dakika); "yaklaşık süre" bunun katıdır.
const _minutesPerStep = 1;

class _FirstDayScreenState extends State<FirstDayScreen> {
  int _step = 0;
  bool _busy = false;
  ReminderSettings _settings = const ReminderSettings();
  bool _settingsTouched = false;

  late final AuthController _auth = context.read<AuthController>();
  String? get _uid => _auth.user?.id;

  late final RoutineView _view = RoutineView(asRoutine(widget.nav['routine']));

  @override
  void initState() {
    super.initState();
    final uid = _uid;
    if (uid != null) {
      // Daha önce ayar yapılmışsa (yeni analiz) onu göster; okunamazsa varsayılan 07:30 / 23:00.
      unawaited(
        fetchReminderSettings(uid)
            .then((s) {
              if (s != null && mounted && !_settingsTouched) setState(() => _settings = s);
            })
            .catchError((_) {}),
      );
    }
  }

  bool get _notificationsStep {
    final c = context.read<NotificationsController>();
    return c.supported && !c.enabled;
  }

  int get _stepCount => _notificationsStep ? 3 : 2;

  String get _name {
    final fromNav = '${widget.nav['userName'] ?? ''}'.trim();
    if (fromNav.isNotEmpty) return fromNav.split(' ').first;
    final meta = '${_auth.user?.userMetadata?['full_name'] ?? ''}'.trim();
    return meta.isEmpty ? '' : meta.split(' ').first;
  }

  List<String> get _profile {
    final f = widget.nav['flowDebug'];
    if (f is! Map) return const [];
    return [str(f['skin_type']), str(f['severity'])].where((s) => s.isNotEmpty).toList();
  }

  DayPlan get _today => _view.routineByDay[getTurkeyWeekdayIndex()] ?? const DayPlan([], []);

  // ── Eylemler ──────────────────────────────────────────────────────────────────────────────────

  Future<void> _startTracking() async {
    final uid = _uid;
    final nav = widget.nav;
    await acceptRoutineTracking(uid, {
      'routine': nav['routine'],
      'weather': nav['weather'],
      'userName': nav['userName'],
      'photoUrl': nav['photoUrl'],
      'flowDebug': nav['flowDebug'],
      'safetyAbsoluteRules': nav['safetyAbsoluteRules'],
      'ruleEnforcementReport': nav['ruleEnforcementReport'],
      'concern': nav['concern'],
      'assessmentId': nav['assessmentId'],
      'activePlan': nav['activePlan'] is List ? nav['activePlan'] : const [],
    });
    if (!mounted) return;
    unawaited(HapticFeedback.lightImpact());
    setState(() => _step = 1);
  }

  void _reviewPlan() => context.go('/dashboard', extra: widget.nav);

  void _finish() => context.go('/dashboard');

  Future<void> _pick(bool wake) async {
    final current = wake ? _settings.wakeMinutes : _settings.sleepMinutes;
    final picked = await pickClockMinutes(context, current);
    if (picked == null || !mounted) return;
    setState(() {
      _settingsTouched = true;
      _settings = wake ? _settings.copyWith(wakeTime: formatClock(picked)) : _settings.copyWith(sleepTime: formatClock(picked));
    });
  }

  Future<void> _saveDay() async {
    final uid = _uid;
    if (uid != null && _settingsTouched) {
      setState(() => _busy = true);
      // Kaydedilemezse (ağ yok) akış durmaz: saatler Hatırlatıcılar ekranından sonra da ayarlanabilir.
      await saveReminderSettings(uid, _settings);
      if (!mounted) return;
      setState(() => _busy = false);
    }
    if (_notificationsStep) {
      setState(() => _step = 2);
    } else {
      _finish();
    }
  }

  Future<void> _enableNotifications() async {
    setState(() => _busy = true);
    try {
      await context.read<NotificationsController>().enable();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) _finish();
  }

  // ── Görünüm ───────────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return Scaffold(
      backgroundColor: Brand.paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopBar(
                    step: _step,
                    count: _stepCount,
                    skipLabel: i18n.t('mobileWelcome.skip'),
                    onSkip: _step == 0 || _busy ? null : _finish,
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 420),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(.06, 0), end: Offset.zero).animate(anim),
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(key: ValueKey(_step), child: _body(i18n)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(I18n i18n) => switch (_step) {
    0 => _ready(i18n),
    1 => _day(i18n),
    _ => _notify(i18n),
  };

  Widget _page({
    required String eyebrow,
    required String title,
    required String body,
    required Widget middle,
    required List<Widget> actions,
  }) {
    final lang = context.i18n.lang;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 28, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(width: 22, height: 1.5, color: Brand.tealDeep),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        brandCaps(eyebrow, lang),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tx(11, w: 7, c: Brand.inkSoft, ls: brandTracking(lang, 2.0)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Semantics(header: true, child: Text(title, style: Brand.serif(34, h: 1.08))),
                const SizedBox(height: 12),
                Text(body, style: tx(15.5, c: Brand.inkSoft, h: 1.5)),
                const SizedBox(height: 32),
                middle,
              ],
            ),
          ),
        ),
        ...actions,
      ],
    );
  }

  Widget _ready(I18n i18n) {
    final today = _today;
    final morning = today.morning.length;
    final evening = today.evening.length;
    final name = _name;
    final profile = _profile;
    // Rutinden somut bir önizleme: bu sabahın (sabah adımı yoksa bu akşamın) ilk dört adımı, kısa adlarıyla.
    final preview = (today.morning.isNotEmpty ? today.morning : today.evening).take(4).toList();
    return _page(
      eyebrow: i18n.t('mobileWelcome.ready.eyebrow'),
      title: name.isEmpty ? i18n.t('mobileWelcome.ready.titleNoName') : i18n.t('mobileWelcome.ready.title', {'name': name}),
      body: i18n.t('mobileWelcome.ready.body'),
      middle: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (profile.isNotEmpty) ...[Text(profile.join('  ·  '), style: tx(13.5, w: 6, c: Brand.ink)), const SizedBox(height: 18)],
          Reveal(
            delay: const Duration(milliseconds: 160),
            child: _Stats(
              items: [
                (value: '$morning', label: i18n.t('mobileWelcome.ready.morning')),
                (value: '$evening', label: i18n.t('mobileWelcome.ready.evening')),
                (value: '~${(morning + evening) * _minutesPerStep}', label: i18n.t('mobileWelcome.ready.minutes')),
              ],
            ),
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 28),
            Reveal(
              delay: const Duration(milliseconds: 300),
              child: _StepPreview(
                label: i18n.t(today.morning.isNotEmpty ? 'mobileWelcome.ready.thisMorning' : 'mobileWelcome.ready.thisEvening'),
                names: [for (final item in preview) shortStepName(pickAction(item, localized: i18n.prefersLocalized))],
              ),
            ),
          ],
        ],
      ),
      actions: [
        BrandButton(onPressed: _startTracking, label: i18n.t('mobileWelcome.ready.start'), trailingIcon: LucideIcons.arrowRight),
        const SizedBox(height: 6),
        _QuietButton(label: i18n.t('mobileWelcome.ready.review'), onPressed: _reviewPlan),
      ],
    );
  }

  Widget _day(I18n i18n) {
    final valid = _settings.dayIsValid;
    return _page(
      eyebrow: i18n.t('mobileWelcome.day.eyebrow'),
      title: i18n.t('mobileWelcome.day.title'),
      body: i18n.t('mobileWelcome.day.body'),
      middle: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ClockRow(
            icon: LucideIcons.sunrise,
            label: i18n.t('mobileWelcome.day.wake'),
            value: _settings.wakeTime,
            onTap: () => _pick(true),
          ),
          Divider(height: 1, color: Brand.inkFaint),
          _ClockRow(
            icon: LucideIcons.moon,
            label: i18n.t('mobileWelcome.day.sleep'),
            value: _settings.sleepTime,
            onTap: () => _pick(false),
          ),
          if (!valid) ...[
            const SizedBox(height: 12),
            Text(i18n.t('mobileWelcome.day.invalid'), style: tx(13, w: 5, c: Tw.rose600, h: 1.4)),
          ],
        ],
      ),
      actions: [
        BrandButton(
          onPressed: valid && !_busy ? _saveDay : null,
          loading: _busy,
          label: i18n.t('mobileWelcome.day.next'),
          trailingIcon: LucideIcons.arrowRight,
        ),
      ],
    );
  }

  Widget _notify(I18n i18n) {
    final s = _settings;
    String at(String id) => defaultReminderWindow(id, s)?.start ?? '';
    final samples = [
      (time: at('routine_morning'), title: i18n.t('mobileWelcome.notify.morningTitle'), body: i18n.t('mobileWelcome.notify.morningBody')),
      (time: at('water_intake'), title: i18n.t('mobileWelcome.notify.waterTitle'), body: i18n.t('mobileWelcome.notify.waterBody')),
      (time: at('routine_evening'), title: i18n.t('mobileWelcome.notify.eveningTitle'), body: i18n.t('mobileWelcome.notify.eveningBody')),
    ];
    return _page(
      eyebrow: i18n.t('mobileWelcome.notify.eyebrow'),
      title: i18n.t('mobileWelcome.notify.title'),
      body: i18n.t('mobileWelcome.notify.body'),
      middle: Column(
        children: [
          for (var i = 0; i < samples.length; i++)
            Reveal(
              delay: Duration(milliseconds: 120 + i * 110),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _NotificationPreview(time: samples[i].time, title: samples[i].title, body: samples[i].body),
              ),
            ),
        ],
      ),
      actions: [
        BrandButton(
          onPressed: _busy ? null : _enableNotifications,
          loading: _busy,
          label: i18n.t('mobileWelcome.notify.enable'),
          trailingIcon: LucideIcons.bell,
        ),
        const SizedBox(height: 6),
        _QuietButton(label: i18n.t('mobileWelcome.notify.later'), onPressed: _busy ? null : _finish),
      ],
    );
  }
}

/// Üstte ince adım çizgileri ve "Atla".
class _TopBar extends StatelessWidget {
  const _TopBar({required this.step, required this.count, required this.skipLabel, required this.onSkip});

  final int step;
  final int count;
  final String skipLabel;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              label: context.i18n.t('mobileWelcome.progress', {'n': '${step + 1}', 'total': '$count'}),
              child: Row(
                children: [
                  for (var i = 0; i < count; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 380),
                        height: 3,
                        decoration: BoxDecoration(color: i <= step ? Brand.ink : Brand.inkFaint, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: onSkip == null ? 0 : 1,
            child: TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(minimumSize: const Size(48, 44), foregroundColor: Brand.inkSoft),
              child: Text(skipLabel, style: tx(14, w: 6, c: Brand.inkSoft)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Üç sakin rakam; aralarında ince dikey çizgi.
class _Stats extends StatelessWidget {
  const _Stats({required this.items});

  final List<({String value, String label})> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: Brand.inkFaint)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) VerticalDivider(width: 1, thickness: 1, color: Brand.inkFaint),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(items[i].value, style: Brand.serif(38, h: 1)),
                      const SizedBox(height: 6),
                      Text(items[i].label, style: tx(12.5, c: Brand.inkSoft, h: 1.3)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Bu sabah" önizlemesi: küçük başlık ve numaralı kısa adım adları.
class _StepPreview extends StatelessWidget {
  const _StepPreview({required this.label, required this.names});

  final String label;
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final lang = context.i18n.lang;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(brandCaps(label, lang), style: tx(11, w: 7, c: Brand.inkSoft, ls: brandTracking(lang, 1.6))),
        const SizedBox(height: 12),
        for (var i = 0; i < names.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Brand.ink.withValues(alpha: .35))),
                  child: Text('${i + 1}', style: tx(12, w: 7, c: Brand.ink)),
                ),
                const SizedBox(width: 14),
                Expanded(child: Text(names[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(16, w: 5, c: Brand.ink))),
              ],
            ),
          ),
      ],
    );
  }
}

class _ClockRow extends StatelessWidget {
  const _ClockRow({required this.icon, required this.label, required this.value, required this.onTap});

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label $value',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(
            children: [
              Icon(icon, size: 22, color: Brand.inkSoft),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label, style: tx(16, w: 5, c: Brand.ink)),
              ),
              Text(value, style: Brand.serif(30, h: 1)),
              const SizedBox(width: 8),
              Icon(LucideIcons.chevronRight, size: 18, color: Brand.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

/// Telefon bildirimine benzeyen örnek: küçük marka işareti, saat, başlık, gövde.
class _NotificationPreview extends StatelessWidget {
  const _NotificationPreview({required this.time, required this.title, required this.body});

  final String time;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Brand.inkFaint),
        boxShadow: [if (!Brand.dark) BoxShadow(color: Brand.forest.withValues(alpha: .06), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: BrandMark(size: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Rebi', style: tx(12, w: 6, c: Brand.inkSoft)),
                    ),
                    Text(time, style: tx(12, w: 5, c: Brand.inkSoft)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(title, style: tx(14.5, w: 7, c: Brand.ink)),
                const SizedBox(height: 2),
                Text(body, style: tx(13.5, c: Brand.inkSoft, h: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuietButton extends StatelessWidget {
  const _QuietButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(minimumSize: const Size(48, 52), foregroundColor: Brand.ink),
      child: Text(label, style: tx(15, w: 6, c: Brand.ink)),
    );
  }
}
