import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/consent_recovery.dart';
import '../../core/daily_tracking.dart';
import '../../core/demo_user.dart';
import '../../core/device_location.dart';
import '../../core/i18n.dart';
import '../../core/image_quality.dart';
import '../../core/privacy_preferences.dart';
import '../../core/routine_tracking.dart';
import '../../state/auth_controller.dart';
import '../../state/theme_controller.dart';
import '../../ui/brand/brand_button.dart';
import '../../ui/brand/brand_mark.dart' show BrandWatermark;
import '../../ui/brand/motion.dart';
import '../../ui/brand/palette.dart';
import '../../ui/components/loading_screen.dart';
import '../../ui/components/photo_picker.dart';
import '../../ui/widgets/app_sheet.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import 'analyze_flow.dart';
import 'analyze_form.dart';
import 'analyze_pages.dart';
import 'analyze_photo_only.dart';

export 'analyze_form.dart' show calcCyclePhase, pssScore, strongActiveFamilyIds;

/// Bölümler (sıra = üst çubuktaki ilerleme çizgileri).
const _chapters = ['about', 'skin', 'life', 'products', 'finish'];

String _chapterOf(String id) {
  if (id.startsWith('sev') || const ['skinType', 'concerns', 'primary', 'zones', 'flags'].contains(id)) return 'skin';
  if (id.startsWith('pss') || const ['waterSleep', 'stressIntro', 'smoking', 'alcohol', 'makeup', 'shaving'].contains(id)) return 'life';
  if (const ['actives', 'tolerance'].contains(id)) return 'products';
  if (const ['photo', 'summary'].contains(id)) return 'finish';
  return 'about';
}

/// Cilt analizi sihirbazı (web: `pages/Analyze.jsx`). Tek soru tek ekran: sorular bölümlere ayrılır, tek seçimli
/// sorular dokununca ilerler, ilgisiz sorular (hamilelikte adet tarihi, sorunsuz ciltte şiddet anketi…) hiç sorulmaz.
class AnalyzeScreen extends StatefulWidget {
  const AnalyzeScreen({super.key, required this.photoOnly});

  final bool photoOnly;

  @override
  State<AnalyzeScreen> createState() => _AnalyzeScreenState();
}

class _AnalyzeScreenState extends State<AnalyzeScreen> with WidgetsBindingObserver implements FlowHost {
  late final AnalyzeForm _form;
  String _pageId = 'intro';

  /// Geçiş yönü: 1 ileri, -1 geri.
  int _direction = 1;
  bool _loading = false;
  String _submitError = '';

  /// İlk analizden sonra varsayılan: kısa ekran; kullanıcı isterse tam sihirbazı açar.
  bool _forceFullWizard = false;

