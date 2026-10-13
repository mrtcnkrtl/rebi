import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/demo_user.dart';
import '../core/i18n.dart';
import '../core/routine_logic.dart';
import '../core/routine_tracking.dart';
import '../core/today_plan.dart';
import '../state/auth_controller.dart';
import '../state/home_sync_controller.dart';
import '../state/notifications_controller.dart';
import '../state/outbox_sync_controller.dart';
import '../state/theme_controller.dart';
import '../state/today_plan_controller.dart';
import '../ui/components/notification_widgets.dart';
import '../ui/components/photo_picker.dart';
import '../ui/tw.dart';
import '../ui/widgets/common.dart';
import 'dashboard_today.dart';

/// Ana panel (web: `pages/Dashboard.jsx`).
/// `nav`: webdeki `location.state` — analiz / check-in sonrası taşınan rutin ve meta.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.nav});

  final Map<String, dynamic>? nav;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Map<String, dynamic> _nav = widget.nav ?? const {};
  List<RoutineItem>? _fetchedRoutine;
  bool _fetchingDbRoutine = false;
  bool _showPlanExpanded = false;
  String _quickLogMsg = '';
  Timer? _quickLogTimer;
  bool _translating = false;
  List<RoutineItem>? _translatedFor;
  late final AuthController _auth = context.read<AuthController>();
  late final HomeSyncController _sync = context.read<HomeSyncController>();
  late final NotificationsController _notifications = context.read<NotificationsController>();
  TodayPlanController? _today;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _uid = _auth.user?.id;
    _auth.addListener(_onAuth);
    _fetchDbRoutine();
    _syncNavSnapshot();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen old) {
    super.didUpdateWidget(old);
    if (!identical(old.nav, widget.nav)) {
      _nav = widget.nav ?? const {};
      _syncNavSnapshot();
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    _quickLogTimer?.cancel();
    _today?.dispose();
    super.dispose();
  }

  void _onAuth() {
    final next = _auth.user?.id;
    if (next == _uid) return;
    _uid = next;
    _fetchedRoutine = null;
    _today?.dispose();
    _today = null;
    _fetchDbRoutine();
  }

  /// Açılış paketi (`/me/snapshot`) ile yürürlükteki rutini alır, bugünün planını (`/today/plan`) yükler.
  /// Panel her açıldığında paket tazelenir: yeni analiz ya da check-in rutini değiştirmiş olabilir.
  /// Paket alınamazsa (ağ yok, sunucu hatası) rutin doğrudan Supabase'den, o da olmazsa yerel kopyadan okunur.
  Future<void> _fetchDbRoutine() async {
    final uid = _uid;
    if (uid == null || uid == demoUserId) return;
    final today = TodayPlanController(userId: uid);
    _today?.dispose();
    _today = today;
    // Plan değiştikçe (yüklenince, bir iş kaydedilince) hatırlatma bildirimleri yeniden kurulur.
    today.addListener(() => _notifications.syncReminders(today.plan));
    setState(() => _fetchingDbRoutine = true);
    try {
      final snap = await _sync.refresh();
      if (!mounted || uid != _uid) return;
      if (snap == null) {
        await _fetchRoutineFromSupabase(uid);
      } else if (snap.routine.isNotEmpty) {
        setState(() => _fetchedRoutine = snap.routine);
      }
      if (mounted && uid == _uid) unawaited(today.load(useLocation: snap?.consent.locationAllowed == true));
    } finally {
      if (mounted) setState(() => _fetchingDbRoutine = false);
    }
  }

  Future<void> _fetchRoutineFromSupabase(String uid) async {
    final client = supabase;
    if (client == null) return;
    try {
      final data = await client
          .from('routines')
          .select('active_routine')
          .eq('user_id', uid)
          .eq('is_active', true)
          .maybeSingle();
      final list = asRoutine(data?['active_routine']);
      if (mounted && uid == _uid && list.isNotEmpty) setState(() => _fetchedRoutine = list);
    } catch (_) {
      /* çevrimdışı: yerel snapshot gösterilir */
    }
  }

  /// UI İngilizce ama rutin satırları Türkçe saklıysa backend çeviri ucuyla bir kez zenginleştir.
  void _maybeTranslate(bool prefersLocalized) {
    final fetched = _fetchedRoutine;
    final uid = _uid;
    if (!prefersLocalized || uid == null || fetched == null || fetched.isEmpty || _translating) return;
    if (identical(_translatedFor, fetched)) return;
    final anyMissing = fetched.any((it) => !(truthy(it['action_localized']) || truthy(it['detail_localized'])));
    if (!anyMissing) return;
    _translating = true;
    _translatedFor = fetched;
    () async {
      try {
        final res = await apiPost('/routine/translate_items', {'user_id': uid, 'routine_items': fetched});
        final items = asRoutine(res.data['routine_items']);
        if (mounted && identical(_fetchedRoutine, fetched) && items.isNotEmpty) {
          setState(() {
            _fetchedRoutine = items;
            _translatedFor = items;
          });
        }
      } catch (_) {
        /* çeviri gelmezse Türkçe alanlar gösterilir */
      } finally {
        _translating = false;
      }
    }();
  }

  /// Kabul edilmiş rutinde, gezinmeyle gelen yeni rutin snapshot'a yazılır.
  void _syncNavSnapshot() {
    final uid = _uid;
    if (uid == null || !isRoutineTrackingAccepted(uid)) return;
    final st = _nav;
    final routine = st['routine'];
    if (routine is! List || routine.isEmpty) return;
    saveRoutineSnapshot(uid, {
      ...?getRoutineSnapshot(uid),
      'routine': routine,
      if (st['checkinResult'] != null) 'checkinResult': st['checkinResult'],
      if (st['weather'] != null) 'weather': st['weather'],
      if (st['activePlan'] is List) 'activePlan': st['activePlan'],
    });
  }

  Map<String, dynamic> _merged(I18n i18n, bool accepted) {
    final uid = _uid;
    final snap = uid != null ? getRoutineSnapshot(uid) : null;
    final st = _nav;
    List<RoutineItem> routine = const [];
    final stRoutine = asRoutine(st['routine']);
    final snapRoutine = asRoutine(snap?['routine']);
    final fetched = _fetchedRoutine ?? const [];
    if (stRoutine.isNotEmpty) {
      routine = stRoutine;
    } else if (accepted && fetched.isNotEmpty) {
      routine = fetched;
    } else if (snapRoutine.isNotEmpty) {
      routine = snapRoutine;
    } else if (fetched.isNotEmpty) {
      routine = fetched;
    }
    Object? pick(String key) => st[key] ?? snap?[key];
    return {
      'routine': routine,
      'weather': pick('weather'),
      'userName': st['userName'] ??
          snap?['userName'] ??
          _auth.user?.userMetadata?['full_name'] ??
          i18n.t('common.user', const {}, 'User'),
      'photoUrl': pick('photoUrl'),
      'flowDebug': pick('flowDebug'),
      'checkinResult': pick('checkinResult'),
      'safetyAbsoluteRules': pick('safetyAbsoluteRules'),
      'ruleEnforcementReport': pick('ruleEnforcementReport'),
      'concern': pick('concern'),
      'assessmentId': pick('assessmentId'),
      'activePlan': st['activePlan'] is List ? st['activePlan'] : (snap?['activePlan'] is List ? snap!['activePlan'] : const []),
    };
  }

  Future<void> _acceptRoutine(Map<String, dynamic> merged) async {
    final uid = _uid;
    if (uid == null) return;
    await acceptRoutineTracking(uid, {
      'routine': merged['routine'],
      'weather': merged['weather'],
      'userName': merged['userName'],
      'photoUrl': merged['photoUrl'],
      'flowDebug': merged['flowDebug'],
      'safetyAbsoluteRules': merged['safetyAbsoluteRules'],
      'ruleEnforcementReport': merged['ruleEnforcementReport'],
      'concern': merged['concern'],
      'assessmentId': merged['assessmentId'],
      'checkinResult': merged['checkinResult'],
      'activePlan': merged['activePlan'] ?? const [],
    });
    if (!mounted) return;
    setState(() {
      _showPlanExpanded = false;
      _nav = const {};
    });
  }

  Future<void> _quickLog(String kind, I18n i18n) async {
    if (_uid == null) return;
    final (String type, Map<String, dynamic> payload) = switch (kind) {
      'spf' => ('spf_refresh', {'n': 1}),
      'morning' => ('routine_completed_block', {'morning': true}),
      'makeup' => ('makeup', {'used': true}),
      'makeupRemoved' => ('makeup', {'removed': true, 'method': 'double'}),
      'junk' => ('nutrition', {'junk_food': true}),
      _ => ('routine_completed_block', {'evening': true}),
    };
    final outcome = await _logToday(type, payload);
    if (outcome.saved) _flashLogged(i18n, queued: outcome == LogOutcome.queued);
  }

  /// Olayı sunucuya yazar ve "bugün" planını tazeler; ulaşılamazsa cihazda bekletir. Demo kullanıcıda yazılmaz.
  Future<LogOutcome> _logToday(String type, Map<String, dynamic> payload) async =>
      await _today?.log(type, payload) ?? LogOutcome.failed;

  void _flashLogged(I18n i18n, {bool queued = false}) {
    if (!mounted) return;
    setState(() => _quickLogMsg = i18n.t(queued ? 'mobileToday.queuedHint' : 'dashboard.quickLogged'));
    _quickLogTimer?.cancel();
    _quickLogTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _quickLogMsg = '');
    });
  }

  /// Hatırlatıcı kartındaki eylem: ekrana git ya da olayı kaydet.
  Future<void> _runReminderAction(ReminderAction action) async {
    final route = action.route;
    if (route != null) {
      context.go(route);
      return;
    }
    final type = action.type;
    if (type == null) return;
    final outcome = await _logToday(type, action.payload);
    if (outcome.saved) _flashLogged(I18n.instance, queued: outcome == LogOutcome.queued);
  }

  /// "Ürün bitti": `product_finished` olayı (günde en fazla 20 kayıt, sunucu sınırlar).
  Future<bool> _logProductFinished(RoutineItem item) async {
    final name = str(item['action']).trim();
    final outcome = await _logToday('product_finished', {
      'product': name.length > 120 ? name.substring(0, 120) : name,
      'step_order': stepOrder(item).round(),
    });
    return outcome.saved;
  }

  /// "Bugün" planı değişince yeniden çizilir; denetleyici yoksa (demo) plansız çizer.
  Widget _withPlan(Widget Function(TodayPlan? plan) build) {
    final controller = _today;
    if (controller == null) return build(null);
    return ListenableBuilder(listenable: controller, builder: (_, _) => build(controller.plan));
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = context.watch<ThemeController>().theme;
    context.watch<AuthController>();
    final uid = _uid;
    final localized = i18n.prefersLocalized;
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeTranslate(localized));

    final accepted = uid != null && isRoutineTrackingAccepted(uid);
    final merged = _merged(i18n, accepted);
    final routine = merged['routine'] as List<RoutineItem>;
    final weekDays = i18n.tList('dashboard.weekDays', const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']);
    final dateLine = DateFormat.yMMMMEEEEd(i18n.lang).format(DateTime.now());
    final userName = str(merged['userName']);

    if (routine.isEmpty) {
      if (uid != null && uid != demoUserId && _fetchingDbRoutine) {
        return ThemedBackground(theme: theme, child: const Center(child: RingSpinner()));
      }
      return _emptyState(i18n, theme, userName);
    }

    final view = RoutineView(routine);
    final trackingMode = accepted && !_showPlanExpanded;
    final ctx = _Ctx(i18n: i18n, theme: theme, localized: localized, weekDays: weekDays);

    if (trackingMode) return _tracking(ctx, view, merged, dateLine, userName);
    return _fullPlan(ctx, view, merged, dateLine, userName, accepted);
  }

  Widget _flashNeedAccept(I18n i18n) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: RCard(
          padding: const EdgeInsets.all(12),
          borderColor: Tw.amber200,
          color: Color.alphaBlend(Tw.amber50.withValues(alpha: .8), Colors.white),
          child: Text(i18n.t('dashboard.acceptHint'), style: tx(14, c: Tw.amber900)),
        ),
      );

  Widget _emptyState(I18n i18n, RebiTheme theme, String userName) {
    return ThemedPage(
      theme: theme,
      padding: const EdgeInsets.fromLTRB(16, 64, 16, 64),
      children: [
        if (_nav['flashNeedAccept'] == true) _flashNeedAccept(i18n),
        Center(child: GradientIconBox(icon: LucideIcons.leaf, from: theme.accent, to: theme.primary, size: 80, iconSize: 40, radius: 24)),
        const SizedBox(height: 24),
        Text(i18n.t('dashboard.noAnalyzeTitle', {'name': userName}), textAlign: TextAlign.center, style: tx(24, w: 7)),
        const SizedBox(height: 8),
        Text(i18n.t('dashboard.noAnalyzeDesc'), textAlign: TextAlign.center, style: tx(16, c: Tw.gray500)),
        const SizedBox(height: 24),
        PrimaryButton(
          onPressed: () => context.go('/dashboard/analyze'),
          color: theme.primary,
          icon: LucideIcons.circlePlus,
          label: i18n.t('dashboard.startAnalyze'),
          trailingIcon: LucideIcons.arrowRight,
          fontSize: 18,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        ),
        const SizedBox(height: 12),
        SecondaryButton(
          onPressed: () => context.go('/dashboard/chat'),
          borderColor: theme.primaryLight,
          textColor: theme.primary,
          icon: LucideIcons.messageCircle,
          label: i18n.t('dashboard.chatWithAi'),
        ),
      ],
    );
  }

  Widget _checkinCard(_Ctx c, {required bool big, bool done = false}) {
    final theme = c.theme;
    return RCard(
      onTap: () => context.go('/dashboard/checkin'),
      borderColor: theme.primaryLight,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [theme.primaryLight.withValues(alpha: .25), Colors.white],
      ),
      child: Row(
        children: [
          Container(
            width: big ? 48 : 40,
            height: big ? 48 : 40,
            decoration: BoxDecoration(color: theme.primary, borderRadius: BorderRadius.circular(12)),
            child: Icon(done ? LucideIcons.circleCheck : LucideIcons.clipboardCheck, size: big ? 24 : 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.i18n.t('dashboard.dailyCheckinTitle'), style: tx(big ? 16 : 14, w: 7, c: Tw.gray800)),
                Text(
                    done
                        ? c.i18n.t('mobileToday.checkinDoneToday')
                        : big
                            ? c.i18n.t('dashboard.dailyCheckinSubtitle')
                            : c.i18n.t('dashboard.feelsTodayHint'),
                    style: tx(12, c: Tw.gray500)),
              ],
            ),
          ),
          const Icon(LucideIcons.arrowRight, size: 20, color: Tw.gray400),
        ],
      ),
    );
  }

  Widget _aiNoteCard(_Ctx c, Map checkinResult, {bool showChanges = false}) {
    final changes = checkinResult['changes'];
    return RCard(
      leftBorderColor: c.theme.primary,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(LucideIcons.sparkles, size: 20, color: c.theme.primary)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.i18n.t('dashboard.lastCheckinNoteTitle'), style: tx(12, w: 7, c: Tw.gray700)),
                const SizedBox(height: 4),
                Text(str(checkinResult['ai_note']), style: tx(14, c: Tw.gray600, h: relaxed)),
                if (showChanges && changes is List && changes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(LucideIcons.info, size: 14, color: Tw.amber600),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(c.i18n.t('checkin.changesCount', {'count': changes.length}), style: tx(12, c: Tw.amber600)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayHeader(RebiTheme theme, String text, {IconData icon = LucideIcons.calendarDays, double alpha = .07}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.primary.withValues(alpha: alpha),
          border: const Border(bottom: BorderSide(color: Tw.gray100)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: theme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: tx(14, w: 7, c: Tw.gray800))),
          ],
        ),
      );

  Widget _block(
    String label,
    List<RoutineItem> items,
    _Ctx c, {
    required bool numbered,
    required String keyPrefix,
    Future<bool> Function(RoutineItem item)? onFinished,
  }) {
    final space = label.indexOf(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: label.substring(0, space), style: emojiStyle(12)),
            TextSpan(text: label.substring(space)),
          ]),
          style: tx(12, w: 6, c: Tw.gray600),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _ProductStep(
            key: ValueKey('$keyPrefix-$i'),
            item: items[i],
            ctx: c,
            step: numbered ? i + 1 : null,
            onFinished: onFinished,
          ),
        ],
      ],
    );
  }

  List<Widget> _spaced(List<Widget> items, double gap) => [
        for (var i = 0; i < items.length; i++) ...[if (i > 0) SizedBox(height: gap), items[i]],
      ];

  Widget _weatherMini(_Ctx c, Map weather) => RCard(
        padding: const EdgeInsets.all(12),
        borderColor: Tw.blue100,
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Tw.blue50, Tw.cyan50]),
        child: Row(
          children: [
            const Icon(LucideIcons.cloudSun, size: 16, color: Tw.blue500),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${c.i18n.t('dashboard.weatherTitle')} — ${str(weather['temperature'])}°C · UV ${str(weather['uv_index'])}',
                style: tx(12, w: 7, c: Tw.gray800),
              ),
            ),
          ],
        ),
      );

  Widget _tracking(_Ctx c, RoutineView v, Map<String, dynamic> merged, String dateLine, String userName) {
    final i18n = c.i18n;
    final theme = c.theme;
    final todayIdx = getTurkeyWeekdayIndex();
    final today = v.routineByDay[todayIdx] ?? const DayPlan([], []);
    final checkinResult = merged['checkinResult'];
    final weather = merged['weather'];
    final morning = i18n.t('dashboard.morning');
    final evening = i18n.t('dashboard.evening');
    final lifestyle = i18n.t('dashboard.lifestyleSuffix');

    final blocks = <Widget>[
      if (today.morning.isNotEmpty)
        _block('☀️ $morning', today.morning, c, numbered: true, keyPrefix: 't-m', onFinished: _logProductFinished),
      if (v.wellnessMorningItems.isNotEmpty)
        _block('☀️ $morning — $lifestyle', v.wellnessMorningItems, c, numbered: false, keyPrefix: 't-wm'),
      if (today.evening.isNotEmpty)
        _block('🌙 $evening', today.evening, c, numbered: true, keyPrefix: 't-e', onFinished: _logProductFinished),
      if (v.wellnessEveningItems.isNotEmpty)
        _block('🌙 $evening — $lifestyle', v.wellnessEveningItems, c, numbered: false, keyPrefix: 't-we'),
      if (v.dailyLifestyleItems.isNotEmpty)
        _block('📌 ${i18n.t('dashboard.allDay')}', v.dailyLifestyleItems, c, numbered: false, keyPrefix: 't-d'),
    ];

    Widget quickBtn(String label, Color border, Color bg, Color fg, String kind, {IconData? icon}) => Material(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _quickLog(kind, i18n),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
                  Flexible(child: Text(label, style: tx(11, w: 6, c: fg))),
                ],
              ),
            ),
          ),
        );

    return ThemedPage(
      theme: theme,
      maxWidth: 672,
      children: [
        Text(i18n.t('dashboard.trackingTitle'), style: tx(24, w: 7)),
        const SizedBox(height: 4),
        Text(dateLine, style: tx(14, c: Tw.gray500)),
        const SizedBox(height: 8),
        Text(i18n.t('dashboard.helloToday', {'name': userName}), style: tx(14, c: Tw.gray600)),
        const AiDisclaimer(padding: EdgeInsets.only(top: 8)),
        const SizedBox(height: 24),
        _withPlan((plan) => _checkinCard(c, big: true, done: plan?.checkinDone == true)),
        const SizedBox(height: 16),
        NotificationPromptCard(theme: theme),
        if (_today case final today?) ...[
          TodayPanel(
            controller: today,
            theme: theme,
            onAction: _runReminderAction,
            onRetryPending: () => context.read<OutboxSyncController>().flushNow(),
          ),
          const SizedBox(height: 16),
        ],
        RCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(i18n.t('dashboard.quickLogTitle'), style: tx(12, w: 7, c: Tw.gray800)),
              const SizedBox(height: 2),
              Text(i18n.t('dashboard.quickLogHint'), style: tx(10, c: Tw.gray500, h: relaxed)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  quickBtn(i18n.t('dashboard.quickSpf'), Tw.amber200, Tw.amber50, Tw.amber900, 'spf', icon: LucideIcons.sun),
                  quickBtn(i18n.t('dashboard.quickMorning'), Tw.gray200, Colors.white, Tw.gray700, 'morning'),
                  quickBtn(i18n.t('dashboard.quickEvening'), Tw.gray200, Colors.white, Tw.gray700, 'evening'),
                  quickBtn(i18n.t('mobileToday.quick.makeup'), Tw.gray200, Colors.white, Tw.gray700, 'makeup'),
                  quickBtn(i18n.t('mobileToday.quick.makeupRemoved'), Tw.gray200, Colors.white, Tw.gray700, 'makeupRemoved'),
                  quickBtn(i18n.t('mobileToday.quick.junk'), Tw.gray200, Colors.white, Tw.gray700, 'junk'),
                ],
              ),
              if (_quickLogMsg.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_quickLogMsg, style: tx(10, w: 5, c: Tw.emerald700)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (checkinResult is Map && truthy(checkinResult['ai_note'])) ...[
          _aiNoteCard(c, checkinResult),
          const SizedBox(height: 20),
        ],
        _DailyBalanceCard(item: v.dailyBalanceItem, flowDebug: merged['flowDebug'], ctx: c),
        RCard(
          padding: EdgeInsets.zero,
          clip: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _dayHeader(theme, '${i18n.t('dashboard.todayTitle')} — ${c.weekDays[todayIdx]}'),
              Padding(
                padding: const EdgeInsets.all(12),
                child: blocks.isEmpty
                    ? Text(i18n.t('dashboard.noPlannedSteps'), style: tx(14, c: Tw.gray500))
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced(blocks, 16)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (v.weeklyItems.isNotEmpty) ...[
          RCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(i18n.t('dashboard.weeklyTitle'), style: tx(12, w: 7, c: Tw.gray800)),
                const SizedBox(height: 8),
                for (final w in v.weeklyItems.take(4)) ...[
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: friendlyRoutineTitle(pickAction(w.item, localized: c.localized), c.fallbackStepTitle),
                        style: tx(11, w: 6, c: Tw.gray800),
                      ),
                      TextSpan(
                        text: ' · ${w.displayDays.isNotEmpty ? w.displayDays.map((i) => c.weekDays[i]).join(', ') : '—'}',
                      ),
                    ]),
                    style: tx(11, c: Tw.gray600),
                  ),
                  StructuredBadges(item: w.item),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        _withPlan((plan) {
          if (plan != null) {
            return Padding(padding: const EdgeInsets.only(bottom: 20), child: EnvironmentAdviceCard(plan: plan, theme: theme));
          }
          if (weather is Map && truthy(weather['temperature'])) {
            return Padding(padding: const EdgeInsets.only(bottom: 20), child: _weatherMini(c, weather));
          }
          return const SizedBox.shrink();
        }),
        SecondaryButton(
          onPressed: () => setState(() => _showPlanExpanded = true),
          borderColor: theme.primaryLight,
          textColor: theme.primary,
          label: 'Tüm haftayı, detayları ve yaşam önerilerini göster',
        ),
        const SizedBox(height: 12),
        SecondaryButton(
          onPressed: () => context.push('/dashboard/history'),
          borderColor: theme.primaryLight,
          textColor: theme.primary,
          icon: LucideIcons.calendarDays,
          fontSize: 14,
          label: i18n.t('mobileHistory.open'),
        ),
        const SizedBox(height: 8),
        SecondaryButton(
          onPressed: () => context.push('/dashboard/analyze?photo=1'),
          borderColor: theme.primaryLight,
          textColor: theme.primary,
          icon: LucideIcons.circlePlus,
          fontSize: 14,
          label: 'Fotoğraf yükle (hızlı)',
        ),
        const SizedBox(height: 8),
        SecondaryButton(
          onPressed: () => context.go('/dashboard/analyze'),
          borderColor: theme.primaryLight,
          textColor: theme.primary,
          icon: LucideIcons.circlePlus,
          label: 'Yeni analiz',
        ),
      ],
    );
  }

  Widget _riskPill(String level, String text) {
    final (bg, fg) = switch (level) {
      'crisis' => (Tw.red100, Tw.red700),
      'high' => (Tw.orange100, Tw.orange700),
      'moderate' => (Tw.yellow100, Tw.yellow700),
      _ => (Tw.green100, Tw.green700),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: tx(10, c: fg)),
    );
  }

  Widget _fullPlan(_Ctx c, RoutineView v, Map<String, dynamic> merged, String dateLine, String userName, bool accepted) {
    final i18n = c.i18n;
    final theme = c.theme;
    final flowDebug = merged['flowDebug'];
    final checkinResult = merged['checkinResult'];
    final weather = merged['weather'];
    final activePlan = (merged['activePlan'] as List?)?.whereType<Map>().toList() ?? const [];
    final photoUrl = merged['photoUrl'];
    final showDailyCheckIn = accepted;
    final showAcceptBar = !accepted;
    final morning = i18n.t('dashboard.morning');
    final evening = i18n.t('dashboard.evening');

    Widget chip(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: theme.primaryLight, borderRadius: BorderRadius.circular(999)),
          child: Text(text, style: tx(10, c: theme.primaryDark)),
        );

    final children = <Widget>[
      if (_nav['flashNeedAccept'] == true) _flashNeedAccept(i18n),
      Text.rich(
        TextSpan(children: [
          TextSpan(text: '${i18n.t('dashboard.myRoutineTitle', {'name': userName})} '),
          WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(LucideIcons.sparkles, size: 20, color: theme.accent)),
        ]),
        style: tx(24, w: 7),
      ),
      const SizedBox(height: 4),
      Text(dateLine, style: tx(14, c: Tw.gray500)),
      const AiDisclaimer(padding: EdgeInsets.only(top: 8)),
      if (accepted && _showPlanExpanded)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextLink(
              i18n.t('dashboard.backToTracking'),
              onTap: () => setState(() => _showPlanExpanded = false),
              style: tx(14, w: 6, c: theme.primary),
            ),
          ),
        ),
      if (showAcceptBar)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: RCard(
            padding: const EdgeInsets.all(16),
            borderColor: theme.primaryLight,
            borderWidth: 2,
            color: Color.alphaBlend(theme.primaryLight.withValues(alpha: .09), Colors.white),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(i18n.t('dashboard.acceptBanner'), style: tx(14, w: 5, c: Tw.gray800)),
                const SizedBox(height: 12),
                Material(
                  color: theme.primary,
                  borderRadius: BorderRadius.circular(12),
                  elevation: 3,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _acceptRoutine(merged),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(i18n.t('dashboard.acceptCta'), textAlign: TextAlign.center, style: tx(16, w: 6, c: Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      if (flowDebug is Map)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              chip(str(flowDebug['age_group'])),
              chip(str(flowDebug['skin_type'])),
              chip(str(flowDebug['severity'])),
              if (flowDebug['risk_info'] is Map)
                Builder(builder: (_) {
                  final risk = flowDebug['risk_info'] as Map;
                  final level = truthy(risk['level']) ? str(risk['level']) : 'normal';
                  final label = c.localized
                      ? i18n.t('dashboard.riskLevels.$level')
                      : (truthy(risk['label']) ? str(risk['label']) : str(risk['level']));
                  return _riskPill(str(risk['level']), '${i18n.t('dashboard.riskPrefix')}: $label');
                }),
            ],
          ),
        ),
      const SizedBox(height: 24),
      if (v.eveningMorningHints.isNotEmpty) ...[
        RCard(
          borderColor: Tw.amber200,
          color: Color.alphaBlend(Tw.amber50.withValues(alpha: .6), Colors.white),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(padding: EdgeInsets.only(top: 2), child: Icon(LucideIcons.triangleAlert, size: 20, color: Tw.amber600)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i18n.t('dashboard.morningUsageTitle'), style: tx(14, w: 7, c: Tw.amber950)),
                    const SizedBox(height: 8),
                    for (final line in v.eveningMorningHints)
                      Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('•  $line', style: tx(14, c: Tw.gray800))),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
      _DailyBalanceCard(item: v.dailyBalanceItem, flowDebug: flowDebug, ctx: c),
      if (v.routineIngredientsList.isNotEmpty) ...[
        _SectionHeader(icon: '🧪', title: i18n.t('dashboard.productListTitle'), subtitle: i18n.t('dashboard.productListSubtitle'), color: theme.primary, topGap: 8),
        RCard(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in v.routineIngredientsList)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.primary.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.primaryLight),
                  ),
                  child: Text(name, style: tx(12, w: 5, c: theme.primaryDark)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
      if (showDailyCheckIn) ...[_checkinCard(c, big: false), const SizedBox(height: 20)],
      if (showDailyCheckIn && checkinResult is Map && truthy(checkinResult['ai_note'])) ...[
        _aiNoteCard(c, checkinResult, showChanges: true),
        const SizedBox(height: 20),
      ],
      if (weather is Map && truthy(weather['temperature'])) ...[_weatherCard(i18n, weather), const SizedBox(height: 20)],
      if (activePlan.isNotEmpty) ...[_activePlanCard(c, activePlan), const SizedBox(height: 16)],
      _SectionHeader(icon: '🧴', title: i18n.t('dashboard.routineByDayTitle'), subtitle: i18n.t('dashboard.routineByDaySubtitle'), color: theme.primary),
      _howToChoose(c),
      const SizedBox(height: 16),
      if (v.dailyLifestyleItems.isNotEmpty) ...[
        RCard(
          padding: EdgeInsets.zero,
          dashed: true,
          borderWidth: 2,
          borderColor: Tw.teal100,
          clip: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _dayHeader(theme, i18n.t('dashboard.everyDayAllDayTitle'), icon: LucideIcons.leaf, alpha: .06),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(i18n.t('dashboard.everyDayAllDayHint'), style: tx(10, c: Tw.gray500)),
                    const SizedBox(height: 8),
                    ..._spaced([
                      for (var i = 0; i < v.dailyLifestyleItems.length; i++)
                        _ProductStep(key: ValueKey('all-days-$i'), item: v.dailyLifestyleItems[i], ctx: c),
                    ], 6),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
      for (var d = 0; d < c.weekDays.length && d < 7; d++) ..._dayCard(c, v, d, morning, evening),
      if (v.weeklyItems.isNotEmpty) ..._weeklySection(c, v),
      _SectionHeader(icon: '🌿', title: i18n.t('dashboard.lifestyleSupportsTitle'), subtitle: i18n.t('dashboard.lifestyleSupportsSubtitle'), color: Tw.green600),
      if (v.nutritionItems.isNotEmpty) ...[
        Row(children: [
          const Icon(LucideIcons.apple, size: 16, color: Tw.green600),
          const SizedBox(width: 8),
          Expanded(child: Text(i18n.t('dashboard.nutritionTitle'), style: tx(14, w: 7, c: Tw.gray700))),
        ]),
        const SizedBox(height: 8),
        ..._spaced([for (var i = 0; i < v.nutritionItems.length; i++) _LifestyleCard(key: ValueKey('n-$i'), item: v.nutritionItems[i], ctx: c)], 8),
        const SizedBox(height: 16),
      ],
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _tipCard(LucideIcons.droplet, Tw.blue500, Tw.blue100, Tw.blue50, 'Su',
                  'Günde en az 2L su iç. Cildin nemine doğrudan etki eder.'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _tipCard(LucideIcons.moon, Tw.indigo500, Tw.indigo100, Tw.indigo50, 'Uyku',
                  '7-8 saat uyku hedefle. Cilt gece kendini onarır.'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (v.wellnessItems.isNotEmpty) ...[
        Row(children: [
          const Icon(LucideIcons.heart, size: 16, color: Tw.purple600),
          const SizedBox(width: 8),
          Expanded(child: Text(i18n.t('dashboard.mindMovementTitle'), style: tx(14, w: 7, c: Tw.gray700))),
        ]),
        const SizedBox(height: 8),
        ..._spaced([for (var i = 0; i < v.wellnessItems.length; i++) _LifestyleCard(key: ValueKey('w-$i'), item: v.wellnessItems[i], ctx: c)], 8),
        const SizedBox(height: 16),
      ],
      if (truthy(photoUrl)) ...[_photoCard(c, str(photoUrl)), const SizedBox(height: 20)],
      const SizedBox(height: 16),
      SecondaryButton(
        onPressed: () => context.go('/dashboard/analyze'),
        borderColor: theme.primaryLight,
        textColor: theme.primary,
        icon: LucideIcons.circlePlus,
        label: i18n.t('dashboard.newAnalyzeCta'),
      ),
    ];

    return ThemedPage(theme: theme, maxWidth: 672, children: children);
  }

  Widget _tipCard(IconData icon, Color iconColor, Color border, Color bg, String title, String body) => RCard(
        padding: const EdgeInsets.all(16),
        borderColor: border,
        color: Color.alphaBlend(bg.withValues(alpha: .3), Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(height: 4),
            Text(title, style: tx(12, w: 7)),
            const SizedBox(height: 4),
            Text(body, style: tx(11, c: Tw.gray600)),
          ],
        ),
      );

  Widget _weatherCard(I18n i18n, Map weather) {
    Widget cell(IconData icon, Color color, String value, [String? sub]) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .7), borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(height: 2),
                Text(value, style: tx(16, w: 7, c: Tw.gray800)),
                if (sub != null) Text(sub, style: tx(10, c: Tw.gray500)),
              ],
            ),
          ),
        );
    return RCard(
      borderColor: Tw.blue100,
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Tw.blue50, Tw.cyan50]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(LucideIcons.cloudSun, size: 16, color: Tw.blue500),
            const SizedBox(width: 8),
            Expanded(child: Text(i18n.t('dashboard.weatherTitle'), style: tx(12, w: 7))),
          ]),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cell(LucideIcons.thermometer, Tw.orange500, '${str(weather['temperature'])}°C'),
              const SizedBox(width: 8),
              cell(LucideIcons.sun, Tw.amber500, str(weather['uv_index']), 'UV'),
              const SizedBox(width: 8),
              cell(LucideIcons.droplets, Tw.blue500, '%${str(weather['humidity'])}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _activePlanCard(_Ctx c, List<Map> activePlan) {
    return RCard(
      borderColor: Tw.teal100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(LucideIcons.sparkles, size: 20, color: c.theme.primary)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.i18n.t('dashboard.activePlanTitle'), style: tx(14, w: 7)),
                    const SizedBox(height: 2),
                    Text(c.i18n.t('dashboard.activePlanSubtitle'), style: tx(12, c: Tw.gray500)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final p in activePlan) ...[
            Builder(builder: (_) {
              final whenKey = p['when'] == 'morning'
                  ? 'dashboard.activePlanWhenMorning'
                  : p['when'] == 'evening'
                      ? 'dashboard.activePlanWhenEvening'
                      : 'dashboard.activePlanWhenBoth';
              final name = [p['name_tr'], p['name'], p['active']].firstWhere(truthy, orElse: () => '');
              final why = [p['why'], p['why_tr']].firstWhere(truthy, orElse: () => '');
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Tw.gray50.withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Tw.gray100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text(str(name), style: tx(14, w: 6))),
                        const SizedBox(width: 8),
                        Text(c.i18n.t(whenKey).toUpperCase(), style: tx(10, w: 5, c: Tw.teal700, ls: .5)),
                      ],
                    ),
                    if (truthy(why)) ...[
                      const SizedBox(height: 4),
                      Text(str(why), style: tx(12, c: Tw.gray600, h: relaxed)),
                    ],
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _howToChoose(_Ctx c) {
    final i18n = c.i18n;
    TextSpan bullet(int n) => TextSpan(children: [
          const TextSpan(text: '•  '),
          TextSpan(text: i18n.t('dashboard.howToChooseBullet${n}Title'), style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: ' ${i18n.t('dashboard.howToChooseBullet${n}Body')}'),
        ]);
    return RCard(
      borderColor: Tw.teal100,
      color: Color.alphaBlend(Tw.teal50.withValues(alpha: .3), Colors.white),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(LucideIcons.info, size: 20, color: c.theme.primary)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i18n.t('dashboard.howToChooseTitle'), style: tx(14, w: 7)),
                const SizedBox(height: 4),
                Text(i18n.t('dashboard.howToChooseDesc'), style: tx(12, c: Tw.gray600)),
                const SizedBox(height: 8),
                for (var n = 1; n <= 4; n++)
                  Padding(padding: const EdgeInsets.only(bottom: 4), child: Text.rich(bullet(n), style: tx(12, c: Tw.gray600))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _dayCard(_Ctx c, RoutineView v, int d, String morning, String evening) {
    final plan = v.routineByDay[d] ?? const DayPlan([], []);
    final hasAny = plan.morning.isNotEmpty || plan.evening.isNotEmpty || v.wellnessMorningItems.isNotEmpty || v.wellnessEveningItems.isNotEmpty;
    if (!hasAny) return const [];
    final blocks = <Widget>[
      if (plan.morning.isNotEmpty) _block('☀️ $morning', plan.morning, c, numbered: true, keyPrefix: '$d-m'),
      if (v.wellnessMorningItems.isNotEmpty)
        _block('☀️ ${c.i18n.t('dashboard.morningLifestyleLabel', {'time': morning})}', v.wellnessMorningItems, c,
            numbered: false, keyPrefix: '$d-wm'),
      if (plan.evening.isNotEmpty) _block('🌙 $evening', plan.evening, c, numbered: true, keyPrefix: '$d-e'),
      if (v.wellnessEveningItems.isNotEmpty)
        _block('🌙 ${c.i18n.t('dashboard.morningLifestyleLabel', {'time': evening})}', v.wellnessEveningItems, c,
            numbered: false, keyPrefix: '$d-we'),
    ];
    return [
      RCard(
        padding: EdgeInsets.zero,
        clip: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dayHeader(c.theme, c.weekDays[d]),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced(blocks, 16)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _weeklySection(_Ctx c, RoutineView v) {
    final theme = c.theme;
    return [
      const SizedBox(height: 8),
      Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: theme.primary.withValues(alpha: .125), borderRadius: BorderRadius.circular(12)),
            child: Icon(LucideIcons.calendarDays, size: 16, color: theme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.i18n.t('dashboard.weeklyTitle'), style: tx(16, w: 7)),
                Text(c.i18n.t('dashboard.weeklyHint'), style: tx(10, c: Tw.gray500)),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      for (final w in v.weeklyItems) ...[
        RCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(pickAction(w.item, localized: c.localized), style: tx(14, w: 7)),
              StructuredBadges(item: w.item),
              if (pickDetail(w.item, localized: c.localized).isNotEmpty) ...[
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Kısaca: ', style: tx(11, w: 5, c: Tw.gray600)),
                    TextSpan(text: pickDetail(w.item, localized: c.localized)),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tx(11, c: Tw.gray500),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var d = 0; d < c.weekDays.length; d++)
                    Container(
                      constraints: const BoxConstraints(minWidth: 40),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      decoration: BoxDecoration(
                        color: w.displayDays.contains(d) ? theme.primary : Tw.gray50.withValues(alpha: .5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: w.displayDays.contains(d) ? Colors.transparent : Tw.gray200, width: 2),
                      ),
                      child: Text(
                        c.weekDays[d],
                        textAlign: TextAlign.center,
                        style: tx(12, w: 5, c: w.displayDays.contains(d) ? Colors.white : Tw.gray400),
                      ),
                    ),
                ],
              ),
              if (w.displayDays.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Bu maddeyi şu günlerde uygula: ${w.displayDays.map((i) => c.weekDays[i]).join(', ')}',
                    style: tx(10, c: Tw.gray500)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    ];
  }

  Widget _photoCard(_Ctx c, String photoUrl) {
    return RCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(LucideIcons.calendar, size: 16, color: c.theme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('İlerleme Takibi', style: tx(12, w: 7))),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 160,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  photoFromUrlOrPath(photoUrl, height: 160),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0x66000000), Color(0x00000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    right: 8,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: c.theme.primary, borderRadius: BorderRadius.circular(999)),
                          child: Text(c.i18n.t('dashboard.dayLabel', {'n': 1}), style: tx(10, w: 7, c: Colors.white)),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(DateFormat.yMd(c.i18n.lang).format(DateTime.now()),
                              style: tx(10, c: Colors.white.withValues(alpha: .8))),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Alt bileşenlere taşınan ortak bağlam.
class _Ctx {
  _Ctx({required this.i18n, required this.theme, required this.localized, required this.weekDays});

  final I18n i18n;
  final RebiTheme theme;
  final bool localized;
  final List<String> weekDays;

  String get fallbackStepTitle => i18n.t('dashboard.fallbackStepTitle', const {}, 'This step');
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.topGap = 24,
  });

  final String icon;
  final String title;
  final String subtitle;
  final Color color;
  final double topGap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: topGap, bottom: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(12)),
              child: emojiText(icon, 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: tx(16, w: 7)),
                  Text(subtitle, style: tx(10, c: Tw.gray500)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Günlük denge kartı: flow_debug risk seviyesine göre renklenir.
class _DailyBalanceCard extends StatelessWidget {
  const _DailyBalanceCard({required this.item, required this.flowDebug, required this.ctx});

  final RoutineItem? item;
  final Object? flowDebug;
  final _Ctx ctx;

  @override
  Widget build(BuildContext context) {
    final it = item;
    if (it == null) return const SizedBox.shrink();
    final fd = flowDebug is Map ? (flowDebug as Map).cast<String, dynamic>() : null;
    final action = pickAction(it, localized: ctx.localized);
    final detail = pickDetail(it, localized: ctx.localized);
    final level = dailyBalanceLevel(it, fd);
    final (border, bg, pillBg, pillFg) = switch (level) {
      'crisis' => (Tw.red200, Tw.red50.withValues(alpha: .6), Tw.red100, Tw.red800),
      'high' => (Tw.orange200, Tw.orange50.withValues(alpha: .5), Tw.orange100, Tw.orange800),
      'moderate' => (Tw.amber200, Tw.amber50.withValues(alpha: .45), Tw.amber100, Tw.amber900),
      _ => (Tw.teal200, Tw.teal50.withValues(alpha: .4), Tw.teal100, Tw.teal900),
    };
    final risk = fd?['risk_info'];
    final lv = risk is Map ? risk['level'] : null;
    String pillText;
    if (ctx.localized && truthy(lv)) {
      pillText = ctx.i18n.t('dashboard.riskLevels.$lv');
    } else if (risk is Map && truthy(risk['label'])) {
      pillText = str(risk['label']);
    } else {
      final t = action.replaceFirst(RegExp(r'^Günlük denge:\s*', caseSensitive: false), '').trim();
      pillText = t.isEmpty ? '—' : t;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: RCard(
        padding: const EdgeInsets.all(16),
        borderColor: border,
        borderWidth: 2,
        color: Color.alphaBlend(bg, Colors.white),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: ctx.theme.primary.withValues(alpha: .145), borderRadius: BorderRadius.circular(12)),
              child: Icon(LucideIcons.activity, size: 20, color: ctx.theme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(ctx.i18n.t('dashboard.dailyBalanceTitle'), style: tx(14, w: 7)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: pillBg, borderRadius: BorderRadius.circular(999)),
                        child: Text(pillText, style: tx(10, w: 6, c: pillFg)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(detail, style: tx(12, c: Tw.gray700, h: relaxed)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rutin adımı: numara / ikon, başlık, rozetler, "neden?" açılır detayı.
class _ProductStep extends StatefulWidget {
  const _ProductStep({super.key, required this.item, required this.ctx, this.step, this.onFinished});

  final RoutineItem item;
  final _Ctx ctx;
  final int? step;

  /// Verilirse bakım adımında "Ürün bitti" düğmesi çıkar; dönüş: sunucuya yazıldı mı.
  final Future<bool> Function(RoutineItem item)? onFinished;

  @override
  State<_ProductStep> createState() => _ProductStepState();
}

class _ProductStepState extends State<_ProductStep> {
  bool _showDetail = false;
  bool _finishing = false;
  bool _finishedLogged = false;

  Future<void> _markFinished() async {
    final onFinished = widget.onFinished;
    if (onFinished == null || _finishing) return;
    setState(() => _finishing = true);
    final ok = await onFinished(widget.item);
    if (mounted) {
      setState(() {
        _finishing = false;
        _finishedLogged = ok;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final c = widget.ctx;
    final i18n = c.i18n;
    final theme = c.theme;
    final isSkincare = item['category'] == 'Bakım' || item['category'] == 'Koruma';
    final usageRaw = item['usage'] != null ? str(item['usage']).trim() : '';
    final so = stepOrder(item);
    final usage = usageRaw.isNotEmpty
        ? usageRaw
        : isSkincare
            ? (so <= 15
                ? i18n.t('dashboard.defaultUsage.cleanser')
                : so <= 25
                    ? i18n.t('dashboard.defaultUsage.serum')
                    : so <= 35
                        ? i18n.t('dashboard.defaultUsage.moisturizer')
                        : so >= 40
                            ? i18n.t('dashboard.defaultUsage.sunscreen')
                            : i18n.t('dashboard.defaultUsage.generic'))
            : '';
    final hasContent = truthy(item['detail']) || truthy(item['detail_localized']) || usage.isNotEmpty;
    final actionLower = str(item['action']).toLowerCase();
    final hasPlusCombo = isSkincare && str(item['action']).contains('+');
    final looksLikeMoisturizerCombo = hasPlusCombo &&
        (actionLower.contains('nemlendirici') ||
            actionLower.contains('bariyer') ||
            actionLower.contains('onarım') ||
            actionLower.contains('onarim') ||
            actionLower.contains('krem'));
    final detail = pickDetail(item, localized: c.localized);

    return RCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.step != null)
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: theme.primary, borderRadius: BorderRadius.circular(12)),
              child: Text('${widget.step}', style: tx(12, w: 7, c: Colors.white)),
            )
          else
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Tw.gray100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Tw.gray200.withValues(alpha: .8)),
              ),
              child: emojiText(truthy(item['icon']) ? str(item['icon']) : '🧴', 16),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(pickAction(item, localized: c.localized), style: tx(14, w: 7)),
                    if (truthy(item['category']))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: theme.primaryLight, borderRadius: BorderRadius.circular(999)),
                        child: Text(str(item['category']), style: tx(9, w: 5, c: theme.primaryDark)),
                      ),
                  ],
                ),
                StructuredBadges(item: item),
                if (looksLikeMoisturizerCombo) ...[
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: 'Tek üründe hepsi şart değil:', style: tx(11, w: 7, c: Tw.gray700)),
                      const TextSpan(text: ' Bu satır “hedef içerik örnekleri” gibi düşün; hepsini tek üründe bulamazsan benzerlerinden '),
                      TextSpan(text: 'birini', style: tx(11, w: 7, c: Tw.gray700)),
                      const TextSpan(text: ' seçebilirsin.'),
                    ]),
                    style: tx(11, c: Tw.gray500, h: relaxed),
                  ),
                ],
                if (hasContent) ...[
                  const SizedBox(height: 8),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _showDetail = !_showDetail),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: theme.primaryLight),
                        ),
                        child: Text(
                          _showDetail
                              ? i18n.t('common.hide')
                              : isSkincare
                                  ? i18n.t('dashboard.whySkincareButton')
                                  : i18n.t('common.details'),
                          style: tx(12, w: 5, c: theme.primary),
                        ),
                      ),
                    ),
                  ),
                  if (_showDetail) ...[
                    const SizedBox(height: 8),
                    if (detail.isNotEmpty)
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(
                            text: (isSkincare || usage.isNotEmpty) ? i18n.t('dashboard.shortWhy') : i18n.t('dashboard.summary'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: ' $detail'),
                        ]),
                        style: tx(12, c: Tw.gray600, h: relaxed),
                      ),
                    if (usage.isNotEmpty) ...[
                      if (detail.isNotEmpty) const SizedBox(height: 8),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(
                            text: isSkincare ? i18n.t('dashboard.howToApply') : i18n.t('dashboard.howToDo'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: ' $usage'),
                        ]),
                        style: tx(12, c: Tw.gray600, h: relaxed),
                      ),
                    ],
                  ],
                ],
                if (widget.onFinished != null && isSkincare) ...[
                  const SizedBox(height: 8),
                  if (_finishedLogged)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(LucideIcons.check, size: 14, color: Tw.emerald700),
                      const SizedBox(width: 4),
                      Flexible(child: Text(i18n.t('mobileToday.productFinishedLogged'), style: tx(11, w: 5, c: Tw.emerald700))),
                    ])
                  else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextLink(
                        i18n.t('mobileToday.productFinished'),
                        onTap: _finishing ? () {} : _markFinished,
                        style: tx(11, w: 5, c: Tw.gray500),
                        underline: true,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Yaşam / beslenme önerisi kartı.
class _LifestyleCard extends StatefulWidget {
  const _LifestyleCard({super.key, required this.item, required this.ctx});

  final RoutineItem item;
  final _Ctx ctx;

  @override
  State<_LifestyleCard> createState() => _LifestyleCardState();
}

class _LifestyleCardState extends State<_LifestyleCard> {
  bool _showDetail = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final c = widget.ctx;
    final detail = pickDetail(item, localized: c.localized);
    return RCard(
      padding: const EdgeInsets.all(12),
      borderColor: Tw.green100,
      color: Color.alphaBlend(Tw.green50.withValues(alpha: .2), Colors.white),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          emojiText(truthy(item['icon']) ? str(item['icon']) : '🌿', 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pickAction(item, localized: c.localized), style: tx(12, w: 7)),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _showDetail = !_showDetail),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Tw.green200),
                        ),
                        child: Text(
                          _showDetail ? c.i18n.t('common.hide') : c.i18n.t('dashboard.lifestyleThisItem'),
                          style: tx(11, w: 5, c: Tw.green700),
                        ),
                      ),
                    ),
                  ),
                  if (_showDetail) ...[
                    const SizedBox(height: 6),
                    Text(detail, style: tx(11, c: Tw.gray500, h: relaxed)),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
