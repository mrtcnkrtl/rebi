import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/consent_recovery.dart';
import '../../core/daily_tracking.dart';
import '../../core/demo_user.dart';
import '../../core/device_location.dart' show roundCoordinate;
import '../../core/i18n.dart';
import '../../core/image_quality.dart';
import '../../core/interpolate.dart';
import '../../core/routine_tracking.dart';
import '../../state/auth_controller.dart';
import '../../state/theme_controller.dart';
import '../../ui/components/loading_screen.dart';
import '../../ui/components/photo_picker.dart';
import '../../ui/components/severity_test.dart';
import '../../ui/components/skin_type_visual.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import 'analyze_photo_only.dart';
import 'analyze_widgets.dart';

const strongActiveFamilyIds = [
  'retinol',
  'adapalene',
  'bha',
  'aha',
  'benzoyl',
  'azelaic',
  'vitamin_c',
  'vitamin_c_derivatives',
  'bakuchiol',
  'pigment',
  'niacinamide',
  'zinc_pca',
  'sulfur',
  'urea',
];

const _concernDefs = [
  ('general', '🧼'),
  ('oiliness', '💧'),
  ('pores', '🕳️'),
  ('acne', '🔴'),
  ('aging', '✨'),
  ('dryness', '🏜️'),
  ('pigmentation', '🎯'),
  ('sensitivity', '🌸'),
];

const _zoneIds = ['forehead', 'nose', 'cheeks', 'chin', 'undereye', 'lips', 'temples'];

/// Son adet tarihinden döngü evresi. Web `new Date("YYYY-MM-DD")` UTC gece yarısı sayar.
String calcCyclePhase(String lastPeriodDate, int cycleLength, {DateTime? now}) {
  if (lastPeriodDate.isEmpty) return 'unknown';
  final p = lastPeriodDate.split('-').map(int.parse).toList();
  final start = DateTime.utc(p[0], p[1], p[2]);
  final diff = ((now ?? DateTime.now()).millisecondsSinceEpoch - start.millisecondsSinceEpoch) / 86400000;
  final days = diff.floor();
  final day = ((days % cycleLength) + cycleLength) % cycleLength;
  if (day <= 5) return 'menstrual';
  if (day <= 13) return 'follicular';
  if (day <= 15) return 'ovulation';
  return 'luteal';
}

/// PSS-10: maddeler 4,5,7,8 (0 tabanlı 3,4,6,7) ters puanlanır. Toplam 0–40.
int pssScore(List<int> answers) {
  var acc = 0;
  for (var i = 0; i < answers.length; i++) {
    acc += const [3, 4, 6, 7].contains(i) ? 4 - answers[i] : answers[i];
  }
  return acc;
}

/// Cilt analizi sihirbazı (web: `pages/Analyze.jsx`).
class AnalyzeScreen extends StatefulWidget {
  const AnalyzeScreen({super.key, required this.photoOnly});

  final bool photoOnly;

  @override
  State<AnalyzeScreen> createState() => _AnalyzeScreenState();
}

class _AnalyzeScreenState extends State<AnalyzeScreen> {
  final _scroll = ScrollController();

  int _step = 1;
  bool _loading = false;
  String _submitError = '';

  /// İlk analizden sonra varsayılan: kısa ekran; kullanıcı isterse tam sihirbazı açar.
  bool _forceFullWizard = false;

  // Adım 1
  late final TextEditingController _name;
  final _age = TextEditingController();
  String _gender = '';
  double? _lat;
  double? _lon;
  bool _locationSet = false;
  bool _locationLoading = false;
  String _locationError = '';
  String _hormonalStatus = '';
  String _lastPeriodDate = '';
  int _cycleLength = 28;

  // Adım 2
  String _skinType = '';
  final List<String> _concerns = [];

  /// Her sorun için etkilenen bölgeler: { concernId: [zoneId, ...] }
  final Map<String, List<String>> _concernZones = {};
  double _waterIntake = 2;
  double _sleepHours = 7;
  final List<int> _pssAnswers = List.filled(10, 0);
  int _smokingPerDay = 0;
  int _smokingYears = 0;
  int _alcoholFreq = 0;
  int _alcoholAmt = 1;
  final Map<String, int> _nutrition = {'fastfood': 0, 'sugar': 0, 'dairy': 0, 'veggies': 3};
  int _makeupFreq = 0;
  String _makeupRemoval = 'cleanser';
  final Map<String, bool> _specialFlags = {
    'frown_lines': false,
    'smile_lines': false,
    'eye_crows_feet': false,
    'redness_diffuse': false,
    'redness_acne_marks': false,
    'cold_sensitive': false,
    'stings_with_products': false,
  };

  // Adım 3 — kullanım soruları (şiddet → tetikleyici → tedavi → beklenti)
  int _step3Section = 0;
  final Map<String, int> _severityScoresByConcern = {};
  String _duration = '';
  final List<String> _triggers = [];
  final List<String> _pastTreatments = [];
  final List<String> _expectations = [];
  String _activesExperience = 'occasional';

