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
import '../ui/tw.dart';
import '../ui/widgets/common.dart';
import 'analyze/analyze_widgets.dart';
import '../ui/brand/glyphs.dart';
import '../ui/brand/palette.dart';

/// Metinler `mobileCheckinForm.feel.<id>` altında: [etiket, açıklama].
const _skinFeelings = ['iyi', 'kuru', 'yagli', 'kirik', 'irritasyon'];

/// Metinler `mobileCheckinForm.stress.<n>` altında.
const _stressLevels = [1, 2, 3, 4, 5];

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
  if (ml <= 0) return I18n.instance.t('mobileCheckinForm.glassesZero');
  final glasses = ml / mlPerGlass;
  final num rounded = (glasses - glasses.round()).abs() < 0.05 ? glasses.round() : (glasses * 10).round() / 10;
  return I18n.instance.t('mobileCheckinForm.glassesApprox', {'n': jsString(rounded)});
}

String get _networkMsg => I18n.instance.t('mobileCheckinForm.networkError');

/// Günlük check-in (web: `pages/CheckIn.jsx`).
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
      if (mounted && isNetworkError(e)) setState(() => _submitError = _networkMsg);
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
          _submitError = d is String ? d : I18n.instance.t('mobileCheckinForm.alreadyDone');
          _alreadyCheckedIn = true;
        });
        return;
      }
      if (!res.ok) {
        setState(() => _submitError = '${formatApiErrorDetail(res.data)} (${res.status})');
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
      if (mounted) setState(() => _submitError = isNetworkError(e) ? _networkMsg : I18n.instance.t('mobileCheckinForm.unexpected'));
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
      return ThemedBackground(
        theme: theme,
        child: Center(child: SizedBox(width: 32, height: 32, child: CircularProgressIndicator(color: Tw.gray400))),
      );
    }

    if (_alreadyCheckedIn) {
      return ThemedPage(
        theme: theme,
        children: [
          Icon(LucideIcons.circleCheckBig, size: 56, color: Tw.teal500),
          const SizedBox(height: 16),
          Text(i18n.t('checkin.alreadyTitle'), textAlign: TextAlign.center, style: heading(24)),
          const SizedBox(height: 8),
          Text(i18n.t('checkin.alreadyDesc'), textAlign: TextAlign.center, style: tx(14, c: Tw.gray500)),
          const SizedBox(height: 24),
          _solidButton(theme.primary, i18n.t('checkin.backToDashboard'), () => context.go('/dashboard')),
        ],
      );
    }

    return _formView(i18n, theme);
  }

  Widget _solidButton(Color color, String label, VoidCallback? onTap, {Widget? leading, Widget? trailing, double vPad = 12}) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: vPad, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leading != null) ...[leading, const SizedBox(width: 8)],
              Flexible(child: Text(label, textAlign: TextAlign.center, style: tx(16, w: 6, c: Colors.white))),
              if (trailing != null) ...[const SizedBox(width: 8), trailing],
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultView(I18n i18n, RebiTheme theme) {
    final result = _result!;
    final changes = (result['changes'] as List?)?.whereType<Map>().toList() ?? const [];
    final today = asRoutine(result['today_routine']);
    final localized = i18n.prefersLocalized;

    return ThemedPage(
      theme: theme,
      children: [
        Center(child: GradientIconBox(icon: LucideIcons.sparkles, from: theme.accent, to: theme.primary, size: 64, iconSize: 32)),
        const SizedBox(height: 16),
        Text(i18n.t('checkin.todayReport'), textAlign: TextAlign.center, style: heading(24)),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: i18n.t('mobileCheckinForm.risk')),
            TextSpan(text: str(result['risk_level']), style: tx(14, w: 6, c: theme.fg)),
            if (result['adaptation_type'] == 'major') TextSpan(text: i18n.t('mobileCheckinForm.majorChanges')),
          ]),
          textAlign: TextAlign.center,
          style: tx(14, c: Tw.gray500),
        ),
        const SizedBox(height: 24),
        if (truthy(result['ai_note'])) ...[
          RCard(
            leftBorderColor: theme.primary,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 2), child: Icon(LucideIcons.sparkles, size: 20, color: theme.primary)),
                const SizedBox(width: 12),
                Expanded(child: Text(str(result['ai_note']), style: tx(14, c: Tw.gray700, h: relaxed))),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (changes.isNotEmpty) ...[
          Row(
            children: [
              Icon(LucideIcons.circleAlert, size: 16, color: Tw.amber500),
              const SizedBox(width: 8),
              Expanded(child: Text(i18n.t('mobileCheckinForm.changes'), style: tx(14, w: 7, c: Tw.gray700))),
            ],
          ),
          const SizedBox(height: 8),
          for (final c in changes) ...[
            RCard(
              padding: const EdgeInsets.all(12),
              borderColor: Tw.amber100,
              color: Color.alphaBlend(Tw.amber50.withValues(alpha: .5), Tw.surface),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(str(c['item']), style: tx(14, w: 5, c: Tw.gray800)),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${str(c['old'])} → '),
                      TextSpan(text: str(c['new']), style: tx(12, w: 6, c: theme.fg)),
                    ]),
                    style: tx(12, c: Tw.gray500),
                  ),
                  const SizedBox(height: 2),
                  Text(str(c['reason']), style: tx(12, c: Tw.gray500)),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
        ],
        if (today.isNotEmpty) ...[
          Text(i18n.t('mobileCheckinForm.todayRoutine'), style: tx(14, w: 7, c: Tw.gray700)),
          const SizedBox(height: 8),
          for (final item in today.take(10)) ...[
            RCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(glyphForEmoji(str(item['icon']), fallback: LucideIcons.dot), size: 16, color: Tw.gray600),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pickAction(item, localized: localized), style: tx(12, w: 6, c: Tw.gray800)),
                        StructuredBadges(item: item),
                        const SizedBox(height: 2),
                        Text(
                          pickDetail(item, localized: localized),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tx(11, c: Tw.gray500),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: theme.primaryLight, borderRadius: BorderRadius.circular(999)),
                    child: Text(str(item['time']), style: tx(9, c: theme.primaryDark)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 14),
        ],
        if (_feedbackStatus == null)
          RCard(
            margin: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(i18n.t('checkin.feedbackTitle'), style: tx(14, w: 6, c: Tw.gray800)),
                const SizedBox(height: 8),
                TextField(
                  controller: _feedbackNote,
                  minLines: 2,
                  maxLines: 2,
                  style: tx(12),
                  decoration: inputDecoration(
                    radius: 12,
                    borderWidth: 1,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    OutlinedButton(
                      onPressed: _feedbackBusy ? null : () => setState(() => _feedbackStatus = 'skipped'),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Tw.gray200),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        minimumSize: Size.zero,
                      ),
                      child: Text(i18n.t('checkin.feedbackSkip'), style: tx(12, w: 5, c: Tw.gray500)),
                    ),
                  ],
                ),
              ],
            ),
          )
        else if (_feedbackStatus == 'sent')
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(i18n.t('checkin.feedbackThanks'), textAlign: TextAlign.center, style: tx(12, c: Tw.emerald700)),
          ),
        _solidButton(
          theme.primary,
          i18n.t('checkin.backToDashboard'),
          _backToDashboard,
          trailing: const Icon(LucideIcons.arrowRight, size: 16, color: Colors.white),
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
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: border, width: 2)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: fg),
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
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: tx(14, w: 7, c: Tw.gray800))),
        ],
      );

  Widget _selectable({required bool selected, required RebiTheme theme, required Widget child, required VoidCallback onTap, EdgeInsets? padding}) {
    return AnimatedScale(
      scale: selected ? 1.05 : 1,
      duration: const Duration(milliseconds: 150),
      child: Material(
        color: selected ? theme.primaryLight : Tw.gray50,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? theme.primary : Colors.transparent, width: 2),
              boxShadow: selected ? const [BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 4))] : null,
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _formView(I18n i18n, RebiTheme theme) {
    const gap = SizedBox(height: 16);
    return ThemedPage(
      theme: theme,
      children: [
        Text(i18n.t('checkin.title'), textAlign: TextAlign.center, style: heading(28)),
        const SizedBox(height: 4),
        Text(i18n.t('checkin.subtitle'), textAlign: TextAlign.center, style: tx(14, c: Tw.gray500)),
        const SizedBox(height: 8),
        Text(
          i18n.t('mobileCheckinForm.intro'),
          textAlign: TextAlign.center,
          style: tx(11, c: Tw.gray500, h: relaxed),
        ),
        const SizedBox(height: 32),
        if (_submitError.isNotEmpty) ...[
          NoticeBox(text: _submitError, bg: Tw.amber50, border: Tw.amber200, fg: Tw.amber900),
          gap,
        ],
        if (_prefilled > 0) ...[
          NoticeBox(
            text: i18n.t('mobileCheckin.prefilled', {'n': _prefilled}),
            bg: theme.primaryLight.withValues(alpha: .35),
            border: theme.primaryLight,
            fg: theme.primaryDark,
            icon: LucideIcons.sparkles,
            fontSize: 12,
          ),
          gap,
        ],
        // S1: Uyku
        RCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cardTitle(LucideIcons.moon, Tw.indigo500, i18n.t('mobileCheckinForm.sleepQ')),
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
                    width: 48,
                    child: Text(i18n.t('mobileCheckinForm.hoursShort', {'n': jsString(_sleepHours)}), textAlign: TextAlign.center, style: tx(18, w: 7, c: Tw.dark ? Tw.indigo400 : Tw.indigo600)),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(i18n.t('mobileCheckinForm.hoursShort', {'n': 3}), style: tx(10, c: Tw.gray500)),
                    Text(i18n.t('mobileCheckinForm.hoursShort', {'n': 7.5}), style: tx(10, c: Tw.gray500)),
                    Text(i18n.t('mobileCheckinForm.hoursShort', {'n': 12}), style: tx(10, c: Tw.gray500)),
                  ],
                ),
              ),
            ],
          ),
        ),
        gap,
        // S2: Stres
        RCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cardTitle(LucideIcons.smilePlus, Tw.purple500, i18n.t('mobileCheckinForm.stressQ')),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final value in _stressLevels) ...[
                    if (value > 1) const SizedBox(width: 8),
                    Expanded(
                      child: _selectable(
                        selected: _stressToday == value,
                        theme: theme,
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                        onTap: () => setState(() => _stressToday = value),
                        child: Column(
                          children: [
                            Icon(stressGlyph(value), size: 22, color: _stressToday == value ? theme.primary : Tw.gray400),
                            const SizedBox(height: 2),
                            Text(i18n.t('mobileCheckinForm.stress.$value'), textAlign: TextAlign.center, style: tx(10, w: _stressToday == value ? 6 : 5, c: _stressToday == value ? theme.primaryDark : Tw.gray600, h: tight)),
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
        // S3: Cilt hissi
        RCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cardTitle(LucideIcons.droplets, theme.primary, i18n.t('mobileCheckinForm.skinQ')),
              const SizedBox(height: 12),
              for (final id in _skinFeelings) ...[
                _selectable(
                  selected: _skinFeeling == id,
                  theme: theme,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  onTap: () => setState(() => _skinFeeling = id),
                  child: Row(
                    children: [
                      Icon(skinFeelingGlyph(id), size: 22, color: _skinFeeling == id ? theme.primary : Tw.gray500),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(i18n.tList('mobileCheckinForm.feel.$id', const ['', ''])[0], style: tx(14, w: 5, c: Tw.gray800)),
                            Text(i18n.tList('mobileCheckinForm.feel.$id', const ['', ''])[1], style: tx(11, c: Tw.gray500)),
                          ],
                        ),
                      ),
                      if (_skinFeeling == id) Icon(LucideIcons.circleCheckBig, size: 20, color: theme.primary),
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
              Text(i18n.t('checkin.symptomsTitle'), style: tx(14, w: 7, c: Tw.gray800)),
              const SizedBox(height: 4),
              Text(i18n.t('checkin.symptomsHint'), style: tx(11, c: Tw.gray500, h: relaxed)),
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
        if (_skinFeeling == 'irritasyon' || _skinFeeling == 'kirik') ...[
          gap,
          RCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(i18n.t('checkin.reactionSeverityTitle'), style: tx(14, w: 7, c: Tw.gray800)),
                const SizedBox(height: 4),
                Text(i18n.t('checkin.reactionSeverityHint'), style: tx(11, c: Tw.gray500)),
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
                  children: [for (final n in ['1', '2', '3']) Text(n, style: tx(10, c: Tw.gray500))],
                ),
              ],
            ),
          ),
        ],
        gap,
        // S4: Rutin uygulandı mı
        RCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cardTitle(LucideIcons.circleCheckBig, Tw.green500, i18n.t('mobileCheckinForm.routineQ')),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _yesNo(i18n.t('mobileCheckinForm.yes'), _appliedRoutine, theme.primary, () => setState(() => _appliedRoutine = true))),
                  const SizedBox(width: 12),
                  Expanded(child: _yesNo(i18n.t('mobileCheckinForm.no'), !_appliedRoutine, Tw.red500, () => setState(() => _appliedRoutine = false))),
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
                TextSpan(text: i18n.t('mobileCheckinForm.concernTitle'), style: TextStyle(fontWeight: FontWeight.w600, color: Tw.slate800)),
                TextSpan(
                  text: i18n.t('mobileCheckinForm.concernBody'),
                ),
              ]),
              style: tx(11, c: Tw.slate600, h: relaxed),
            ),
          ),
        ],
        if (_showWaterExtra) ...[gap, _waterCard(theme)],
        if (_showMakeupExtra) ...[gap, _makeupCard()],
        ..._concernExtras(),
        gap,
        RCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: i18n.t('mobileCheckinForm.notesQ')),
                  TextSpan(text: i18n.t('mobileCheckinForm.optional'), style: tx(14, c: Tw.gray500)),
                ]),
                style: tx(14, w: 7, c: Tw.gray800),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                style: tx(14),
                decoration: inputDecoration(
                  hint: i18n.t('mobileCheckinForm.notesHint'),
                  radius: 12,
                  borderWidth: 1,
                  focusColor: theme.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Opacity(
          opacity: _canSubmit || _loading ? 1 : .5,
          child: _solidButton(
            _canSubmit || _loading ? theme.primary : Tw.gray400,
            _loading ? i18n.t('mobileCheckinForm.analyzing') : i18n.t('checkin.submit'),
            _canSubmit ? _submit : null,
            vPad: 16,
            leading: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                : const Icon(LucideIcons.send, size: 20, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _yesNo(String label, bool selected, Color color, VoidCallback onTap) {
    return Material(
      color: selected ? Tw.fillWithWhiteText(color) : Tw.gray50,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected ? const [BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 4))] : null,
          ),
          child: Text(label, textAlign: TextAlign.center, style: tx(16, w: 5, c: selected ? Colors.white : Tw.gray600)),
        ),
      ),
    );
  }

  Widget _waterCard(RebiTheme theme) {
    final parsed = parseWaterMlInput(_waterMl.text);
    void bump(int delta) {
      final next = ((parsed ?? 0) + delta).clamp(0, 8000);
      _waterMl.text = '$next';
    }

    Widget smallBtn(String label, VoidCallback onTap, {bool primary = false}) => Material(
          color: primary ? theme.primary : Tw.surface,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: primary ? theme.primary : Tw.gray200),
              ),
              child: Text(label, style: tx(12, w: 5, c: primary ? Colors.white : Tw.gray700)),
            ),
          ),
        );

    return RCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTitle(LucideIcons.droplets, Tw.sky500, I18n.instance.t('mobileCheckinForm.waterQ')),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: I18n.instance.t('mobileCheckinForm.waterIntro1')),
              TextSpan(text: I18n.instance.t('mobileCheckinForm.waterUnit'), style: tx(11, w: 7, c: Tw.gray700)),
              TextSpan(text: I18n.instance.t('mobileCheckinForm.waterIntro2')),
              TextSpan(text: I18n.instance.t('mobileCheckinForm.waterGlass', {'ml': mlPerGlass}), style: tx(11, w: 7, c: Tw.gray700)),
              TextSpan(text: I18n.instance.t('mobileCheckinForm.waterIntro3')),
            ]),
            style: tx(11, c: Tw.gray500, h: relaxed),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _waterMl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            style: tx(14, w: 5),
            decoration: inputDecoration(
              hint: I18n.instance.t('mobileCheckinForm.waterHint', {'ml': mlPerGlass * 8}),
              suffixText: 'ml',
              radius: 12,
              borderWidth: 1,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            ),
          ),
          const SizedBox(height: 6),
          Text(I18n.instance.t('mobileCheckinForm.waterNote'), style: tx(10, c: Tw.gray500)),
          if (parsed != null && parsed > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Tw.sky50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Tw.sky100),
              ),
              child: Text(
                '${NumberFormat.decimalPattern(I18n.instance.lang).format(parsed)} ml → ${formatGlassesLabel(parsed)}',
                style: tx(12, w: 6, c: Tw.sky800),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              smallBtn(I18n.instance.t('mobileCheckinForm.glassMinus', {'ml': mlPerGlass}), () => bump(-mlPerGlass)),
              smallBtn(I18n.instance.t('mobileCheckinForm.glassPlus', {'ml': mlPerGlass}), () => bump(mlPerGlass), primary: true),
              smallBtn(I18n.instance.t('mobileCheckinForm.glassHalf'), () => bump(125)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tri(String label, bool selected, VoidCallback onTap, {bool plain = false}) => Material(
        color: selected ? Tw.teal50 : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? Tw.teal500 : Tw.gray200, width: 2),
            ),
            child: Text(label, textAlign: TextAlign.center, style: tx(13, w: 5, c: plain ? Tw.gray600 : Tw.gray900)),
          ),
        ),
      );

  Widget _makeupCard() {
    return RCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTitle(LucideIcons.palette, Tw.rose500, I18n.instance.t('mobileCheckinForm.makeupQ')),
          const SizedBox(height: 8),
          Text(I18n.instance.t('mobileCheckinForm.makeupIntro'),
              style: tx(11, c: Tw.gray500, h: relaxed)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _tri(I18n.instance.t('mobileCheckinForm.yes'), _makeupUsedToday == true, () => setState(() => _makeupUsedToday = true))),
              const SizedBox(width: 8),
              Expanded(child: _tri(I18n.instance.t('mobileCheckinForm.no'), _makeupUsedToday == false, () => setState(() => _makeupUsedToday = false))),
              const SizedBox(width: 8),
              Expanded(
                child: _tri(I18n.instance.t('mobileCheckinForm.skip'), false, plain: true, () {
                  setState(() {
                    _makeupUsedToday = null;
                    _makeupRemovalToday = 'cleanser';
                  });
                }),
              ),
            ],
          ),
          if (_makeupUsedToday == true) ...[
            const SizedBox(height: 12),
            Text(I18n.instance.t('mobileCheckinForm.removalQ'), style: tx(11, w: 5, c: Tw.gray700)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final id in const ['cleanser', 'double', 'water', 'wipe', 'none'])
                  ChoiceChipBox(
                    label: I18n.instance.t('mobileCheckinForm.removal.$id'),
                    selected: _makeupRemovalToday == id,
                    radius: 8,
                    fontSize: 10,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

  /// Evet / Hayır / Atla — check-in ek soruları.
  Widget _extraTristate(String title, String key, {String? description}) {
    final i18n = I18n.instance;
    final value = _concernExtra[key];
    return RCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: tx(14, w: 7, c: Tw.gray800)),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(description, style: tx(11, c: Tw.gray500, h: relaxed)),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _tri(i18n.t('common.yes'), value == true, () => setState(() => _concernExtra[key] = true))),
              const SizedBox(width: 8),
              Expanded(child: _tri(i18n.t('common.no'), value == false, () => setState(() => _concernExtra[key] = false))),
              const SizedBox(width: 8),
              Expanded(child: _tri(i18n.t('common.skip'), false, plain: true, () => setState(() => _concernExtra[key] = null))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _extraHeader(IconData icon, Color color, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: tx(12, w: 7, c: Tw.gray800))),
          ],
        ),
      );

  List<Widget> _concernExtras() {
    switch (_concern) {
      case 'acne':
        return [
          const SizedBox(height: 16),
          _extraHeader(LucideIcons.hand, Tw.rose500, I18n.instance.t('mobileCheckinForm.acne')),
          _extraTristate(I18n.instance.t('mobileCheckinForm.acnePick'), 'picked_skin_today', description: I18n.instance.t('mobileCheckinForm.acnePickD')),
          _extraTristate(I18n.instance.t('mobileCheckinForm.acneSugar'), 'high_glycemic_intake_today', description: I18n.instance.t('mobileCheckinForm.acneSugarD')),
          _extraTristate(I18n.instance.t('mobileCheckinForm.acneDairy'), 'heavy_dairy_today', description: I18n.instance.t('mobileCheckinForm.acneDairyD')),
        ];
      case 'aging':
      case 'pigmentation':
        return [
          const SizedBox(height: 16),
          _extraHeader(LucideIcons.sun, Tw.amber500, _concern == 'aging' ? I18n.instance.t('mobileCheckinForm.aging') : I18n.instance.t('mobileCheckinForm.pigmentation')),
          _extraTristate(I18n.instance.t('mobileCheckinForm.sun'), 'long_sun_exposure_today', description: I18n.instance.t('mobileCheckinForm.sunD')),
          _extraTristate(I18n.instance.t('mobileCheckinForm.spf'), 'spf_applied_today', description: I18n.instance.t('mobileCheckinForm.spfD')),
        ];
      case 'dryness':
        return [
          const SizedBox(height: 16),
          _extraHeader(LucideIcons.wind, Tw.sky500, I18n.instance.t('mobileCheckinForm.dryness')),
          _extraTristate(I18n.instance.t('mobileCheckinForm.dryEnv'), 'very_dry_environment_today'),
          _extraTristate(I18n.instance.t('mobileCheckinForm.shower'), 'long_hot_shower_today', description: I18n.instance.t('mobileCheckinForm.showerD')),
        ];
      case 'sensitivity':
        return [
          const SizedBox(height: 16),
          _extraHeader(LucideIcons.flower, Tw.violet400, I18n.instance.t('mobileCheckinForm.sensitivity')),
          _extraTristate(I18n.instance.t('mobileCheckinForm.fragrance'), 'fragrance_new_product_today'),
          _extraTristate(I18n.instance.t('mobileCheckinForm.shower'), 'long_hot_shower_today'),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Row(
              children: [
                Icon(LucideIcons.flaskConical, size: 16, color: Tw.violet400),
                const SizedBox(width: 8),
                Expanded(child: Text(I18n.instance.t('mobileCheckinForm.active'), style: tx(11, w: 6, c: Tw.gray700))),
              ],
            ),
          ),
          _extraTristate(I18n.instance.t('mobileCheckinForm.newActive'), 'tried_new_active_today', description: I18n.instance.t('mobileCheckinForm.newActiveD')),
        ];
    }
    return const [];
  }
}
