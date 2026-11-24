import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/analyze_draft.dart';
import '../../core/api.dart';
import '../../core/consent_recovery.dart';
import '../../core/daily_tracking.dart';
import '../../core/demo_user.dart';
import '../../core/device_location.dart';
import '../../core/i18n.dart';
import '../../core/image_quality.dart';
import '../../core/last_assessment.dart';
import '../../core/privacy_preferences.dart';
import '../../core/routine_tracking.dart';
import '../../state/auth_controller.dart';
import '../../state/theme_controller.dart';
import '../../ui/brand/brand_button.dart';
import '../../ui/brand/brand_mark.dart' show BrandWatermark;
import '../../ui/brand/motion.dart';
import '../../ui/brand/palette.dart';
import '../../ui/components/loading_screen.dart';
import '../../ui/components/modals.dart';
import '../../ui/components/photo_picker.dart';
import '../../ui/widgets/app_sheet.dart';
import '../../ui/shell/page_stage.dart';
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
  if (id.startsWith('sev_') ||
      id.startsWith('zones_') ||
      id.startsWith('tl_') ||
      const ['skinType', 'concerns', 'primary', 'flags', 'triggers', 'pastTreatments', 'expectations'].contains(id)) {
    return 'skin';
  }
  if (id.startsWith('pss') ||
      const ['waterSleep', 'stressIntro', 'smoking', 'alcohol', 'nutrition', 'makeup', 'shaving'].contains(id)) {
    return 'life';
  }
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

  /// Cevaplar cihazdaki taslaktan geri geldi: üstte "kaldığın yerden devam ediyorsun" şeridi çıkar.
  bool _resumedFromDraft = false;

  /// Cevaplar önceki analizden dolduruldu (yeni analizde baştan yazmak gerekmesin).
  bool _prefilledFromLast = false;

  /// Taslağı diske yazma gecikmesi: her dokunuşta değil, kısa bir duruştan sonra yazılır.
  Timer? _saveTimer;

  /// Taslağın hangi kullanıcıya yazıldığı (çıkışta da aynı anahtar kullanılsın).
  String? _draftUid;

  /// Rutin üretildi: taslak silindi ve bir daha yazılmayacak. Bu olmasa `dispose` içindeki
  /// son yazma, az önce silinen taslağı geri getirir ve sonraki analizde eski cevaplar sorulur.
  bool _draftDone = false;
  bool _locating = false;
  String _locationError = '';
  LocationFailure? _locationFailure;
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final user = context.read<AuthController>().user;
    final meta = user?.userMetadata;
    _form = AnalyzeForm(name: (meta?['full_name'] ?? '').toString());
    _form.name.addListener(_rebuild);
    _form.age.addListener(_rebuild);
    _draftUid = user?.id ?? demoUserId;
    _restoreDraft();
  }

  /// Yarım kalan cevaplar: uygulama kapansa, kullanıcı çıksa ya da yanlışlıkla başa dönse de kaybolmaz.
  void _restoreDraft() {
    final draft = getAnalyzeDraft(_draftUid);
    if (draft == null) return;
    final answers = draft['answers'];
    if (answers is! Map) return;
    _form.applyDraft(answers.cast<String, dynamic>());
    if (!_form.hasAnswers) return;
    _stressTest = draft['stressTest'] == true;
    final saved = draft['pageId'];
    if (saved is String && saved.isNotEmpty && saved != 'intro') {
      _pageId = _pages().contains(saved) ? saved : 'basics';
      // Taslak varsa kısa ekranı atla: kullanıcı yarım bıraktığı sihirbaza döner.
      _forceFullWizard = true;
    }
    _resumedFromDraft = true;
  }

  /// Taslağı kısa bir duruştan sonra diske yazar (her dokunuşta disk yazmamak için).
  void _scheduleDraftSave() {
    if (_draftDone) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _writeDraft);
  }

  void _writeDraft() {
    if (_draftDone || !_form.hasAnswers) return;
    unawaited(saveAnalyzeDraft(_draftUid, pageId: _pageId, stressTest: _stressTest, answers: _form.toDraft()));
  }

  /// Cevapları temizleyip sihirbazı baştan açar (kullanıcı açıkça isterse).
  Future<void> _startOver() async {
    _saveTimer?.cancel();
    _draftDone = false;
    await clearAnalyzeDraft(_draftUid);
    if (!mounted) return;
    setState(() {
      final meta = context.read<AuthController>().user?.userMetadata;
      _form.resetAnswers(name: (meta?['full_name'] ?? '').toString());
      _stressTest = false;
      _resumedFromDraft = false;
      _prefilledFromLast = false;
      _pageId = 'basics';
      _direction = 1;
      _submitError = '';
    });
  }

  void _rebuild() {
    if (mounted) setState(() {});
    _scheduleDraftSave();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoTimer?.cancel();
    _saveTimer?.cancel();
    _writeDraft();
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
  void refresh(VoidCallback change) {
    setState(change);
    _scheduleDraftSave();
  }

  @override
  void answer(VoidCallback change, {bool advance = true}) {
    setState(change);
    _scheduleDraftSave();
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
    final zoneConcerns = f.concerns.where((c) => c != 'general').toList();
    return [
      'intro',
      'basics',
      'gender',
      if (f.isFemale) 'hormonal',
      if (f.periodNeeded) 'period',
      'skinType',
      'concerns',
      if (f.concerns.length > 1) 'primary',
      for (final c in zoneConcerns) 'zones_$c',
      if (f.hasAgingConcern || f.hasSensitivityConcern) 'flags',
      for (final c in f.concerns)
        for (var i = 0; i < severityQuestionsFor(severityPack, c).length; i++) 'sev_${c}_$i',
      for (final c in f.concerns) 'tl_$c',
      'triggers',
      'pastTreatments',
      'expectations',
      'waterSleep',
      'stressIntro',
      if (_stressTest)
        for (var i = 0; i < 10; i++) 'pss$i',
      if (f.asksHabits) ...['smoking', 'alcohol'],
      'nutrition',
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
    final sev = RegExp(r'^sev_(.+)_(\d+)$').firstMatch(id);
    if (sev != null) {
      final concern = sev.group(1)!;
      final i = int.parse(sev.group(2)!);
      final qs = severityQuestionsFor(severityPack, concern);
      return i < qs.length && (f.severityAnswers[concern]?.containsKey(qs[i]['id'].toString()) ?? false);
    }
    if (id.startsWith('tl_')) return f.timelineReadyFor(id.substring(3));
    if (id.startsWith('pss')) return f.pssTouched[int.parse(id.substring(3))];
    return switch (id) {
      'basics' => f.basicsDone,
      'gender' => f.gender.isNotEmpty,
      'hormonal' => f.hormonalStatus.isNotEmpty,
      'period' => f.lastPeriodDate.isNotEmpty,
      'skinType' => f.skinType.isNotEmpty,
      'concerns' => f.concerns.isNotEmpty,
      // Tıraş: hayır yeter; evetse sonrası (rahat/tahriş/batık) açıkça seçilmeli — tahriş varsayılanı yok.
      'shaving' => f.shavingFreq == 0 || f.shavingAfter.isNotEmpty,
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
    _scheduleDraftSave();
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

  /// Kapat: cevaplar cihazda kalır (taslak), kullanıcı kaldığı yerden dönebilir.
  Future<void> _close() async {
    final pages = _pages();
    if (pages.indexOf(_pageId) <= 1) return _exit();
    _saveTimer?.cancel();
    _writeDraft();
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
    } on StateError catch (e) {
      if (mounted) setState(() => _submitError = e.message);
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
    if (!await ensureAiSharing(context)) {
      if (mounted) setState(() => _submitError = I18n.instance.t('mobileAiSharing.declined'));
      return;
    }
    if (!mounted) return;
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

      final body = f.toBody(
        userId: user?.id ?? demoUserId,
        photoPath: photoPath,
        severity: f.severityScore(severityPack),
        severityPack: severityPack,
      );
      final res = await apiPost('/generate_routine', body, timeout: apiLongTimeout);
      if (!res.ok) {
        if (isConsentError(res.status, res.data)) {
          requestConsentRecovery();
          if (mounted) setState(() => _submitError = I18n.instance.t('common.consentRecoveryBody'));
          return;
        }
        if (mounted) setState(() => _submitError = '${apiErrorMessage(res)} (${res.status})');
        return;
      }
      final data = res.data;
      // Rutin üretildi: yarım cevap taslağı artık gereksiz.
      _saveTimer?.cancel();
      _draftDone = true;
      await clearAnalyzeDraft(_draftUid);
      final localPreview = photo?.file.path;
      // İlk rutin: kısa karşılama (rutini kabul, gün saatleri, bildirim izni). Sonraki analizlerde doğrudan plana.
      final firstRoutine = user != null && !isRoutineTrackingAccepted(user.id);
      router.go(
        firstRoutine ? '/dashboard/welcome' : '/dashboard',
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
                if (_resumedFromDraft || _prefilledFromLast) _resumeBar(),
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

  /// Yeni tam analiz: baştan yazdırmak yerine önce ne yapılacağı sorulur — yarım kalan taslak varsa
  /// kaldığı yerden, yoksa önceki analizin cevaplarıyla ya da boş formla.
  Future<void> _openFullWizard() async {
    final draft = getAnalyzeDraft(_draftUid);
    final hasDraft = draft != null;
    final choice = await AppSheet.show<String>(
      context,
      title: i18n.t('mobileAnalyze.again.title'),
      subtitle: i18n.t(hasDraft ? 'analyze.again.draftBody' : 'analyze.again.body'),
      body: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrimaryButton(
            key: const Key('analyze-again-keep'),
            onPressed: () => Navigator.of(ctx).pop(hasDraft ? 'draft' : 'last'),
            color: context.read<ThemeController>().theme.primary,
            label: i18n.t(hasDraft ? 'analyze.again.resume' : 'analyze.again.useLast'),
          ),
          const SizedBox(height: 10),
          SecondaryButton(
            key: const Key('analyze-again-fresh'),
            onPressed: () => Navigator.of(ctx).pop('fresh'),
            label: i18n.t('analyze.again.fresh'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'fresh') {
      await _startOver();
      if (mounted) setState(() => _forceFullWizard = true);
      return;
    }
    if (choice == 'draft') {
      setState(() {
        _restoreDraft();
        _forceFullWizard = true;
      });
      return;
    }
    await _prefillFromLast();
  }

  /// Önceki analizin cevaplarını forma yazar; okunamazsa boş formla açılır.
  Future<void> _prefillFromLast() async {
    setState(() => _loading = true);
    LastAssessment? last;
    try {
      final uid = context.read<AuthController>().user?.id;
      if (uid != null && uid != demoUserId) last = await fetchLastAssessment(uid);
    } catch (_) {
      /* önceki analiz okunamadı: boş formla devam */
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _forceFullWizard = true;
      _pageId = 'basics';
      _direction = 1;
      _stressTest = false;
      _resumedFromDraft = false;
      if (last != null) {
        _form.applyDraft(last.toDraftAnswers());
        _prefilledFromLast = true;
      }
    });
    _writeDraft();
  }

  /// Üstteki şerit: cevapların nereden geldiğini söyler ve tek dokunuşla baştan başlatır.
  Widget _resumeBar() {
    final theme = context.watch<ThemeController>().theme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: theme.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(_prefilledFromLast ? LucideIcons.history : LucideIcons.bookmark, size: 18, color: theme.fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              i18n.t(_prefilledFromLast ? 'analyze.again.prefilledNote' : 'analyze.again.resumedNote'),
              style: tx(12.5, w: 5, c: Tw.gray700, h: 1.3),
            ),
          ),
          TextButton(
            key: const Key('analyze-start-over'),
            onPressed: _startOver,
            style: TextButton.styleFrom(minimumSize: const Size(44, 40), padding: const EdgeInsets.symmetric(horizontal: 10)),
            child: Text(i18n.t('analyze.again.fresh'), style: tx(12.5, w: 7, c: theme.fg)),
          ),
        ],
      ),
    );
  }

  /// İlk analizden sonra: rutin hazır; hızlı fotoğraf ya da yeni tam analiz. Diğer sayfalar gibi markanın sahnesinde
  /// durur (eskiden düz zeminde tek başına bir simge + başlıktı); seçenekler sahneye binen tek kartta.
  Widget _compactHub() {
    final theme = context.watch<ThemeController>().theme;
    return StagePage(
      theme: theme,
      title: i18n.t('analyze.routineReadyTitle'),
      subtitle: pack.s('compactHub.description'),
      backTo: '/dashboard/routine',
      maxWidth: 512,
      children: [
        RCard(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
          radius: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              const SizedBox(height: 12),
              SecondaryButton(
                onPressed: () => context.push('/dashboard/routine/edit'),
                icon: LucideIcons.listChecks,
                label: i18n.t('mobileRoutineEdit.entry'),
                fontSize: 15,
                minHeight: 56,
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _openFullWizard,
                style: TextButton.styleFrom(minimumSize: const Size(48, 52)),
                child: Text(i18n.t('analyze.newAnalyzeFull'), style: tx(14.5, w: 6, c: Tw.gray600)),
              ),
            ],
          ),
        ),
      ],
    );
  }

}
