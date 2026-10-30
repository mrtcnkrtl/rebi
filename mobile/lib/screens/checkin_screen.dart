import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/checkin_prefill.dart';
import '../core/checkin_stats.dart';
import '../core/demo_user.dart';
import '../core/i18n.dart';
import '../core/routine_logic.dart';
import '../core/routine_tracking.dart';
import '../core/today_plan.dart';
import '../state/auth_controller.dart';
import '../state/theme_controller.dart';
import '../ui/shell/page_stage.dart';
import '../ui/tw.dart';
import '../ui/widgets/common.dart';
import '../ui/widgets/skeleton.dart';
import 'checkin/checkin_form_cards.dart';
import 'checkin/checkin_parts.dart';
import 'checkin/checkin_report.dart';
import 'checkin/checkin_water.dart';

export 'checkin/checkin_water.dart' show formatGlassesLabel, mlPerGlass, parseWaterMlInput;

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

/// Günlük check-in (web: `pages/CheckIn.jsx`). Bu dosya yalnızca durumu ve akışı yönetir (yükleme, bugünün kayıtlarından ön
/// doldurma, gönderme); kartlar `checkin/` altındadır. Dört durum (yükleniyor, bugün yapıldı, form, rapor) hep sahneyle başlar.
/// Tüm metinler `mobileCheckin.*` / `checkin.*` içindedir.
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

  /// Bugünkü takip kayıtlarından önceden doldurulan cevap sayısı (0 ise bilgi çıkmaz).
  int _prefilled = 0;

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

  bool get _showMakeupExtra => _assessmentMakeup >= 3 || const ['acne', 'pigmentation', 'sensitivity', 'aging'].contains(_concern);

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
      setState(() => _result = res.data);
    } catch (e) {
      if (mounted) {
        setState(() => _submitError = i18n.t(isNetworkError(e) ? 'mobileCheckin.errors.network' : 'mobileCheckin.errors.unexpected'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = context.watch<ThemeController>().theme;

    if (_result != null) return CheckinReport(result: _result!, theme: theme);

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
        CheckinSleepCard(hours: _sleepHours, onChanged: (v) => setState(() => _sleepHours = v)),
        gap,
        CheckinStressCard(level: _stressToday, theme: theme, onChanged: (v) => setState(() => _stressToday = v)),
        gap,
        CheckinSkinCard(selected: _skinFeeling, theme: theme, onChanged: (id) => setState(() => _skinFeeling = id)),
        gap,
        CheckinSymptomsCard(
          tags: _symptomTags,
          onToggle: (id) => setState(() => _symptomTags.contains(id) ? _symptomTags.remove(id) : _symptomTags.add(id)),
        ),
        if (skinSevere) ...[
          gap,
          CheckinReactionSeverityCard(severity: _reactionSeverity, onChanged: (v) => setState(() => _reactionSeverity = v)),
        ],
        gap,
        CheckinRoutineAppliedCard(applied: _appliedRoutine, theme: theme, onChanged: (v) => setState(() => _appliedRoutine = v)),
        if (_showConcernIntro) ...[gap, const CheckinConcernIntroCard()],
        if (_showWaterExtra) ...[gap, CheckinWaterCard(controller: _waterMl, theme: theme)],
        if (_showMakeupExtra) ...[
          gap,
          CheckinMakeupCard(
            used: _makeupUsedToday,
            removal: _makeupRemovalToday,
            theme: theme,
            onUsed: (v) => setState(() {
              _makeupUsedToday = v;
              // "Atla": yöntem varsayılana döner (sunucuya gitmez).
              if (v == null) _makeupRemovalToday = 'cleanser';
            }),
            onRemoval: (id) => setState(() => _makeupRemovalToday = id),
          ),
        ],
        ..._concernExtras(i18n, theme),
        gap,
        CheckinNotesCard(controller: _notes, theme: theme),
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

  /// Analizdeki ana soruna göre ek sorular (akne, yaşlanma/leke, kuruluk, hassasiyet) ve başlıkları.
  List<Widget> _concernExtras(I18n i18n, RebiTheme theme) {
    Widget header(IconData icon, Color color, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 2),
          child: Row(
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: tx(13, w: 7, c: Tw.gray800))),
            ],
          ),
        );
    Widget q(String key) =>
        CheckinExtraQuestion(questionKey: key, value: _concernExtra[key], theme: theme, onChanged: (v) => setState(() => _concernExtra[key] = v));

    switch (_concern) {
      case 'acne':
        return [
          const SizedBox(height: 16),
          header(LucideIcons.hand, Tw.rose600, i18n.t('mobileCheckin.extras.acne')),
          q('picked_skin_today'),
          q('high_glycemic_intake_today'),
          q('heavy_dairy_today'),
        ];
      case 'aging':
      case 'pigmentation':
        return [
          const SizedBox(height: 16),
          header(LucideIcons.sun, Tw.amber600, i18n.t('mobileCheckin.extras.$_concern')),
          q('long_sun_exposure_today'),
          q('spf_applied_today'),
        ];
      case 'dryness':
        return [
          const SizedBox(height: 16),
          header(LucideIcons.wind, Tw.sky500, i18n.t('mobileCheckin.extras.dryness')),
          q('very_dry_environment_today'),
          q('long_hot_shower_today'),
        ];
      case 'sensitivity':
        return [
          const SizedBox(height: 16),
          header(LucideIcons.flower, Tw.violet400, i18n.t('mobileCheckin.extras.sensitivity')),
          q('fragrance_new_product_today'),
          q('long_hot_shower_today'),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: header(LucideIcons.flaskConical, Tw.violet400, i18n.t('mobileCheckin.extras.active')),
          ),
          q('tried_new_active_today'),
        ];
    }
    return const [];
  }
}