  /// Stres testi (10 soru) isteğe bağlıdır; çözülmek istenirse sayfaları listeye girer.
  bool _stressTest = false;
  bool _locating = false;
  String _locationError = '';
  LocationFailure? _locationFailure;
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final meta = context.read<AuthController>().user?.userMetadata;
    _form = AnalyzeForm(name: (meta?['full_name'] ?? '').toString());
    _form.name.addListener(_rebuild);
    _form.age.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoTimer?.cancel();
    _form.dispose();
    super.dispose();
  }

  // ═══ FlowHost ═══

  @override
  AnalyzeForm get form => _form;

  @override
  I18n get i18n => I18n.instance;

  @override
  Pack get pack => Pack(i18n.analyzeWizardPack);

  @override
  Map<String, dynamic> get severityPack => i18n.severityTestsPack;

  @override
  bool get locating => _locating;

  @override
  String get locationError => _locationError;

  @override
  LocationFailure? get locationFailure => _locationFailure;

  /// Ayarlardan dönülünce (servis açıldı / izin verildi) hata kalkar; satır yeniden "Konumumu paylaş" olur.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final f = _locationFailure;
    if (state == AppLifecycleState.resumed && (f == LocationFailure.serviceOff || f == LocationFailure.blocked)) {
      setState(() {
        _locationFailure = null;
        _locationError = '';
      });
    }
  }

  @override
  void refresh(VoidCallback change) => setState(change);

  @override
  void answer(VoidCallback change, {bool advance = true}) {
    setState(change);
    _autoTimer?.cancel();
    // Ekran okuyucu kullanıcıları için kendiliğinden ilerleme kapalı: "Devam et" düğmesini kullanırlar.
    if (!advance || MediaQuery.of(context).accessibleNavigation) return;
    final from = _pageId;
    _autoTimer = Timer(const Duration(milliseconds: 280), () {
      if (mounted && _pageId == from) _next();
    });
  }

  // ═══ Sayfa dizisi ═══

  List<String> _pages() {
    final f = _form;
    final sevCount = severityQuestionsFor(severityPack, f.primaryConcern).length;
    return [
      'intro',
      'basics',
      'gender',
      if (f.isFemale) 'hormonal',
      if (f.periodNeeded) 'period',
      'skinType',
      'concerns',
      if (f.concerns.length > 1) 'primary',
      if (f.primaryConcern != 'general') 'zones',
      if (f.hasAgingConcern || f.hasSensitivityConcern) 'flags',
      for (var i = 0; i < sevCount; i++) 'sev$i',
      'waterSleep',
      'stressIntro',
      if (_stressTest)
        for (var i = 0; i < 10; i++) 'pss$i',
      if (f.asksHabits) ...['smoking', 'alcohol'],
      if (f.asksMakeup) 'makeup',
      if (f.asksShaving) 'shaving',
      'actives',
      'tolerance',
      'photo',
      'summary',
    ];
  }

  /// Bu sayfada "Devam et" açık mı.
  bool _canContinue(String id) {
    final f = _form;
    if (id.startsWith('sev')) {
      final qs = severityQuestionsFor(severityPack, f.primaryConcern);
      final i = int.parse(id.substring(3));
      return i < qs.length && (f.severityAnswers[f.primaryConcern]?.containsKey(qs[i]['id'].toString()) ?? false);
    }
    if (id.startsWith('pss')) return f.pssTouched[int.parse(id.substring(3))];
    return switch (id) {
      'basics' => f.basicsDone,
      'gender' => f.gender.isNotEmpty,
      'hormonal' => f.hormonalStatus.isNotEmpty,
      'period' => f.lastPeriodDate.isNotEmpty,
      'skinType' => f.skinType.isNotEmpty,
      'concerns' => f.concerns.isNotEmpty,
      _ => true,
    };
  }

  void _go(String id, int direction) {
    _autoTimer?.cancel();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _pageId = id;
      _direction = direction;
      _submitError = '';
    });
  }

  void _next() {
    final pages = _pages();
    final i = pages.indexOf(_pageId);
    if (i >= 0 && i < pages.length - 1) _go(pages[i + 1], 1);
  }

  void _back() {
    final pages = _pages();
    final i = pages.indexOf(_pageId);
    if (i <= 0) {
      _exit();
    } else {
      _go(pages[i - 1], -1);
    }
  }

  void _exit() => context.canPop() ? context.pop() : context.go('/dashboard/routine');

  /// Kapat: ilk sorudan sonra cevaplar kaybolacağı için sorar.
  Future<void> _close() async {
    final pages = _pages();
    if (pages.indexOf(_pageId) <= 1) return _exit();
    final leave = await AppSheet.show<bool>(
      context,
      title: i18n.t('mobileAnalyze.leaveTitle'),
      subtitle: i18n.t('mobileAnalyze.leaveBody'),
      body: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrimaryButton(
            key: const Key('flow-stay'),
            onPressed: () => Navigator.of(ctx).pop(false),
            color: context.read<ThemeController>().theme.primary,
            label: i18n.t('mobileAnalyze.leaveStay'),
          ),
          const SizedBox(height: 10),
          SecondaryButton(key: const Key('flow-leave'), onPressed: () => Navigator.of(ctx).pop(true), label: i18n.t('mobileAnalyze.leaveExit')),
        ],
      ),
    );
    if (leave == true && mounted) _exit();
  }

  // ═══ Eylemler ═══

  /// "Konumumu paylaş": önce sunucudaki konum izni (yoksa açıkça sorulur: rutin konum bilgisiyle gönderilirken sunucu
  /// izin ister), sonra telefon izni ve konum. Başarısızlıkta nedeni söylenir; ayar gerekiyorsa satır ayarı açar.
  @override
  Future<void> locate() async {
    if (_locating) return;
    final fix = _locationFailure;
    if (fix == LocationFailure.serviceOff || fix == LocationFailure.blocked) {
      await openLocationSettingsFor(fix!);
      return;
    }
    setState(() {
      _locating = true;
      _locationError = '';
      _locationFailure = null;
    });
    final uid = context.read<AuthController>().user?.id;
    if (uid != null && uid != demoUserId && !await _ensureLocationConsent(uid)) {
      if (mounted) setState(() => _locating = false);
      return;
    }
    final r = await acquireDeviceLocation();
    if (!mounted) return;
    setState(() {
      _locating = false;
      final at = r.at;
      if (at != null) {
        _form.lat = at.lat;
        _form.lon = at.lon;
      } else {
        _locationFailure = r.failure;
        _locationError = i18n.t('mobileAnalyze.location.${(r.failure ?? LocationFailure.timeout).name}');
      }
    });
  }

  /// Konum işleme izni sunucuda açık mı; değilse nedenini söyleyip kullanıcıdan ister. false: konum alınmayacak.
  Future<bool> _ensureLocationConsent(String uid) async {
    var photoAllowed = false;
    try {
      final prefs = await getPrivacyPreferences(uid);
      if (prefs['location_processing_allowed'] == true) return true;
      photoAllowed = prefs['photo_processing_allowed'] == true;
    } catch (_) {
      if (mounted) setState(() => _locationError = i18n.t('mobileAnalyze.location.consentFailed'));
      return false;
    }
    if (!mounted) return false;
    final allow = await AppSheet.show<bool>(
      context,
      title: i18n.t('mobileAnalyze.location.consentTitle'),
      subtitle: i18n.t('mobileAnalyze.location.consentBody'),
      body: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrimaryButton(
            key: const Key('flow-location-allow'),
            onPressed: () => Navigator.of(ctx).pop(true),
            color: context.read<ThemeController>().theme.primary,
            label: i18n.t('mobileAnalyze.location.consentAllow'),
          ),
          const SizedBox(height: 10),
          SecondaryButton(
            key: const Key('flow-location-later'),
            onPressed: () => Navigator.of(ctx).pop(false),
            label: i18n.t('mobileAnalyze.location.consentLater'),
          ),
        ],
      ),
    );
    if (allow != true) return false;
    try {
      await updatePrivacyPreferences(uid, location: true, photo: photoAllowed);
      return true;
    } catch (_) {
      if (mounted) setState(() => _locationError = i18n.t('mobileAnalyze.location.consentFailed'));
      return false;
    }
  }

  @override
  Future<void> pickPhoto(ImageSource source, CameraDevice camera) async {
    PickedPhoto? picked;
    try {
      picked = await pickSkinPhoto(source, camera: camera);
    } on PlatformException {
      return;
    }
    if (picked == null || !mounted) return;
    setState(() => _form.photo = picked);
    final q = await analyzeSkinPhotoQuality(picked.bytes);
    if (mounted && identical(_form.photo, picked)) setState(() => picked!.quality = q);
  }

  @override
  Future<void> pickDate() async {
    final now = DateTime.now();
    final last = _form.lastPeriodDate;
    final initial = last.isNotEmpty ? DateTime.parse(last) : now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      locale: Locale(I18n.instance.lang),
    );
    if (picked != null && mounted) setState(() => _form.lastPeriodDate = DateFormat('yyyy-MM-dd').format(picked));
  }

  Future<void> _submit() async {
    final user = context.read<AuthController>().user;
    final router = GoRouter.of(context);
    final f = _form;
    setState(() {
      _submitError = '';
      _loading = true;
    });
    try {
      String? photoUrl;
      String? photoPath;
      final photo = f.photo;
      final client = supabase;
      if (photo != null && client != null) {
        final path = '${user?.id ?? demoUserId}/${DateTime.now().millisecondsSinceEpoch}.${photo.extension}';
        try {
          await client.storage.from('skin-photos').upload(path, File(photo.file.path));
          photoPath = path;
          try {
            photoUrl = await client.storage.from('skin-photos').createSignedUrl(path, 3600);
          } catch (_) {
            /* imzalı adres alınamazsa yerel önizleme gösterilir */
          }
          if (user != null) {
            unawaited(
              ingestDailyTrackingEvent(user.id, 'photo_meta', {
                'context': f.photoContext,
                'meanLuma': photo.quality?.meanLuma,
                'variance': photo.quality?.variance,
                'sharpnessApprox': photo.quality?.sharpnessApprox,
                'flow': 'analyze_full',
              }),
            );
          }
        } catch (_) {
          if (mounted) setState(() => _submitError = pack.s('errors.photoUploadWarn'));
        }
      } else if (photo != null && client == null) {
        setState(() => _submitError = pack.s('errors.storageOffWarn'));
      }

      final body = f.toBody(userId: user?.id ?? demoUserId, photoPath: photoPath, severity: f.severityScore(severityPack));
      final res = await apiPost('/generate_routine', body, timeout: apiLongTimeout);
      if (!res.ok) {
        if (isConsentError(res.status, res.data)) {
          requestConsentRecovery();
          if (mounted) setState(() => _submitError = I18n.instance.t('common.consentRecoveryBody'));
          return;
        }
        final msg = formatApiErrorDetail(res.data);
        if (mounted) setState(() => _submitError = '$msg (${res.status})');
        return;
      }
      final data = res.data;
      final localPreview = photo?.file.path;
      router.go(
        '/dashboard',
        extra: {
          'routine': data['routine'],
          'weather': data['weather'],
          'insights': data['holistic_insights'],
          'assessmentId': data['assessment_id'],
          'photoUrl': photoUrl ?? localPreview,
          'routineWithoutPhoto': photoUrl == null && localPreview == null,
          'userName': f.name.text,
          'concern': f.primaryConcern,
          'flowDebug': data['flow_debug'],
          'safetyAbsoluteRules': data['safety_absolute_rules'],
          'ruleEnforcementReport': data['rule_enforcement_report'],
          'aiPolishNote': data['ai_polish_note'],
          'activePlan': data['active_plan'] is List ? data['active_plan'] : const [],
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _submitError = isNetworkError(e) ? pack.s('errors.networkError') : pack.s('errors.unexpectedError'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ═══ Görünüm ═══

  @override
  Widget build(BuildContext context) {
    if (widget.photoOnly) return const AnalyzePhotoOnly();
    if (_loading) return const LoadingScreen();

    final user = context.watch<AuthController>().user;
    context.watch<ThemeController>();
    final uid = user?.id ?? demoUserId;
    if (!_forceFullWizard && hasCompletedOnboarding(uid)) return _compactHub();

    final pages = _pages();
    final id = pages.contains(_pageId) ? _pageId : 'basics';
    final intro = id == 'intro';
    final reduce = reduceMotion(context);

    return BackButtonListener(
      onBackButtonPressed: () async {
        if (intro) return false;
        _back();
        return true;
      },
      child: intro
          ? _introStage()
          : Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: FlowTop(
                    chapterLabel: i18n.t('mobileAnalyze.chapters.${_chapterOf(id)}'),
                    fractions: _fractions(pages, id),
                    onBack: _back,
                    onClose: _close,
                    backLabel: i18n.t('common.back'),
                    closeLabel: i18n.t('common.close'),
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: reduce ? Duration.zero : const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeIn,
                    layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(begin: Offset(.05 * _direction, 0), end: Offset.zero).animate(anim),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(key: ValueKey(id), child: _pageShell(id)),
                  ),
                ),
                if (_submitError.isNotEmpty) _errorBox(),
                _bottom(id),
              ],
            ),
    );
  }

  Widget _pageShell(String id) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: flowPageBody(id, this)),
      ),
    );
  }

  Widget _bottom(String id) {
    final t = i18n.t;
    switch (id) {
      case 'stressIntro':
        return FlowBottom(
          label: t('mobileAnalyze.stress.start'),
          onPressed: () {
            setState(() => _stressTest = true);
            _next();
          },
          secondaryLabel: t('mobileAnalyze.stress.skip'),
          onSecondary: () {
            setState(() {
              _stressTest = false;
              // Atlanan test varsayılan cevaplarla kalır (eski sihirbazda dokunulmayan kaydırıcılarla aynı).
              for (var i = 0; i < 10; i++) {
                _form.pssAnswers[i] = 0;
                _form.pssTouched[i] = false;
              }
            });
            _next();
          },
        );
      case 'summary':
        return FlowBottom(label: t('mobileAnalyze.summary.create'), leadingIcon: LucideIcons.sparkles, icon: null, onPressed: _submit);
      default:
        return FlowBottom(label: t('mobileAnalyze.next'), onPressed: _canContinue(id) ? _next : null);
    }
  }

  /// Her bölümün doluluk oranı: önceki bölümler dolu, geçerli bölüm kaldığı yere kadar, sonrakiler boş.
  List<double> _fractions(List<String> pages, String id) {
    final current = _chapters.indexOf(_chapterOf(id));
    final index = pages.indexOf(id);
    return [
      for (var c = 0; c < _chapters.length; c++)
        if (c < current)
          1.0
        else if (c > current)
          0.0
        else
          () {
            final members = [
              for (var i = 1; i < pages.length; i++)
                if (_chapterOf(pages[i]) == _chapters[c]) i,
            ];
            if (members.isEmpty) return 0.0;
            return (members.indexOf(index) + 1) / members.length;
          }(),
    ];
  }

  Widget _errorBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Tw.red50.withValues(alpha: .9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Tw.red200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(LucideIcons.circleAlert, size: 20, color: Tw.red600),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i18n.t('analyze.generateFailedTitle'), style: tx(14, w: 6, c: Tw.red950)),
                      const SizedBox(height: 4),
                      Text(
                        _submitError,
                        style: tx(14, c: Tw.red900.withValues(alpha: .95), h: relaxed),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _submitError = ''),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(i18n.t('common.close'), style: tx(13, w: 6, c: Tw.red700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Karşılama: giriş ekranıyla aynı sahne (derin orman yeşili + krem panel); ne soracağımızı ve ne kadar süreceğini söyler.
  Widget _introStage() {
    final t = i18n.t;
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    Widget row(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Brand.ink.withValues(alpha: .07)),
            child: Icon(icon, size: 18, color: Brand.ink),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(text, style: tx(15.5, c: Brand.ink, h: 1.35)),
            ),
          ),
        ],
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Brand.paper,
        systemNavigationBarIconBrightness: Brand.dark ? Brightness.light : Brightness.dark,
      ),
      child: ColoredBox(
        color: Brand.forest,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned(right: -90, top: -20, child: BrandWatermark(size: 300)),
            CustomScrollView(
              physics: const ClampingScrollPhysics(),
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    children: [
                      SizedBox(height: top + 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: IconButton(
                            tooltip: t('common.back'),
                            onPressed: _exit,
                            icon: const Icon(LucideIcons.chevronLeft, size: 26, color: Brand.cream),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(26, 24, 26, 36),
                                child: Reveal(
                                  offset: const Offset(0, 18),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Semantics(
                                        header: true,
                                        child: Text(t('mobileAnalyze.intro.title'), style: Brand.serif(40, ls: -1.1, h: 1.05, color: Brand.cream)),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(t('mobileAnalyze.intro.lead'), style: tx(16.5, c: Brand.cream.withValues(alpha: .76), h: 1.45)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.fromLTRB(26, 30, 26, 22 + bottom),
                        decoration: BoxDecoration(
                          color: Brand.paper,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 480),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                row(LucideIcons.clock, t('mobileAnalyze.intro.time')),
                                row(LucideIcons.circleCheck, t('mobileAnalyze.intro.easy')),
                                row(LucideIcons.lock, t('mobileAnalyze.intro.private')),
                                const SizedBox(height: 6),
                                BrandButton(
                                  key: const Key('flow-start'),
                                  onPressed: _next,
                                  label: t('mobileAnalyze.intro.start'),
                                  trailingIcon: LucideIcons.arrowRight,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// İlk analizden sonra: rutin hazır; hızlı fotoğraf ya da yeni tam analiz.
  Widget _compactHub() {
    final theme = context.watch<ThemeController>().theme;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: IconButton(
                tooltip: i18n.t('common.back'),
                onPressed: _exit,
                icon: Icon(LucideIcons.chevronLeft, size: 26, color: Tw.gray700),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: theme.primary.withValues(alpha: .12)),
                        child: Icon(LucideIcons.sparkles, size: 28, color: theme.fg),
                      ),
                      const SizedBox(height: 20),
                      Semantics(header: true, child: Text(i18n.t('analyze.routineReadyTitle'), style: heading(32, h: 1.1))),
                      const SizedBox(height: 12),
                      Text(pack.s('compactHub.description'), style: tx(15.5, c: Tw.gray500, h: 1.5)),
                      const SizedBox(height: 28),
                      PrimaryButton(
                        onPressed: () => context.go('/dashboard'),
                        color: theme.primary,
                        label: pack.s('compactHub.backToDashboard'),
                        trailingIcon: LucideIcons.arrowRight,
                        minHeight: 56,
                      ),
                      const SizedBox(height: 12),
                      SecondaryButton(
                        onPressed: () => context.push('/dashboard/analyze?photo=1'),
                        icon: LucideIcons.camera,
                        label: i18n.t('analyze.quickPhotoUpload'),
                        fontSize: 15,
                        minHeight: 56,
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: () => setState(() {
                          _forceFullWizard = true;
                          _pageId = 'intro';
                        }),
                        style: TextButton.styleFrom(minimumSize: const Size(48, 52)),
                        child: Text(i18n.t('analyze.newAnalyzeFull'), style: tx(14.5, w: 6, c: Tw.gray600)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
