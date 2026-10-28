import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/day_log.dart';
import '../core/demo_user.dart';
import '../core/i18n.dart';
import '../core/routine_logic.dart';
import '../core/routine_tracking.dart';
import '../core/routine_usage.dart';
import '../core/today_plan.dart';
import '../state/auth_controller.dart';
import '../state/home_sync_controller.dart';
import '../state/location_prompt_controller.dart';
import '../state/notifications_controller.dart';
import '../state/outbox_sync_controller.dart';
import '../state/theme_controller.dart';
import '../state/today_actions.dart';
import '../state/today_plan_controller.dart';
import '../ui/components/location_widgets.dart';
import '../ui/tw.dart';
import '../ui/widgets/stage_overlap.dart';
import '../ui/widgets/common.dart';
import 'today/now_card.dart';
import 'today/routine_hero.dart';
import 'today/empty_start.dart';
import 'today/more_list.dart';
import 'today/today_widgets.dart';
import 'today/today_action_bar.dart';
import 'today/today_header.dart';
import 'today/today_sheets.dart';
import 'today/tracking_tiles.dart';
import 'today/weather_advice_card.dart';
import 'routine/routine_parts.dart';
import 'routine/routine_plan_view.dart';
import '../ui/brand/palette.dart';

/// Ana panel (web: `pages/Dashboard.jsx`).
/// `nav`: webdeki `location.state` — analiz / check-in sonrası taşınan rutin ve meta.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.nav, this.planOnly = false});

  final Map<String, dynamic>? nav;

  /// Rutin sekmesi: gün içi takip yerine tüm haftalık plan gösterilir.
  final bool planOnly;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  late Map<String, dynamic> _nav = widget.nav ?? const {};
  List<RoutineItem>? _fetchedRoutine;
  bool _fetchingDbRoutine = false;
  bool _showPlanExpanded = false;

  bool _translating = false;
  List<RoutineItem>? _translatedFor;
  late final AuthController _auth = context.read<AuthController>();
  late final HomeSyncController _sync = context.read<HomeSyncController>();
  late final NotificationsController _notifications = context.read<NotificationsController>();
  TodayPlanController? _today;
  TodayActions? _actions;
  LocationPromptController? _location;
  StreamSubscription<String>? _recordedSub;
  String? _uid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    _recordedSub?.cancel();
    _auth.removeListener(_onAuth);
    _location?.dispose();
    _actions?.dispose();
    _today?.dispose();
    super.dispose();
  }

  /// Uygulama öne gelince bayat plan (uzun arka plan, gece yarısı, saat dilimi) yeniden okunur; yeni plan
  /// bildirimleri de yeniden kurar.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_today?.reloadIfStale());
  }

  void _onAuth() {
    final next = _auth.user?.id;
    if (next == _uid) return;
    _uid = next;
    _fetchedRoutine = null;
    _recordedSub?.cancel();
    _location?.dispose();
    _location = null;
    _actions?.dispose();
    _actions = null;
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
    _actions?.dispose();
    _today?.dispose();
    _today = today;
    _actions = TodayActions(today);
    // Plan değiştikçe (yüklenince, bir iş kaydedilince) hatırlatma bildirimleri yeniden kurulur.
    today.addListener(() => _notifications.syncReminders(today.plan));
    // Bildirimdeki düğmeyle (+250 ml, Yaptım) kaydedilen iş panele de hemen yansısın.
    _recordedSub?.cancel();
    _recordedSub = _notifications.recordedActions.listen((_) => unawaited(today.reload()));
    setState(() => _fetchingDbRoutine = true);
    try {
      final snap = await _sync.refresh();
      if (!mounted || uid != _uid) return;
      if (snap == null) {
        await _fetchRoutineFromSupabase(uid);
      } else if (snap.routine.isNotEmpty) {
        setState(() => _fetchedRoutine = snap.routine);
      }
      if (mounted && uid == _uid) {
        final locationAllowed = snap?.consent.locationAllowed == true;
        unawaited(today.load(useLocation: locationAllowed));
        // Konum önerisi: gizlilik onayı varsa ve telefon izni henüz sorulmadıysa.
        _location?.dispose();
        final prompt = LocationPromptController(
          userId: uid,
          consentAllowed: locationAllowed,
          onGranted: () => today.load(useLocation: true),
        );
        _location = prompt;
        unawaited(prompt.refresh());
      }
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
        final res = await apiPost('/routine/translate_items', {'user_id': uid, 'routine_items': fetched}, timeout: apiLongTimeout);
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

  /// Hatırlatıcı kartındaki eylem: ekrana git, seçim ekranını aç ya da olayı kaydet.
  Future<void> _runReminderAction(ReminderAction action) async {
    final route = action.route;
    if (route != null) {
      context.go(route);
      return;
    }
    final sheet = action.sheet;
    if (sheet != null) {
      _openSheet(sheet);
      return;
    }
    final type = action.type;
    if (type == null) return;
    await _actions?.record(type, action.payload);
  }

  void _openSheet(DaySheet sheet) {
    final actions = _actions;
    if (actions == null) return;
    showTodaySheet(
      context,
      sheet,
      actions: actions,
      theme: context.read<ThemeController>().theme,
      products: _finishableProducts(),
    );
  }

  /// "Ürün bitti" sayfasında listelenecek bakım ürünleri (sabah + akşam, tekrarsız).
  List<RoutineItem> _finishableProducts() {
    final uid = _uid;
    final merged = _merged(I18n.instance, uid != null && isRoutineTrackingAccepted(uid));
    final view = RoutineView(merged['routine'] as List<RoutineItem>);
    final seen = <String>{};
    return [
      for (final item in [...view.morningProducts, ...view.eveningProducts])
        if (isSkincareStep(item) && seen.add(str(item['action']).trim().toLowerCase())) item,
    ];
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

    // Bugün kökünde (`/dashboard`) kabuk üst güvenli alanı uygulamaz: üst sahne durum çubuğunun altına uzanır. Sahnesiz
    // durumlar (yükleniyor, boş, tam plan) güvenli alanı kendileri uygular.
    Widget safe(Widget child) => SafeArea(bottom: false, child: child);
    if (routine.isEmpty) {
      if (uid != null && uid != demoUserId && _fetchingDbRoutine) {
        return safe(ThemedBackground(theme: theme, child: const Center(child: RingSpinner())));
      }
      return _emptyState(i18n, theme, userName, dateLine);
    }

    final view = RoutineView(routine);
    final trackingMode = accepted && !_showPlanExpanded && !widget.planOnly;
    final ctx = RoutineCtx(i18n: i18n, theme: theme, localized: localized, weekDays: weekDays);

    if (trackingMode) return _tracking(ctx, view, merged, dateLine, userName);
    // Tam plan da üst sahneyle başlar: durum çubuğunun altına uzanır, güvenli alanı sahne uygular.
    return _fullPlan(ctx, view, merged, dateLine, userName, accepted);
  }

  Widget _flashNeedAccept(I18n i18n) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: RCard(
          padding: const EdgeInsets.all(12),
          borderColor: Tw.amber200,
          color: Color.alphaBlend(Tw.amber50.withValues(alpha: .8), Tw.surface),
          child: Text(i18n.t('dashboard.acceptHint'), style: tx(14, c: Tw.amber900)),
        ),
      );

  /// Rutini olmayan kullanıcı (ilk giriş): üst sahne + sahneye binen "İlk adım" kartı. Sahne durum çubuğunun altına
  /// uzandığı için güvenli alanı kendisi uygular (Bugün ve Rutin kökünde kabuk üst güvenli alanı uygulamaz).
  Widget _emptyState(I18n i18n, RebiTheme theme, String userName, String dateLine) {
    return ThemedPage(
      theme: theme,
      maxWidth: 672,
      padding: EdgeInsets.zero,
      children: [
        StageOverlap(
          overlap: TodayHeader.overlap,
          stage: TodayHeader(
            name: userName,
            dateLine: dateLine,
            theme: theme,
            greeting: i18n.t('dashboard.noAnalyzeTitle', {'name': userName}),
            trailing: _AccountShortcut(name: userName, theme: theme),
          ),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_nav['flashNeedAccept'] == true) _flashNeedAccept(i18n),
                TodayEmptyStart(
                  theme: theme,
                  onStart: () => context.go('/dashboard/analyze'),
                  onChat: () => context.go('/dashboard/chat'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tracking(RoutineCtx c, RoutineView v, Map<String, dynamic> merged, String dateLine, String userName) {
    final i18n = c.i18n;
    final theme = c.theme;
    final todayIdx = getTurkeyWeekdayIndex();
    final today = v.routineByDay[todayIdx] ?? const DayPlan([], []);
    final checkinResult = merged['checkinResult'];
    final weather = merged['weather'];
    final actions = _actions;

    // Üst sahne tam genişlikte (durum çubuğunun altına kadar) çizilir; kahraman kart sahnenin alt kenarına biner.
    final bodyChildren = <Widget>[
      FirstRunPrompts(location: _location, theme: theme),
      if (actions != null) ...[
        // Kahraman: günün rutini. Altında gün akışı, havaya göre kararlar ve gün içi kayıtlar.
        RoutineHero(
          actions: actions,
          theme: theme,
          dayLabel: c.weekDays[todayIdx],
          localized: c.localized,
          morning: today.morning,
          evening: today.evening,
          morningNotes: [...v.wellnessMorningItems, ...v.dailyLifestyleItems],
          eveningNotes: [...v.wellnessEveningItems, ...v.dailyLifestyleItems],
        ),
        const SizedBox(height: 14),
        NowCard(
          controller: actions.plan,
          theme: theme,
          onAction: _runReminderAction,
          onRetryPending: () => context.read<OutboxSyncController>().flushNow(),
          onOpenSettings: () => context.push('/dashboard/reminders'),
        ),
        const SizedBox(height: 14),
        _withPlan((plan) => plan == null
            ? const SizedBox.shrink()
            : Padding(padding: const EdgeInsets.only(bottom: 14), child: WeatherDecisionsCard(plan: plan, theme: theme, actions: actions))),
        // Plan yoksa (yüklenemedi) altında kart olmayan yalnız bir etiket kalmasın.
        _withPlan((plan) => plan != null || _today?.loading == true ? SectionLabel(i18n.t('mobileToday.dayLog.title')) : const SizedBox.shrink()),
        TrackingTiles(actions: actions, theme: theme, onOpenSheet: _openSheet),
        const SizedBox(height: 14),
      ] else ...[
        // Demo oturumunda gün içi kayıt yoktur: rutin yalnızca okunur gösterilir.
        if (today.morning.isNotEmpty) ...[
          RoutineBlockCard(icon: LucideIcons.sun, title: i18n.t('dashboard.morning'), ctx: c, tone: BlockTone.morning, steps: today.morning),
          const SizedBox(height: 14),
        ],
        if (today.evening.isNotEmpty) ...[
          RoutineBlockCard(icon: LucideIcons.moon, title: i18n.t('dashboard.evening'), ctx: c, tone: BlockTone.evening, steps: today.evening),
          const SizedBox(height: 14),
        ],
        if (weather is Map && truthy(weather['temperature'])) ...[WeatherLine(weather: weather, ctx: c), const SizedBox(height: 14)],
      ],
      if (v.dailyBalanceItem != null) ...[
        DailyBalanceCard(item: v.dailyBalanceItem, flowDebug: merged['flowDebug'], ctx: c),
        const SizedBox(height: 14),
      ],
      if (checkinResult is Map && truthy(checkinResult['ai_note'])) ...[
        AiNoteCard(checkinResult: checkinResult, ctx: c),
        const SizedBox(height: 14),
      ],
      _withPlan((plan) => TodayMoreList(theme: theme, checkinDone: plan?.checkinDone == true, shelfCount: plan?.productsOut.length ?? 0)),
      const AiDisclaimer(padding: EdgeInsets.only(top: 20)),
    ];
    final page = ThemedPage(
      theme: theme,
      maxWidth: 672,
      padding: EdgeInsets.zero,
      children: [
        StageOverlap(
          overlap: TodayHeader.overlap,
          stage: _withPlan((plan) => TodayHeader(
                name: userName,
                dateLine: dateLine,
                plan: plan,
                theme: theme,
                trailing: _AccountShortcut(name: userName, theme: theme),
              )),
          body: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, actions != null ? 132 : 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: bodyChildren),
          ),
        ),
      ],
    );

    if (actions == null) return page;
    return Stack(
      fit: StackFit.expand,
      children: [
        page,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: TodayActionBar(
            actions: actions,
            theme: theme,
            onProductFinished: () => _openSheet(DaySheet.products),
          ),
        ),
      ],
    );
  }

  Widget _fullPlan(RoutineCtx c, RoutineView v, Map<String, dynamic> merged, String dateLine, String userName, bool accepted) {
    return RoutinePlanView(
      view: v,
      merged: merged,
      ctx: c,
      dateLine: dateLine,
      userName: userName,
      accepted: accepted,
      flashNeedAccept: _nav['flashNeedAccept'] == true,
      onAccept: () => _acceptRoutine(merged),
      onBackToTracking: accepted && _showPlanExpanded && !widget.planOnly ? () => setState(() => _showPlanExpanded = false) : null,
    );
  }
}

/// Bugün başlığındaki hesap kısayolu: baş harfli yuvarlak düğme, "Ben" sekmesini açar.
class _AccountShortcut extends StatelessWidget {
  const _AccountShortcut({required this.name, required this.theme});

  final String name;
  final RebiTheme theme;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return Semantics(
      button: true,
      label: I18n.instance.t('mobileNav.me'),
      child: GestureDetector(
        onTap: () => context.go('/dashboard/profile'),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Brand.cream),
          child: Text(initial, style: heading(20, c: theme.deep, w: 600)),
        ),
      ),
    );
  }
}
