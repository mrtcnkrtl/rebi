import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/checkin_prefill.dart';
import '../core/checkin_stats.dart';
import '../core/daily_tracking.dart';
import '../core/demo_user.dart';
import '../core/i18n.dart';
import '../core/routine_logic.dart';
import '../core/routine_tracking.dart';
import '../core/today_plan.dart';
import '../state/auth_controller.dart';
import '../state/theme_controller.dart';
import '../ui/brand/glyphs.dart';
import '../ui/shell/page_stage.dart';
import '../ui/tw.dart';
import '../ui/widgets/common.dart';
import '../ui/widgets/skeleton.dart';
import 'analyze/analyze_widgets.dart';

/// Cilt hissi seçenekleri: kimlikler sunucuya giden değerlerdir, başlık/açıklama `mobileCheckin.skin.<kimlik>` içindedir.
const _skinFeelingIds = ['iyi', 'kuru', 'yagli', 'kirik', 'irritasyon'];

const _concernExtraKeys = [
  'picked_skin_today',
  'high_glycemic_intake_today',
  'heavy_dairy_today',
  'long_sun_exposure_today',
  'spf_applied_today',
  'very_dry_environment_today',
  'long_hot_shower_today',
  'fragrance_new_product_today',
  'tried_new_active_today',
];

/// Check-in su: Türkiye'de sık kullanılan "1 bardak ≈ 250 ml" (2 L ≈ 8 bardak).
const mlPerGlass = 250;

int? parseWaterMlInput(String? raw) {
  final s = (raw ?? '').trim().replaceFirst(',', '.');
  if (s.isEmpty) return null;
  final n = num.tryParse(s);
  if (n == null || !n.isFinite || n < 0) return null;
  final r = n.round();
  return r > 8000 ? 8000 : r;
}

String formatGlassesLabel(int ml) {
  final i18n = I18n.instance;
  if (ml <= 0) return i18n.t('mobileCheckin.water.zeroGlasses');
  final glasses = ml / mlPerGlass;
  final num rounded = (glasses - glasses.round()).abs() < 0.05 ? glasses.round() : (glasses * 10).round() / 10;
  return i18n.t('mobileCheckin.water.aboutGlasses', {'n': jsString(rounded)});
}

/// Günlük check-in (web: `pages/CheckIn.jsx`). Üst sahne (`StagePage`) diğer ekranlarla aynı dildedir; dört durum
/// (yükleniyor, bugün yapıldı, form, rapor) hep sahneyle başlar. Tüm metinler `mobileCheckin.*` / `checkin.*` içindedir.
class CheckInScreen extends StatefulWidget {
  const CheckInScreen({super.key});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  double _sleepHours = 7;
  int _stressToday = 3;
  String _skinFeeling = '';
  bool _appliedRoutine = true;
  final _notes = TextEditingController();
  bool _ctxLoading = true;
  String _concern = 'acne';
  double _assessmentWater = 2;
  double _assessmentMakeup = 0;
  final _waterMl = TextEditingController();
  bool? _makeupUsedToday;
  String _makeupRemovalToday = 'cleanser';
  final Map<String, bool?> _concernExtra = {for (final k in _concernExtraKeys) k: null};
  bool _loading = false;
  Map<String, dynamic>? _result;
  bool _alreadyCheckedIn = false;
  bool _statusLoading = true;
  String _submitError = '';
  final List<String> _symptomTags = [];
  int _reactionSeverity = 2;
  bool _feedbackBusy = false;

  /// Bugünkü takip kayıtlarından önceden doldurulan cevap sayısı (0 ise bilgi çıkmaz).
  int _prefilled = 0;

  /// null | sent | skipped
  String? _feedbackStatus;
  final _feedbackNote = TextEditingController();

  String? get _uid => context.read<AuthController>().user?.id;