  // Adım 4 — fotoğraf + rutin oluştur
  PickedPhoto? _photo;
  String _photoContext = 'unsure';

  /// Her güçlü aktif ailesi: never | good | mild | bad
  final Map<String, String> _activesTolerance = {for (final id in strongActiveFamilyIds) id: 'good'};

  @override
  void initState() {
    super.initState();
    final meta = context.read<AuthController>().user?.userMetadata;
    _name = TextEditingController(text: (meta?['full_name'] ?? '').toString());
    _name.addListener(_rebuild);
    _age.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _setStep(int s) {
    setState(() {
      _step = s;
      _submitError = '';
    });
    _scrollTop();
  }

  void _setSection(int s) {
    setState(() => _step3Section = s);
    _scrollTop();
  }

  void _scrollTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  bool get _isFemale => _gender == 'female';

  String get _cyclePhase {
    if (!_isFemale) return '';
    if (_hormonalStatus == 'pregnant') return '';
    if (_hormonalStatus == 'menopause') return 'menopause';
    if ((_hormonalStatus == 'regular' || _hormonalStatus == 'irregular') && _lastPeriodDate.isNotEmpty) {
      return calcCyclePhase(_lastPeriodDate, _cycleLength);
    }
    return '';
  }

  List<String> get _zones {
    final out = <String>[];
    for (final list in _concernZones.values) {
      for (final z in list) {
        if (!out.contains(z)) out.add(z);
      }
    }
    return out;
  }

  String get _primaryConcern => _concerns.isNotEmpty ? _concerns.first : 'general';

  void _toggle(List<String> list, String v) => setState(() => list.contains(v) ? list.remove(v) : list.add(v));

  void _toggleConcernZone(String concernId, String zoneId) {
    setState(() {
      final list = [...?_concernZones[concernId]];
      list.contains(zoneId) ? list.remove(zoneId) : list.add(zoneId);
      if (list.isNotEmpty) {
        _concernZones[concernId] = list;
      } else {
        _concernZones.remove(concernId);
      }
    });
  }

  Future<void> _getLocation(Pack pack) async {
    setState(() {
      _locationLoading = true;
      _locationError = '';
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw Exception('disabled');
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) throw Exception('denied');
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 10)),
      );
      if (!mounted) return;
      setState(() {
        _lat = roundCoordinate(p.latitude);
        _lon = roundCoordinate(p.longitude);
        _locationSet = true;
        _locationLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locationError = pack.s('errors.locationFailed');
        _locationLoading = false;
      });
    }
  }

  Future<void> _pickPhoto(ImageSource source, CameraDevice camera) async {
    PickedPhoto? picked;
    try {
      picked = await pickSkinPhoto(source, camera: camera);
    } on PlatformException {
      return;
    }
    if (picked == null || !mounted) return;
    setState(() => _photo = picked);
    final q = await analyzeSkinPhotoQuality(picked.bytes);
    if (mounted && identical(_photo, picked)) setState(() => picked!.quality = q);
  }

  Future<void> _pickLastPeriodDate() async {
    final now = DateTime.now();
    final initial = _lastPeriodDate.isNotEmpty ? DateTime.parse(_lastPeriodDate) : now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      locale: Locale(I18n.instance.lang),
    );
    if (picked != null) setState(() => _lastPeriodDate = DateFormat('yyyy-MM-dd').format(picked));
  }

  Future<void> _submit(Pack pack) async {
    final user = context.read<AuthController>().user;
    final router = GoRouter.of(context);
    setState(() {
      _submitError = '';
      _loading = true;
    });
    try {
      String? photoUrl;
      String? photoPath;
      final photo = _photo;
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
            unawaited(ingestDailyTrackingEvent(user.id, 'photo_meta', {
              'context': _photoContext,
              'meanLuma': photo.quality?.meanLuma,
              'variance': photo.quality?.variance,
              'sharpnessApprox': photo.quality?.sharpnessApprox,
              'flow': 'analyze_full',
            }));
          }
        } catch (_) {
          if (mounted) setState(() => _submitError = pack.s('errors.photoUploadWarn'));
        }
      } else if (photo != null && client == null) {
        setState(() => _submitError = pack.s('errors.storageOffWarn'));
      }

      final primary = _primaryConcern;
      final sev = _severityScoresByConcern[primary];
      final anyFlag = _specialFlags.values.any((v) => v);
      final body = {
        'user_id': user?.id ?? demoUserId,
        'full_name': _name.text,
        'age': int.tryParse(_age.text.trim()),
        'gender': _gender,
        'concern': primary,
        'skin_type': _skinType.isEmpty ? 'normal' : _skinType,
        'severity_score': sev ?? 5,
        'water_intake': _waterIntake,
        'sleep_hours': _sleepHours,
        'stress_score': (pssScore(_pssAnswers) * 16 / 40).round(),
        'smoking': _smokingPerDay > 0,
        'smoking_per_day': _smokingPerDay,
        'smoking_years': _smokingYears,
        'alcohol': _alcoholFreq > 0,
        'alcohol_frequency': _alcoholFreq,
        'alcohol_amount': _alcoholAmt,
        'location_lat': _lat,
        'location_lon': _lon,
        'photo_url': photoPath,
        'is_pregnant': _hormonalStatus == 'pregnant',
        'cycle_phase': _cyclePhase,
        'acne_zones': _zones,
        'actives_experience': _activesExperience,
        'actives_tolerance': _activesTolerance,
        'makeup_frequency': _makeupFreq,
        'makeup_removal': _makeupFreq > 0 ? _makeupRemoval : 'cleanser',
        'special_flags': anyFlag ? _specialFlags : null,
      };
      final res = await apiPost('/generate_routine', body);
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
      router.go('/dashboard', extra: {
        'routine': data['routine'],
        'weather': data['weather'],
        'insights': data['holistic_insights'],
        'assessmentId': data['assessment_id'],
        'photoUrl': photoUrl ?? localPreview,
        'routineWithoutPhoto': photoUrl == null && localPreview == null,
        'userName': _name.text,
        'concern': primary,
        'flowDebug': data['flow_debug'],
        'safetyAbsoluteRules': data['safety_absolute_rules'],
        'ruleEnforcementReport': data['rule_enforcement_report'],
        'aiPolishNote': data['ai_polish_note'],
        'activePlan': data['active_plan'] is List ? data['active_plan'] : const [],
      });
    } catch (e) {
      if (mounted) {
        setState(() => _submitError = isNetworkError(e) ? pack.s('errors.networkError') : pack.s('errors.unexpectedError'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.photoOnly) return const AnalyzePhotoOnly();

    final i18n = context.i18n;
    final pack = Pack(i18n.analyzeWizardPack);
    final theme = context.watch<ThemeController>().theme;
    final user = context.watch<AuthController>().user;

    if (_loading) return const LoadingScreen();

    final uid = user?.id ?? demoUserId;
    if (!_forceFullWizard && hasCompletedOnboarding(uid)) return _compactHub(i18n, pack, theme);

    return ThemedPage(
      theme: theme,
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(16, 32, 16, 32 + MediaQuery.of(context).padding.bottom),
      children: [
        _progress(),
        const SizedBox(height: 24),
        if (_submitError.isNotEmpty) ...[_errorBox(i18n), const SizedBox(height: 20)],
        if (_step == 1) ..._step1(i18n, pack),
        if (_step == 2) ..._step2(i18n, pack),
        if (_step == 3) ..._step3(i18n, pack),
        if (_step == 4) ..._step4(i18n, pack),
      ],
    );
  }

  Widget _compactHub(I18n i18n, Pack pack, RebiTheme theme) {
    return ThemedPage(
      theme: theme,
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 40),
      children: [
        RCard(
          borderColor: theme.primaryLight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: GradientIconBox(icon: LucideIcons.sparkles, from: theme.accent, to: theme.primary, size: 64, iconSize: 32)),
              const SizedBox(height: 16),
              Text(i18n.t('analyze.routineReadyTitle'), textAlign: TextAlign.center, style: tx(20, w: 7)),
              const SizedBox(height: 16),
              Text(pack.s('compactHub.description'), textAlign: TextAlign.center, style: tx(14, c: Tw.gray600, h: relaxed)),
              const SizedBox(height: 24),
              PrimaryButton(
                onPressed: () => context.go('/dashboard'),
                color: theme.primary,
                label: pack.s('compactHub.backToDashboard'),
                trailingIcon: LucideIcons.arrowRight,
              ),
              const SizedBox(height: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => context.push('/dashboard/analyze?photo=1'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.primaryLight, width: 2),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.camera, size: 20, color: theme.primary),
                        const SizedBox(width: 8),
                        Flexible(child: Text(i18n.t('analyze.quickPhotoUpload'), style: tx(14, w: 6, c: theme.primary))),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SecondaryButton(
                onPressed: () {
                  setState(() {
                    _forceFullWizard = true;
                    _step = 1;
                  });
                },
                borderColor: theme.primaryLight,
                textColor: theme.primary,
                fontSize: 14,
                label: i18n.t('analyze.newAnalyzeFull'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _progress() {
    return Row(
      children: [
        for (final s in [1, 2, 3, 4]) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: s < _step ? Tw.teal500 : (s == _step ? null : Tw.gray200),
                gradient: s == _step ? LinearGradient(colors: [Tw.teal400, Tw.teal600]) : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Text('$_step/4', style: tx(12, c: Tw.gray400)),
      ],
    );
  }

  Widget _errorBox(I18n i18n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Tw.red50.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Tw.red200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: EdgeInsets.only(top: 2), child: Icon(LucideIcons.circleAlert, size: 20, color: Tw.red600)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i18n.t('analyze.generateFailedTitle'), style: tx(14, w: 6, c: Tw.red950)),
                const SizedBox(height: 4),
                Text(_submitError, style: tx(14, c: Tw.red900.withValues(alpha: .95), h: relaxed)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _submitError = ''),
            child: Text(i18n.t('common.close'), style: tx(12, w: 6, c: Tw.red700)),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) =>
      Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(text, style: tx(14, w: 5, c: Tw.gray700)));

  // ═══ ADIM 1: Temel ═══
  List<Widget> _step1(I18n i18n, Pack pack) {
    final periodNeeded = _isFemale && (_hormonalStatus == 'regular' || _hormonalStatus == 'irregular');
    final canContinue = _name.text.isNotEmpty && _age.text.isNotEmpty && _gender.isNotEmpty && !(periodNeeded && _lastPeriodDate.isEmpty);
    return [
      StepHeader(title: pack.s('step1.title'), subtitle: pack.s('step1.subtitle')),
      const SizedBox(height: 20),
      RCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _fieldLabel(pack.s('step1.nameLabel')),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: inputDecoration(hint: pack.s('step1.namePlaceholder'), prefixIcon: LucideIcons.user),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _fieldLabel(pack.s('step1.ageLabel')),
                      TextField(
                        controller: _age,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                        decoration: inputDecoration(hint: '25'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _fieldLabel(pack.s('step1.genderLabel')),
                      Row(
                        children: [
                          for (final g in ['female', 'male', 'other']) ...[
                            if (g != 'female') const SizedBox(width: 6),
                            Expanded(
                              child: ChoiceChipBox(
                                label: pack.or('gender.$g', g),
                                selected: _gender == g,
                                radius: 12,
                                center: true,
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
                                onTap: () => setState(() {
                                  _gender = g;
                                  if (g != 'female') _hormonalStatus = '';
                                }),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_locationSet)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Tw.teal50, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Icon(LucideIcons.circleCheck, size: 16, color: Tw.teal700),
                    const SizedBox(width: 8),
                    Expanded(child: Text(i18n.t('analyze.locationSet'), style: tx(12, c: Tw.teal700))),
                  ],
                ),
              )
            else
              SecondaryButton(
                onPressed: _locationLoading ? null : () => _getLocation(pack),
                loading: _locationLoading,
                icon: LucideIcons.mapPin,
                label: i18n.t('analyze.location'),
                fontSize: 14,
              ),
            if (_locationError.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(_locationError, style: tx(12, c: Tw.red500)),
            ],
          ],
        ),
      ),
      if (_isFemale) ...[
        const SizedBox(height: 20),
        RCard(
          borderColor: Tw.pink100,
          color: Color.alphaBlend(Tw.pink50.withValues(alpha: .2), Tw.surface),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CardTitle(icon: LucideIcons.heart, color: Tw.pink600, text: pack.s('step1.hormonalTitle'), size: 14),
              const SizedBox(height: 12),
              for (final pair in const [
                ['regular', 'irregular'],
                ['pregnant', 'menopause'],
              ]) ...[
                if (pair.first == 'pregnant') const SizedBox(height: 6),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final id in pair) ...[
                        if (id != pair.first) const SizedBox(width: 6),
                        Expanded(
                          child: ChoiceChipBox(
                            label: pack.s('step1.hormonal_$id'),
                            selected: _hormonalStatus == id,
                            radius: 12,
                            center: true,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            activeBorder: Tw.pink400,
                            activeBg: Tw.pink50,
                            activeText: Tw.pink800,
                            onTap: () => setState(() => _hormonalStatus = id),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (_hormonalStatus == 'regular' || _hormonalStatus == 'irregular') ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickLastPeriodDate,
                  borderRadius: BorderRadius.circular(16),
                  child: InputDecorator(
                    decoration: inputDecoration(suffix: Icon(LucideIcons.calendar, size: 18, color: Tw.gray400)),
                    child: Text(
                      _lastPeriodDate.isEmpty
                          ? (i18n.lang == 'en' ? 'mm/dd/yyyy' : 'gg.aa.yyyy')
                          : DateFormat.yMd(i18n.lang).format(DateTime.parse(_lastPeriodDate)),
                      style: tx(14, c: _lastPeriodDate.isEmpty ? Tw.gray400 : Tw.gray900),
                    ),
                  ),
                ),
                if (_hormonalStatus == 'regular') ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: RangeSlider1(
                          value: _cycleLength.toDouble(),
                          min: 21,
                          max: 35,
                          step: 1,
                          color: Tw.pink500,
                          onChanged: (v) => setState(() => _cycleLength = v.round()),
                        ),
                      ),
                      SizedBox(width: 40, child: Text('${_cycleLength}g', style: tx(12, w: 5, c: Tw.pink700))),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
      const SizedBox(height: 20),
      PrimaryButton(
        onPressed: canContinue ? () => _setStep(2) : null,
        label: i18n.t('analyze.continue'),
        trailingIcon: LucideIcons.arrowRight,
      ),
      if (periodNeeded && _lastPeriodDate.isEmpty) ...[
        const SizedBox(height: 8),
        Text(pack.s('step1.periodHint'), textAlign: TextAlign.center, style: tx(12, c: Tw.amber700)),
      ],
    ];
  }

  Widget _flagChip(String key, String label) => ChoiceChipBox(
        label: label,
        selected: _specialFlags[key] ?? false,
        activeText: Tw.teal800,
        inactiveText: Tw.gray600,
        onTap: () => setState(() => _specialFlags[key] = !(_specialFlags[key] ?? false)),
      );

  // ═══ ADIM 2: Cilt + Yaşam Tarzı ═══
  List<Widget> _step2(I18n i18n, Pack pack) {
    List<ChipOption<int>> numOpts(String path, List<int> ids) =>
        [for (final id in ids) ChipOption(id, pack.s('$path.$id'))];
    final packYears = (_smokingPerDay / 20 * _smokingYears).toStringAsFixed(1);

    return [
      StepHeader(title: pack.s('step2.title'), subtitle: pack.s('step2.subtitle')),
      const SizedBox(height: 20),
      RCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(i18n.t('analyze.skinType'), style: tx(14, w: 5, c: Tw.gray700)),
            const SizedBox(height: 12),
            SkinTypeVisual(value: _skinType, onChanged: (v) => setState(() => _skinType = v)),
          ],
        ),
      ),
      const SizedBox(height: 20),
      RCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(i18n.t('analyze.concerns'), style: tx(14, w: 5, c: Tw.gray700)),
            const SizedBox(height: 12),
            for (final (id, icon) in _concernDefs) ...[
              _concernButton(id, icon, pack.or('concern.$id', id)),
              if (_concerns.contains(id)) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(interpolate(pack.s('step2.zonesHint'), {'concern': pack.or('concern.$id', id)}),
                          style: tx(10, c: Tw.gray500)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final z in _zoneIds)
                            ChoiceChipBox(
                              label: pack.or('zone.$z', z),
                              selected: (_concernZones[id] ?? const []).contains(z),
                              onTap: () => _toggleConcernZone(id, z),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
      if (_concerns.contains('aging') || _concerns.contains('sensitivity')) ...[
        const SizedBox(height: 20),
        RCard(
          borderColor: Tw.slate100,
          color: Color.alphaBlend(Tw.slate50.withValues(alpha: .6), Tw.surface),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(pack.s('step2.clarifyTitle'), style: tx(12, w: 7, c: Tw.gray800)),
              if (_concerns.contains('aging')) ...[
                const SizedBox(height: 12),
                Text(pack.s('step2.agingIntro'), style: tx(11, c: Tw.gray600, h: relaxed)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _flagChip('frown_lines', pack.s('step2.aging_frown')),
                  _flagChip('eye_crows_feet', pack.s('step2.aging_crow')),
                  _flagChip('smile_lines', pack.s('step2.aging_smile')),
                ]),
              ],
              if (_concerns.contains('sensitivity')) ...[
                const SizedBox(height: 12),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: pack.s('step2.sensitivityIntro')),
                    TextSpan(text: ' ${pack.s('step2.sensitivityNote')}', style: tx(11, c: Tw.gray500)),
                  ]),
                  style: tx(11, c: Tw.gray600, h: relaxed),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _flagChip('redness_diffuse', pack.s('step2.redness_diffuse')),
                  _flagChip('redness_acne_marks', pack.s('step2.redness_acne_marks')),
                  _flagChip('cold_sensitive', pack.s('step2.cold_sensitive')),
                  _flagChip('stings_with_products', pack.s('step2.stings_products')),
                ]),
                const SizedBox(height: 8),
                Text(pack.s('step2.sensitivityFootnote'), style: tx(10, c: Tw.gray500, h: relaxed)),
              ],
            ],
          ),
        ),
      ],
      const SizedBox(height: 20),
      RCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CardTitle(
                    icon: LucideIcons.droplets,
                    color: Tw.blue500,
                    text: interpolate(pack.s('step2.waterLabel'), {'n': _waterIntake}),
                  ),
                  RangeSlider1(
                    value: _waterIntake,
                    min: .5,
                    max: 4,
                    step: .5,
                    color: Tw.blue500,
                    onChanged: (v) => setState(() => _waterIntake = v),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CardTitle(
                    icon: LucideIcons.moon,
                    color: Tw.indigo500,
                    text: interpolate(pack.s('step2.sleepLabel'), {'n': _sleepHours}),
                  ),
                  RangeSlider1(
                    value: _sleepHours,
                    min: 3,
                    max: 12,
                    step: .5,
                    color: Tw.indigo500,
                    onChanged: (v) => setState(() => _sleepHours = v),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      RCard(
        borderColor: Tw.purple100,
        color: Color.alphaBlend(Tw.purple50.withValues(alpha: .2), Tw.surface),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Tw.purple100, borderRadius: BorderRadius.circular(8)),
                  child: const Text('🧠', style: TextStyle(fontSize: 14)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pack.s('step2.pssTitle'), style: tx(12, w: 7)),
                      Text(pack.s('step2.pssSubtitle'), style: tx(10, c: Tw.gray500)),
                    ],
                  ),
                ),
              ],
            ),
            for (var i = 0; i < pack.list('pss10').length && i < 10; i++) ...[
              const SizedBox(height: 16),
              Text(pack.list('pss10')[i].toString(), style: tx(12, c: Tw.gray700)),
              const SizedBox(height: 4),
              RangeSlider1(
                value: _pssAnswers[i].toDouble(),
                min: 0,
                max: 4,
                step: 1,
                color: Tw.purple500,
                onChanged: (v) => setState(() => _pssAnswers[i] = v.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(child: Text(pack.s('step2.scaleNever'), style: tx(9, c: Tw.gray400))),
                  Flexible(child: Text(pack.s('step2.scaleOften'), textAlign: TextAlign.right, style: tx(9, c: Tw.gray400))),
                ],
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 20),
      RCard(
        borderColor: Tw.amber100,
        color: Color.alphaBlend(Tw.amber50.withValues(alpha: .1), Tw.surface),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardTitle(icon: LucideIcons.cigarette, color: Tw.amber700, text: pack.s('step2.smokingTitle')),
            const SizedBox(height: 12),
            ChipSelect<int>(
              options: numOpts('smokingAmount', const [0, 1, 5, 15, 25]),
              value: _smokingPerDay,
              onChanged: (v) => setState(() => _smokingPerDay = v),
              cols: 3,
            ),
            if (_smokingPerDay > 0) ...[
              const SizedBox(height: 12),
              Text(pack.s('step2.smokingYears'), style: tx(10, c: Tw.gray500)),
              const SizedBox(height: 8),
              ChipSelect<int>(
                options: numOpts('smokingYears', const [0, 2, 5, 10, 20]),
                value: _smokingYears,
                onChanged: (v) => setState(() => _smokingYears = v),
                cols: 3,
              ),
              if (_smokingYears > 0) ...[
                const SizedBox(height: 8),
                Text(interpolate(pack.s('step2.packYears'), {'n': packYears}), style: tx(10, w: 5, c: Tw.red600)),
              ],
            ],
          ],
        ),
      ),
      const SizedBox(height: 20),
      RCard(
        borderColor: Tw.purple100,
        color: Color.alphaBlend(Tw.purple50.withValues(alpha: .1), Tw.surface),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardTitle(icon: LucideIcons.wine, color: Tw.purple700, text: pack.s('step2.alcoholTitle')),
            const SizedBox(height: 12),
            ChipSelect<int>(
              options: numOpts('alcoholFreq', const [0, 1, 3, 5, 7]),
              value: _alcoholFreq,
              onChanged: (v) => setState(() => _alcoholFreq = v),
              cols: 3,
            ),
            if (_alcoholFreq > 0) ...[
              const SizedBox(height: 12),
              Text(pack.s('step2.alcoholSession'), style: tx(10, c: Tw.gray500)),
              const SizedBox(height: 8),
              ChipSelect<int>(
                options: numOpts('alcoholAmt', const [1, 2, 4, 6]),
                value: _alcoholAmt,
                onChanged: (v) => setState(() => _alcoholAmt = v),
                cols: 2,
              ),
              const SizedBox(height: 8),
              Text(interpolate(pack.s('step2.alcoholWeekly'), {'n': _alcoholFreq * _alcoholAmt}),
                  style: tx(10, c: Tw.purple600)),
            ],
          ],
        ),
      ),
      const SizedBox(height: 20),
      RCard(
        borderColor: Tw.green100,
        color: Color.alphaBlend(Tw.green50.withValues(alpha: .1), Tw.surface),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardTitle(icon: LucideIcons.utensilsCrossed, color: Tw.green700, text: pack.s('step2.nutritionTitle')),
            for (final key in const ['fastfood', 'sugar', 'dairy', 'veggies']) ...[
              const SizedBox(height: 12),
              Text(pack.or('nutrition.$key.label', key), style: tx(10, w: 5, c: Tw.gray600)),
              const SizedBox(height: 4),
              Builder(builder: (context) {
                final opts = pack.map('nutrition.$key.opts');
                final list = [for (final e in opts.entries) ChipOption(int.parse(e.key), e.value.toString())];
                return ChipSelect<int>(
                  options: list,
                  value: _nutrition[key]!,
                  onChanged: (v) => setState(() => _nutrition[key] = v),
                  cols: list.isEmpty ? 1 : list.length,
                );
              }),
            ],
          ],
        ),
      ),
      const SizedBox(height: 20),
      RCard(
        borderColor: Tw.pink100,
        color: Color.alphaBlend(Tw.pink50.withValues(alpha: .1), Tw.surface),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardTitle(icon: LucideIcons.palette, color: Tw.pink700, text: pack.s('step2.makeupTitle')),
            const SizedBox(height: 12),
            Text(pack.s('step2.makeupFreqQ'), style: tx(10, w: 5, c: Tw.gray600)),
            const SizedBox(height: 4),
            ChipSelect<int>(
              options: numOpts('makeup.frequency', const [0, 1, 3, 5]),
              value: _makeupFreq,
              onChanged: (v) => setState(() => _makeupFreq = v),
            ),
            if (_makeupFreq > 0) ...[
              const SizedBox(height: 12),
              Text(pack.s('step2.makeupRemovalQ'), style: tx(10, w: 5, c: Tw.gray600)),
              const SizedBox(height: 4),
              ChipSelect<String>(
                options: [
                  for (final id in const ['none', 'water', 'cleanser', 'double'])
                    ChipOption(id, pack.or('makeup.removal.$id', id)),
                ],
                value: _makeupRemoval,
                onChanged: (v) => setState(() => _makeupRemoval = v),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 20),
      BackNextRow(
        backLabel: i18n.t('common.back'),
        onBack: () => _setStep(1),
        nextLabel: i18n.t('common.continue'),
        nextIcon: LucideIcons.arrowRight,
        onNext: _skinType.isEmpty
            ? null
            : () {
                _step3Section = 0;
                // Yüz sorunu seçilmediyse yine de cilt tipine göre rutin üretilir.
                _setStep(_concerns.isEmpty ? 4 : 3);
              },
      ),
    ];
  }

  Widget _concernButton(String id, String icon, String label) {
    final active = _concerns.contains(id);
    return Material(
      color: active ? Tw.teal50 : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _toggle(_concerns, id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? Tw.teal500 : Tw.gray200, width: 2),
          ),
          child: Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: tx(14, w: active ? 5 : 4, c: active ? Tw.teal800 : Tw.gray600))),
              if (active) Icon(LucideIcons.circleCheck, size: 16, color: Tw.teal500),
            ],
          ),
        ),
      ),
    );
  }

  Widget _multiChips(Pack pack, String path, List<String> ids, List<String> selected) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final id in ids)
            ChoiceChipBox(
              label: pack.or('$path.$id', id),
              selected: selected.contains(id),
              radius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              onTap: () => _toggle(selected, id),
            ),
        ],
      );

  // ═══ ADIM 3: Kullanım soruları ═══
  List<Widget> _step3(I18n i18n, Pack pack) {
    final back = i18n.t('common.back');
    final cont = i18n.t('common.continue');
    switch (_step3Section) {
      case 0:
        return [
          StepHeader(title: pack.s('step3.activesTitle'), subtitle: pack.s('step3.activesSubtitle')),
          const SizedBox(height: 20),
          RCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(pack.s('step3.experienceLabel'), style: tx(14, w: 5, c: Tw.gray700)),
                const SizedBox(height: 12),
                ChipSelect<String>(
                  options: [
                    for (final id in const ['none', 'occasional', 'regular'])
                      ChipOption(id, pack.or('activesExperience.$id', id)),
                  ],
                  value: _activesExperience,
                  onChanged: (v) => setState(() => _activesExperience = v),
                  cols: 1,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          BackNextRow(backLabel: back, onBack: () => _setStep(2), nextLabel: cont, nextIcon: LucideIcons.arrowRight, onNext: () => _setSection(1)),
        ];
      case 1:
        return [
          StepHeader(title: pack.s('step3.severityTitle'), subtitle: pack.s('step3.severitySubtitle')),
          const SizedBox(height: 20),
          for (final c in _concerns)
            SeverityTest(
              key: ValueKey('sev-$c'),
              concern: c,
              onScoreChange: (score) => setState(() => _severityScoresByConcern[c] = score),
            ),
          RCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(pack.s('step3.durationLabel'), style: tx(14, w: 5, c: Tw.gray700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final id in const ['1-3', '3-6', '6-12', '1y+'])
                      ChoiceChipBox(
                        label: pack.or('duration.$id', id),
                        selected: _duration == id,
                        radius: 12,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        onTap: () => setState(() => _duration = id),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          BackNextRow(backLabel: back, onBack: () => _setSection(0), nextLabel: cont, nextIcon: LucideIcons.arrowRight, onNext: () => _setSection(2)),
        ];
      case 2:
        return [
          StepHeader(title: pack.s('step3.triggersTitle'), subtitle: pack.s('step3.triggersSubtitle')),
          const SizedBox(height: 20),
          RCard(child: _multiChips(pack, 'trigger', const ['stress', 'period', 'sun', 'food', 'season', 'cold', 'heat', 'other'], _triggers)),
          const SizedBox(height: 20),
          BackNextRow(backLabel: back, onBack: () => _setSection(1), nextLabel: cont, nextIcon: LucideIcons.arrowRight, onNext: () => _setSection(3)),
        ];
      case 3:
        return [
          StepHeader(title: pack.s('step3.pastTitle'), subtitle: pack.s('step3.pastSubtitle')),
          const SizedBox(height: 20),
          RCard(child: _multiChips(pack, 'pastTreatment', const ['none', 'cleanser', 'moisturizer', 'rx', 'derm', 'otc'], _pastTreatments)),
          const SizedBox(height: 20),
          BackNextRow(backLabel: back, onBack: () => _setSection(2), nextLabel: cont, nextIcon: LucideIcons.arrowRight, onNext: () => _setSection(4)),
        ];
      default:
        return [
          StepHeader(title: pack.s('step3.expectationsTitle'), subtitle: pack.s('step3.expectationsSubtitle')),
          const SizedBox(height: 20),
          RCard(
            child: _multiChips(
                pack, 'expectation', const ['acne_less', 'spots_less', 'clean_skin', 'hydration', 'aging_slow', 'comfort'], _expectations),
          ),
          const SizedBox(height: 20),
          BackNextRow(
            backLabel: back,
            onBack: () => _setSection(3),
            nextLabel: i18n.t('analyze.continue'),
            nextIcon: LucideIcons.arrowRight,
            onNext: () => _setStep(4),
          ),
        ];
    }
  }

  // ═══ ADIM 4: Fotoğraf + Rutin oluştur ═══
  List<Widget> _step4(I18n i18n, Pack pack) {
    final sev = _severityScoresByConcern[_primaryConcern];
    final concernLabels = _concerns.map((c) => pack.or('concern.$c', c)).join(', ');
    Widget summaryCell(String label, String value) => Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Tw.surface, borderRadius: BorderRadius.circular(8)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: tx(11, c: Tw.gray400)),
              Text(value, style: tx(11, w: 5)),
            ],
          ),
        );

    return [
      StepHeader(
        title: i18n.t('analyze.finalStep'),
        subtitle: interpolate(pack.s('step4.finalLead'), {
          'tracking': pack.s('step4.final_tracking'),
          'recommended': pack.s('step4.final_recommended'),
        }),
      ),
      const SizedBox(height: 20),
      RCard(
        child: PhotoPickerCard(
          photo: _photo,
          photoContext: _photoContext,
          changeLabel: pack.s('step4.changePhoto'),
          onPick: _pickPhoto,
          onClear: () => setState(() => _photo = null),
          onContextChanged: (v) => setState(() => _photoContext = v),
          header: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Tw.amber50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Tw.amber100),
              ),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: pack.s('step4.tipTitle'), style: tx(11, w: 6, c: Tw.amber900)),
                  TextSpan(text: ' ${pack.s('step4.tipBody')}'),
                ]),
                style: tx(11, c: Tw.amber900.withValues(alpha: .95), h: relaxed),
              ),
            ),
            const SizedBox(height: 12),
            Text(pack.s('step4.modeHint'), style: tx(11, c: Tw.gray500, h: relaxed)),
            const SizedBox(height: 12),
          ],
        ),
      ),
      const SizedBox(height: 20),
      RCard(
        borderColor: Tw.teal100,
        color: Color.alphaBlend(Tw.teal50.withValues(alpha: .5), Tw.surface),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(LucideIcons.sparkles, size: 12, color: Tw.teal800),
                const SizedBox(width: 4),
                Expanded(child: Text(pack.s('step4.summaryTitle'), style: tx(12, w: 7, c: Tw.teal800))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: summaryCell(pack.s('step4.age'), _age.text)),
                const SizedBox(width: 6),
                Expanded(child: summaryCell(pack.s('step4.skin'), _skinType)),
                const SizedBox(width: 6),
                Expanded(child: summaryCell(pack.s('step4.severity'), '${sev ?? '?'}/10')),
              ],
            ),
            const SizedBox(height: 6),
            summaryCell(pack.s('step4.concerns'), concernLabels),
          ],
        ),
      ),
      const SizedBox(height: 20),
      RCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(pack.s('modal.toleranceExplTitle'), style: tx(14, w: 6)),
            const SizedBox(height: 12),
            Text(pack.s('modal.toleranceExplBody'), style: tx(11, c: Tw.gray500, h: relaxed)),
            for (final fam in strongActiveFamilyIds) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Tw.gray50.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Tw.gray200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(pack.or('strongFamily.$fam', fam), style: tx(12, w: 5, c: Tw.gray800)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final lv in const ['never', 'good', 'mild', 'bad'])
                          ChoiceChipBox(
                            label: pack.or('tolerance.$lv', lv),
                            selected: _activesTolerance[fam] == lv,
                            radius: 8,
                            fontSize: 10,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            activeText: Tw.teal900,
                            inactiveText: Tw.gray600,
                            inactiveBg: Tw.surface,
                            onTap: () => setState(() => _activesTolerance[fam] = lv),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 20),
      const AiDisclaimer(),
      const SizedBox(height: 20),
      BackNextRow(
        backLabel: i18n.t('common.back'),
        onBack: () => _setStep(3),
        nextLabel: pack.s('step4.createRoutineCta'),
        nextLeadingIcon: LucideIcons.sparkles,
        onNext: () => _submit(pack),
      ),
      if (_photo == null) ...[
        const SizedBox(height: 20),
        Text(pack.s('step4.noPhotoNote'), textAlign: TextAlign.center, style: tx(11, c: Tw.gray500)),
      ],
    ];
  }
}