  @override
  void initState() {
    super.initState();
    _waterMl.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = _uid;
      if (id != null && !isRoutineTrackingAccepted(id)) {
        context.go('/dashboard', extra: const {'flashNeedAccept': true});
        return;
      }
      _loadContext();
      _loadStatus();
      _prefillFromTracking();
    });
  }

  @override
  void dispose() {
    _notes.dispose();
    _waterMl.dispose();
    _feedbackNote.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    final id = _uid;
    final client = supabase;
    if (id == null || client == null) {
      setState(() => _ctxLoading = false);
      return;
    }
    try {
      final row = await client
          .from('assessments')
          .select('concern, lifestyle_data')
          .eq('user_id', id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (!mounted) return;
      final life = (row?['lifestyle_data'] as Map?) ?? const {};
      setState(() {
        _concern = truthy(row?['concern']) ? row!['concern'].toString() : 'acne';
        _assessmentWater = (num.tryParse('${life['water_intake'] ?? 2}') ?? double.nan).toDouble();
        _assessmentMakeup = (num.tryParse('${life['makeup_frequency'] ?? 0}') ?? double.nan).toDouble();
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _concern = 'acne';
          _assessmentWater = 2;
          _assessmentMakeup = 0;
        });
      }
    } finally {
      if (mounted) setState(() => _ctxLoading = false);
    }
  }

  /// Bugünkü takip kayıtlarıyla (su, makyaj, beslenme, güneş kremi) soruları önceden doldurur.
  /// Kullanıcı bu sırada bir soruyu zaten cevapladıysa onun cevabı korunur.
  Future<void> _prefillFromTracking() async {
    final id = _uid;
    if (id == null || id == demoUserId) return;
    try {
      final res = await apiGet('/daily_tracking/today', query: {'user_id': id, 'utc_offset_minutes': localUtcOffsetMinutes()});
      if (!mounted || !res.ok) return;
      final prefill = checkinPrefill(DayProgress.fromJson(res.data['aggregated']));
      if (prefill.isEmpty) return;
      var applied = 0;
      setState(() {
        final water = prefill.waterMl;
        if (water != null && _waterMl.text.isEmpty) {
          _waterMl.text = '$water';
          applied++;
        }
        final used = prefill.makeupUsed;
        if (used != null && _makeupUsedToday == null) {
          _makeupUsedToday = used;
          applied++;
          final method = prefill.removalMethod;
          if (used && method != null) {
            _makeupRemovalToday = method;
            applied++;
          }
        }
        prefill.extras.forEach((key, value) {
          if (_concernExtra[key] == null) {
            _concernExtra[key] = value;
            applied++;
          }
        });
        _prefilled = applied;
      });
    } catch (_) {
      /* çevrimdışı: sorular boş kalır, elle cevaplanır */
    }
  }

  Future<void> _loadStatus() async {
    final id = _uid;
    if (id == null) {
      setState(() => _statusLoading = false);
      return;
    }
    try {
      final res = await apiGet('/daily_checkin/status', query: {'user_id': id, 'utc_offset_minutes': localUtcOffsetMinutes()});
      if (!mounted) return;
      if (!res.ok) {
        setState(() => _submitError = formatApiErrorDetail(res.data));
        return;
      }
      if (res.data['already_checked_in'] == true) setState(() => _alreadyCheckedIn = true);
    } catch (e) {
      if (mounted && isNetworkError(e)) setState(() => _submitError = I18n.instance.t('mobileCheckin.errors.network'));
    } finally {
      if (mounted) setState(() => _statusLoading = false);
    }
  }

  bool get _canSubmit => _skinFeeling.isNotEmpty && !_loading && !_alreadyCheckedIn && !_ctxLoading;

  static const _concernDriven = ['acne', 'dryness', 'pigmentation', 'sensitivity', 'aging'];

  bool get _showWaterExtra => _concernDriven.contains(_concern) || _assessmentWater < 2;

  bool get _showMakeupExtra =>
      _assessmentMakeup >= 3 || const ['acne', 'pigmentation', 'sensitivity', 'aging'].contains(_concern);

  bool get _showConcernIntro => _concernDriven.contains(_concern);

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final i18n = I18n.instance;
    final user = context.read<AuthController>().user;
    setState(() {
      _loading = true;
      _submitError = '';
    });
    try {
      final payload = <String, dynamic>{
        'user_id': user?.id ?? demoUserId,
        'sleep_hours': _sleepHours,
        'stress_today': _stressToday,
        'skin_feeling': _skinFeeling,
        'applied_routine': _appliedRoutine,
        'notes': _notes.text.isEmpty ? null : _notes.text,
        'utc_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
      };
      final w = parseWaterMlInput(_waterMl.text);
      if (w != null && w > 0) payload['water_ml_today'] = w;
      if (_makeupUsedToday != null) {
        payload['makeup_used_today'] = _makeupUsedToday;
        if (_makeupUsedToday == true) payload['makeup_removal_today'] = _makeupRemovalToday;
      }
      for (final k in _concernExtraKeys) {
        final v = _concernExtra[k];
        if (v != null) payload[k] = v;
      }
      if (_symptomTags.isNotEmpty) payload['symptom_tags'] = _symptomTags;
      if (_skinFeeling == 'irritasyon' || _skinFeeling == 'kirik') {
        payload['active_reaction_severity'] = _reactionSeverity;
      }

      final res = await apiPost('/daily_checkin', payload, timeout: apiLongTimeout);
      if (!mounted) return;
      if (res.status == 409) {
        final d = res.data['detail'];
        setState(() {
          _submitError = d is String ? d : i18n.t('mobileCheckin.errors.alreadyDone');
          _alreadyCheckedIn = true;
        });
        return;
      }
      if (!res.ok) {
        setState(() => _submitError = '${apiErrorMessage(res)} (${res.status})');
        return;
      }
      await recordCheckInSuccess(user?.id, appliedRoutine: _appliedRoutine);
      if (!mounted) return;
      setState(() {
        _feedbackStatus = null;
        _feedbackNote.clear();
        _result = res.data;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _submitError = i18n.t(isNetworkError(e) ? 'mobileCheckin.errors.network' : 'mobileCheckin.errors.unexpected'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendFeedback(String helpful) async {
    setState(() => _feedbackBusy = true);
    final note = _feedbackNote.text;
    await ingestDailyTrackingEvent(_uid, 'checkin_feedback', {
      'helpful': helpful,
      'note': note.length > 500 ? note.substring(0, 500) : note,
      'source_screen': 'checkin_report',
    });
    if (!mounted) return;
    setState(() {
      _feedbackStatus = 'sent';
      _feedbackBusy = false;
    });
  }

  Future<void> _backToDashboard() async {
    final result = _result!;
    final id = _uid;
    final today = asRoutine(result['today_routine']);
    if (id != null && isRoutineTrackingAccepted(id) && today.isNotEmpty) {
      await saveRoutineSnapshot(id, {...?getRoutineSnapshot(id), 'routine': result['today_routine'], 'checkinResult': result});
    }
    if (!mounted) return;
    context.go('/dashboard', extra: {'routine': result['today_routine'], 'checkinResult': result});
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = context.watch<ThemeController>().theme;

    if (_result != null) return _resultView(i18n, theme);

    if (_statusLoading) {
      return StagePage(
        theme: theme,
        title: i18n.t('checkin.title'),
        subtitle: i18n.t('checkin.subtitle'),
        backTo: '/dashboard',
        children: const [SkeletonCard(lines: 3), SizedBox(height: 12), SkeletonCard(lines: 3)],
      );
    }

    if (_alreadyCheckedIn) {
      return StagePage(
        theme: theme,
        title: i18n.t('checkin.alreadyTitle'),
        subtitle: i18n.t('checkin.alreadyDesc'),
        backTo: '/dashboard',
        children: [
          RCard(
            padding: const EdgeInsets.all(20),
            radius: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: Icon(LucideIcons.circleCheckBig, size: 44, color: theme.fg)),
                const SizedBox(height: 18),
                PrimaryButton(color: theme.primary, label: i18n.t('checkin.backToDashboard'), onPressed: () => context.go('/dashboard')),
              ],
            ),
          ),
        ],
      );
    }

    return _formView(i18n, theme);
  }

  // ---- Rapor ----

  Widget _resultView(I18n i18n, RebiTheme theme) {
    final result = _result!;
    final changes = (result['changes'] as List?)?.whereType<Map>().toList() ?? const [];
    final today = asRoutine(result['today_routine']);
    final localized = i18n.prefersLocalized;
    final risk = i18n.t('mobileCheckin.result.risk', {'level': str(result['risk_level'])});
    final subtitle = result['adaptation_type'] == 'major' ? '$risk · ${i18n.t('mobileCheckin.result.major')}' : risk;

    return StagePage(
      theme: theme,
      title: i18n.t('checkin.todayReport'),
      subtitle: subtitle,
      backTo: '/dashboard',
      children: [
        if (truthy(result['ai_note'])) ...[
          RCard(
            leftBorderColor: theme.primary,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 2), child: Icon(LucideIcons.sparkles, size: 20, color: theme.fg)),
                const SizedBox(width: 12),
                Expanded(child: Text(str(result['ai_note']), style: tx(14.5, c: Tw.gray700, h: relaxed))),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (changes.isNotEmpty) ...[
          RCard(
            padding: const EdgeInsets.all(18),
            radius: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _cardTitle(LucideIcons.circleAlert, Tw.amber600, i18n.t('mobileCheckin.result.changes')),
                const SizedBox(height: 12),
                for (var i = 0; i < changes.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(Tw.amber50.withValues(alpha: .6), Tw.surface),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Tw.amber100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(str(changes[i]['item']), style: tx(14, w: 6, c: Tw.gray800)),
                        const SizedBox(height: 3),
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(text: '${str(changes[i]['old'])} → '),
                            TextSpan(text: str(changes[i]['new']), style: tx(12.5, w: 6, c: theme.fg)),
                          ]),
                          style: tx(12.5, c: Tw.gray600),
                        ),
                        const SizedBox(height: 3),
                        Text(str(changes[i]['reason']), style: tx(12.5, c: Tw.gray600, h: snug)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (today.isNotEmpty) ...[
          RCard(
            padding: const EdgeInsets.all(18),
            radius: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _cardTitle(LucideIcons.listChecks, theme.fg, i18n.t('mobileCheckin.result.todayRoutine')),
                const SizedBox(height: 12),
                for (var i = 0; i < today.take(10).length; i++) ...[
                  if (i > 0) const Divider(height: 20, thickness: 1),
                  _routineRow(today[i], theme, localized),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_feedbackStatus == null)
          RCard(
            padding: const EdgeInsets.all(18),
            radius: 22,
            margin: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(i18n.t('checkin.feedbackTitle'), style: tx(14, w: 6, c: Tw.gray800, h: snug)),
                const SizedBox(height: 10),
                TextField(
                  controller: _feedbackNote,
                  minLines: 2,
                  maxLines: 3,
                  style: tx(14),
                  decoration: inputDecoration(
                    radius: 14,
                    borderWidth: 1,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _feedbackButton(
                        border: Tw.emerald200,
                        bg: Tw.emerald50,
                        fg: Tw.emerald900,
                        icon: LucideIcons.thumbsUp,
                        label: 'OK',
                        onTap: _feedbackBusy ? null : () => _sendFeedback('helpful'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _feedbackButton(
                        border: Tw.rose200,
                        bg: Tw.rose50,
                        fg: Tw.rose900,
                        icon: LucideIcons.thumbsDown,
                        onTap: _feedbackBusy ? null : () => _sendFeedback('not_helpful'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: TextButton(
                        onPressed: _feedbackBusy ? null : () => setState(() => _feedbackStatus = 'skipped'),
                        style: TextButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Tw.gray200)),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          minimumSize: const Size(48, 48),
                        ),
                        child: Text(i18n.t('checkin.feedbackSkip'), style: tx(13, w: 5, c: Tw.gray600)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )
        else if (_feedbackStatus == 'sent')
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(i18n.t('checkin.feedbackThanks'), textAlign: TextAlign.center, style: tx(13, c: Tw.readable(Tw.emerald700))),
          ),
        PrimaryButton(
          color: theme.primary,
          label: i18n.t('checkin.backToDashboard'),
          trailingIcon: LucideIcons.arrowRight,
          onPressed: _backToDashboard,
        ),
      ],
    );
  }

  Widget _routineRow(RoutineItem item, RebiTheme theme, bool localized) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(glyphForEmoji(str(item['icon']), fallback: LucideIcons.dot), size: 18, color: Tw.gray600),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(pickAction(item, localized: localized), style: tx(13.5, w: 6, c: Tw.gray800, h: snug)),
              StructuredBadges(item: item),
              const SizedBox(height: 2),
              Text(
                pickDetail(item, localized: localized),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tx(12, c: Tw.gray600, h: snug),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: theme.primaryLight, borderRadius: BorderRadius.circular(999)),
          child: Text(str(item['time']), style: tx(11, w: 6, c: theme.primaryDark)),
        ),
      ],
    );
  }

  Widget _feedbackButton({
    required Color border,
    required Color bg,
    required Color fg,
    required IconData icon,
    String? label,
    required VoidCallback? onTap,
  }) {
    return Opacity(
      opacity: onTap == null ? .6 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: border, width: 1.5)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: fg),
                if (label != null) ...[const SizedBox(width: 8), Text(label, style: tx(14, w: 6, c: fg))],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardTitle(IconData icon, Color color, String text) => Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: tx(14.5, w: 7, c: Tw.gray800, h: snug))),
        ],
      );

  // ---- Seçim parçaları ----

  /// Seçilebilir kutu (stres düzeyi, cilt hissi): seçiliyken tema çerçevesi ve soluk dolgu, ölçeklenme yok.
  Widget _selectable({required bool selected, required RebiTheme theme, required Widget child, required VoidCallback onTap, EdgeInsets? padding}) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? theme.primaryLight.withValues(alpha: Tw.dark ? .35 : .55) : Tw.gray50,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? theme.primary : Colors.transparent, width: 1.6),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _yesNo(String label, bool selected, RebiTheme theme, VoidCallback onTap) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? Tw.fillWithWhiteText(theme.primary) : Tw.gray50,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(label, textAlign: TextAlign.center, style: tx(16, w: selected ? 6 : 5, c: selected ? Colors.white : Tw.gray700)),
          ),
        ),
      ),
    );
  }

  /// Evet / Hayır / Atla düğmesi (ek sorular, makyaj).
  Widget _tri(String label, bool selected, RebiTheme theme, VoidCallback onTap, {bool plain = false}) => Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? theme.primaryLight.withValues(alpha: Tw.dark ? .35 : .55) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: selected ? theme.primary : Tw.gray200, width: selected ? 1.6 : 1.3),
              ),
              child: Text(label, textAlign: TextAlign.center, style: tx(13.5, w: selected ? 6 : 5, c: plain ? Tw.gray600 : Tw.gray900)),
            ),
          ),
        ),
      );

  // ---- Form ----

  Widget _formView(I18n i18n, RebiTheme theme) {
    const gap = SizedBox(height: 16);
    final skinSevere = _skinFeeling == 'irritasyon' || _skinFeeling == 'kirik';
    return StagePage(
      theme: theme,
      title: i18n.t('checkin.title'),
      subtitle: i18n.t('checkin.subtitle'),
      backTo: '/dashboard',
      bottomBar: _submitBar(i18n, theme),
      children: [
        if (_submitError.isNotEmpty) ...[
          NoticeBox(text: _submitError, bg: Tw.amber50, border: Tw.amber200, fg: Tw.amber900, fontSize: 13.5),
          gap,
        ],
        if (_prefilled > 0) ...[
          NoticeBox(
            text: i18n.t('mobileCheckin.prefilled', {'n': _prefilled}),
            // Sahneye binebilir: yarı saydam dolgu sahnenin koyusunu geçirir, bu yüzden yüzeyle karıştırılıp opak yapılır.
            bg: Color.alphaBlend(theme.primaryLight.withValues(alpha: .35), Tw.surface),
            border: theme.primaryLight,
            fg: Tw.readable(theme.primaryDark, bg: Color.alphaBlend(theme.primaryLight.withValues(alpha: .35), Tw.surface)),
            icon: LucideIcons.sparkles,
            fontSize: 13,
          ),
          gap,
        ],
        // Uyku
        RCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cardTitle(LucideIcons.moon, Tw.indigo500, i18n.t('mobileCheckin.sleep.question')),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: RangeSlider1(
                      value: _sleepHours,
                      min: 3,
                      max: 12,
                      step: .5,
                      color: Tw.indigo500,
                      onChanged: (v) => setState(() => _sleepHours = v),
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 56,
                    child: Text(
                      i18n.t('mobileCheckin.sleep.unit', {'h': jsString(_sleepHours)}),
                      textAlign: TextAlign.center,
                      style: tx(18, w: 7, c: Tw.dark ? Tw.indigo400 : Tw.indigo600),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final h in const ['3', '7.5', '12']) Text(i18n.t('mobileCheckin.sleep.unit', {'h': h}), style: tx(11.5, c: Tw.gray500)),
                  ],
                ),
              ),
            ],
          ),
        ),
        gap,
        // Stres
        RCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cardTitle(LucideIcons.smilePlus, Tw.purple500, i18n.t('mobileCheckin.stress.question')),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var value = 1; value <= 5; value++) ...[
                    if (value > 1) const SizedBox(width: 6),
                    Expanded(
                      child: _selectable(
                        selected: _stressToday == value,
                        theme: theme,
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                        onTap: () => setState(() => _stressToday = value),
                        child: Column(
                          children: [
                            Icon(stressGlyph(value), size: 24, color: _stressToday == value ? theme.fg : Tw.gray500),
                            const SizedBox(height: 4),
                            Text(
                              i18n.t('mobileCheckin.stress.l$value'),
                              textAlign: TextAlign.center,
                              style: tx(11.5, w: _stressToday == value ? 6 : 5, c: _stressToday == value ? Tw.readable(theme.primaryDark) : Tw.gray600, h: tight),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        gap,
        // Cilt hissi
        RCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cardTitle(LucideIcons.droplets, theme.fg, i18n.t('mobileCheckin.skin.question')),
              const SizedBox(height: 12),
              for (final id in _skinFeelingIds) ...[
                _selectable(
                  selected: _skinFeeling == id,
                  theme: theme,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  onTap: () => setState(() => _skinFeeling = id),
                  child: Row(
                    children: [
                      Icon(skinFeelingGlyph(id), size: 22, color: _skinFeeling == id ? theme.fg : Tw.gray500),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(i18n.t('mobileCheckin.skin.$id.title'), style: tx(14.5, w: 6, c: Tw.gray800)),
                            Text(i18n.t('mobileCheckin.skin.$id.desc'), style: tx(12.5, c: Tw.gray600)),
                          ],
                        ),
                      ),
                      if (_skinFeeling == id) Icon(LucideIcons.circleCheckBig, size: 20, color: theme.fg),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        gap,
        RCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(i18n.t('checkin.symptomsTitle'), style: tx(14.5, w: 7, c: Tw.gray800, h: snug)),
              const SizedBox(height: 4),
              Text(i18n.t('checkin.symptomsHint'), style: tx(12.5, c: Tw.gray600, h: relaxed)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (id, key) in const [
                    ('redness_diffuse', 'checkin.symptomRedness'),
                    ('burning_stinging', 'checkin.symptomBurning'),
                    ('flaking_peeling', 'checkin.symptomFlaking'),
                    ('acne_flare', 'checkin.symptomAcne'),
                  ])
                    ChoiceChipBox(
                      label: i18n.t(key),
                      selected: _symptomTags.contains(id),
                      activeText: Tw.teal900,
                      inactiveText: Tw.gray600,
                      onTap: () => setState(() => _symptomTags.contains(id) ? _symptomTags.remove(id) : _symptomTags.add(id)),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (skinSevere) ...[
          gap,
          RCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(i18n.t('checkin.reactionSeverityTitle'), style: tx(14.5, w: 7, c: Tw.gray800, h: snug)),
                const SizedBox(height: 4),
                Text(i18n.t('checkin.reactionSeverityHint'), style: tx(12.5, c: Tw.gray600, h: relaxed)),
                const SizedBox(height: 8),
                RangeSlider1(
                  value: _reactionSeverity.toDouble(),
                  min: 1,
                  max: 3,
                  step: 1,
                  color: Tw.teal600,
                  onChanged: (v) => setState(() => _reactionSeverity = v.round()),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [for (final n in ['1', '2', '3']) Text(n, style: tx(11.5, c: Tw.gray500))],
                ),
              ],
            ),
          ),
        ],
        gap,
        // Rutin uygulandı mı
        RCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cardTitle(LucideIcons.circleCheckBig, Tw.green600, i18n.t('mobileCheckin.routineQuestion')),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _yesNo(i18n.t('common.yes'), _appliedRoutine, theme, () => setState(() => _appliedRoutine = true))),
                  const SizedBox(width: 12),
                  Expanded(child: _yesNo(i18n.t('common.no'), !_appliedRoutine, theme, () => setState(() => _appliedRoutine = false))),
                ],
              ),
            ],
          ),
        ),
        if (_showConcernIntro) ...[
          gap,
          RCard(
            borderColor: Tw.slate100,
            color: Color.alphaBlend(Tw.slate50.withValues(alpha: .9), Tw.surface),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: i18n.t('mobileCheckin.concernIntro.lead'), style: TextStyle(fontWeight: FontWeight.w600, color: Tw.slate800)),
                TextSpan(text: ' ${i18n.t('mobileCheckin.concernIntro.body')}'),
              ]),
              style: tx(12.5, c: Tw.slate600, h: relaxed),
            ),
          ),
        ],
        if (_showWaterExtra) ...[gap, _waterCard(i18n, theme)],
        if (_showMakeupExtra) ...[gap, _makeupCard(i18n, theme)],
        ..._concernExtras(i18n, theme),
        gap,
        RCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${i18n.t('mobileCheckin.notes.question')} '),
                  TextSpan(text: i18n.t('mobileCheckin.notes.optional'), style: tx(14, c: Tw.gray500)),
                ]),
                style: tx(14.5, w: 7, c: Tw.gray800, h: snug),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                style: tx(14),
                decoration: inputDecoration(
                  hint: i18n.t('mobileCheckin.notes.hint'),
                  radius: 14,
                  borderWidth: 1,
                  focusColor: theme.primary,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 18, 8, 0),
          child: Text(i18n.t('mobileCheckin.blendNote'), textAlign: TextAlign.center, style: tx(12, c: Tw.gray500, h: relaxed)),
        ),
      ],
    );
  }

  /// Sabit gönder çubuğu: uzun formun sonuna kaydırmadan gönderilir; düğme kapalıyken nedenini söyler (cilt hissi seçilmedi).
  Widget _submitBar(I18n i18n, RebiTheme theme) {
    final needsSkin = _skinFeeling.isEmpty && !_loading;
    return StageBottomBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (needsSkin)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(i18n.t('mobileCheckin.needSkin'), textAlign: TextAlign.center, style: tx(12.5, w: 5, c: Tw.gray600, h: snug)),
            ),
          if (_loading)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(liveRegion: true, child: Text(i18n.t('mobileCheckin.analyzing'), textAlign: TextAlign.center, style: tx(12.5, c: Tw.gray600))),
            ),
          PrimaryButton(
            color: theme.primary,
            loading: _loading,
            icon: LucideIcons.send,
            label: i18n.t('checkin.submit'),
            onPressed: _canSubmit ? _submit : null,
            minHeight: 54,
          ),
        ],
      ),
    );
  }

  Widget _waterCard(I18n i18n, RebiTheme theme) {
    final parsed = parseWaterMlInput(_waterMl.text);
    void bump(int delta) {
      final next = ((parsed ?? 0) + delta).clamp(0, 8000);
      _waterMl.text = '$next';
    }

    Widget smallBtn(String label, VoidCallback onTap, {bool primary = false}) => Material(
          color: primary ? Tw.fillWithWhiteText(theme.primary) : Tw.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: primary ? theme.primary : Tw.gray200),
              ),
              // Wrap içinde içeriği kadar geniş olsun (alignment kutuyu tam genişliğe şişirirdi).
              child: Align(
                widthFactor: 1,
                heightFactor: 1,
                child: Text(label, style: tx(13, w: 6, c: primary ? Colors.white : Tw.gray700)),
              ),
            ),
          ),
        );

    final nf = NumberFormat.decimalPattern(i18n.lang);
    return RCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTitle(LucideIcons.droplets, Tw.sky500, i18n.t('mobileCheckin.water.title')),
          const SizedBox(height: 8),
          Text(i18n.t('mobileCheckin.water.help', {'glass': mlPerGlass}), style: tx(12.5, c: Tw.gray600, h: relaxed)),
          const SizedBox(height: 10),
          TextField(
            controller: _waterMl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            style: tx(14, w: 5),
            decoration: inputDecoration(
              hint: i18n.t('mobileCheckin.water.placeholder', {'ml': mlPerGlass * 8}),
              suffixText: 'ml',
              radius: 14,
              borderWidth: 1,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            ),
          ),
          const SizedBox(height: 6),
          Text(i18n.t('mobileCheckin.water.note'), style: tx(12, c: Tw.gray500, h: snug)),
          if (parsed != null && parsed > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Tw.sky50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Tw.sky100),
              ),
              child: Text('${nf.format(parsed)} ml → ${formatGlassesLabel(parsed)}', style: tx(13, w: 6, c: Tw.sky800)),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              smallBtn(i18n.t('mobileCheckin.water.minus', {'ml': mlPerGlass}), () => bump(-mlPerGlass)),
              smallBtn(i18n.t('mobileCheckin.water.plus', {'ml': mlPerGlass}), () => bump(mlPerGlass), primary: true),
              smallBtn(i18n.t('mobileCheckin.water.half', {'ml': mlPerGlass ~/ 2}), () => bump(mlPerGlass ~/ 2)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _makeupCard(I18n i18n, RebiTheme theme) {
    return RCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTitle(LucideIcons.palette, Tw.rose600, i18n.t('mobileCheckin.makeup.title')),
          const SizedBox(height: 8),
          Text(i18n.t('mobileCheckin.makeup.hint'), style: tx(12.5, c: Tw.gray600, h: relaxed)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _tri(i18n.t('common.yes'), _makeupUsedToday == true, theme, () => setState(() => _makeupUsedToday = true))),
              const SizedBox(width: 8),
              Expanded(child: _tri(i18n.t('common.no'), _makeupUsedToday == false, theme, () => setState(() => _makeupUsedToday = false))),
              const SizedBox(width: 8),
              Expanded(
                child: _tri(i18n.t('common.skip'), false, theme, plain: true, () {
                  setState(() {
                    _makeupUsedToday = null;
                    _makeupRemovalToday = 'cleanser';
                  });
                }),
              ),
            ],
          ),
          if (_makeupUsedToday == true) ...[
            const SizedBox(height: 14),
            Text(i18n.t('mobileCheckin.makeup.how'), style: tx(13, w: 6, c: Tw.gray700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final id in const ['cleanser', 'double', 'water', 'wipe', 'none'])
                  ChoiceChipBox(
                    label: i18n.t('mobileCheckin.makeup.$id'),
                    selected: _makeupRemovalToday == id,
                    radius: 12,
                    fontSize: 13,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    activeText: Tw.gray900,
                    inactiveText: Tw.gray600,
                    onTap: () => setState(() => _makeupRemovalToday = id),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Evet / Hayır / Atla — check-in ek soruları. Soru ve açıklama `mobileCheckin.extras.<anahtar>` içindedir.
  Widget _extraTristate(I18n i18n, RebiTheme theme, String key) {
    final value = _concernExtra[key];
    final description = i18n.t('mobileCheckin.extras.$key.d', const {}, '');
    return RCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(i18n.t('mobileCheckin.extras.$key.q'), style: tx(14.5, w: 7, c: Tw.gray800, h: snug)),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(description, style: tx(12.5, c: Tw.gray600, h: relaxed)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _tri(i18n.t('common.yes'), value == true, theme, () => setState(() => _concernExtra[key] = true))),
              const SizedBox(width: 8),
              Expanded(child: _tri(i18n.t('common.no'), value == false, theme, () => setState(() => _concernExtra[key] = false))),
              const SizedBox(width: 8),
              Expanded(child: _tri(i18n.t('common.skip'), false, theme, plain: true, () => setState(() => _concernExtra[key] = null))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _extraHeader(IconData icon, Color color, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 2),
        child: Row(
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: tx(13, w: 7, c: Tw.gray800))),
          ],
        ),
      );

  List<Widget> _concernExtras(I18n i18n, RebiTheme theme) {
    Widget q(String key) => _extraTristate(i18n, theme, key);
    switch (_concern) {
      case 'acne':
        return [
          const SizedBox(height: 16),
          _extraHeader(LucideIcons.hand, Tw.rose600, i18n.t('mobileCheckin.extras.acne')),
          q('picked_skin_today'),
          q('high_glycemic_intake_today'),
          q('heavy_dairy_today'),
        ];
      case 'aging':
      case 'pigmentation':
        return [
          const SizedBox(height: 16),
          _extraHeader(LucideIcons.sun, Tw.amber600, i18n.t('mobileCheckin.extras.$_concern')),
          q('long_sun_exposure_today'),
          q('spf_applied_today'),
        ];
      case 'dryness':
        return [
          const SizedBox(height: 16),
          _extraHeader(LucideIcons.wind, Tw.sky500, i18n.t('mobileCheckin.extras.dryness')),
          q('very_dry_environment_today'),
          q('long_hot_shower_today'),
        ];
      case 'sensitivity':
        return [
          const SizedBox(height: 16),
          _extraHeader(LucideIcons.flower, Tw.violet400, i18n.t('mobileCheckin.extras.sensitivity')),
          q('fragrance_new_product_today'),
          q('long_hot_shower_today'),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 10, left: 2),
            child: Row(
              children: [
                Icon(LucideIcons.flaskConical, size: 17, color: Tw.violet400),
                const SizedBox(width: 8),
                Expanded(child: Text(i18n.t('mobileCheckin.extras.active'), style: tx(13, w: 7, c: Tw.gray800))),
              ],
            ),
          ),
          q('tried_new_active_today'),
        ];
    }
    return const [];
  }
}
