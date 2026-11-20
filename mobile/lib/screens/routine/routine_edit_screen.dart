import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/demo_user.dart';
import '../../core/i18n.dart';
import '../../core/routine_edits.dart';
import '../../core/routine_logic.dart';
import '../../core/routine_tracking.dart';
import '../../state/auth_controller.dart';
import '../../state/theme_controller.dart';
import '../../ui/shell/page_stage.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/app_sheet.dart';
import '../../ui/widgets/common.dart';

/// "Rutinimi kendime göre düzenle" (`PUT /routine/active`).
///
/// Geri bildirim: "kendim de bir rutin yapabileyim, onun üstüne AI önerebilirsin ya da AI önerdiğinin
/// üzerinde değişiklikler yapabileyim". Rebi'nin ürettiği adımların metni burada değişmez — kullanıcı
/// yapmayacağı adımı plandan çıkarır (geri alınabilir) ve kendi adımlarını ekler. Değişiklikler
/// kaydedilene kadar sunucuya gitmez; kaydedilince bugünün planı ve hatırlatıcılar da buna uyar.
class RoutineEditScreen extends StatefulWidget {
  const RoutineEditScreen({super.key});

  @override
  State<RoutineEditScreen> createState() => _RoutineEditScreenState();
}

class _RoutineEditScreenState extends State<RoutineEditScreen> {
  late final String? _uid = context.read<AuthController>().user?.id;

  /// Motorun ürettiği adımlar (çıkarılanlar dâhil), geldiği sırada.
  List<RoutineItem> _engineSteps = const [];

  /// Kullanıcının kendi adımları.
  List<UserRoutineStep> _userSteps = [];

  /// Şu an plandan çıkarılmış adımların kimlikleri.
  Set<String> _hidden = {};

  Set<String> _savedHidden = {};
  List<UserRoutineStep> _savedUserSteps = const [];

  bool _loading = true;
  bool _failed = false;
  bool _saving = false;
  bool _showSaved = false;
  String? _error;
  Timer? _savedTimer;

  bool get _real => _uid != null && _uid != demoUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _savedTimer?.cancel();
    super.dispose();
  }

  /// Sunucudaki rutin + çıkarılanlar; ağ yoksa cihazdaki kopya gösterilir (düzenleme kaydedilemez).
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    RoutineEditsResult? loaded;
    if (_real) {
      try {
        loaded = await fetchRoutineWithSkipped(_uid!);
      } catch (_) {
        loaded = null;
      }
    }
    if (!mounted) return;
    final items = loaded == null ? asRoutine(getRoutineSnapshot(_uid)?['routine']) : [...loaded.routine, ...loaded.skipped];
    setState(() {
      _loading = false;
      _failed = loaded == null;
      _apply(items);
    });
  }

  void _apply(List<RoutineItem> items) {
    _engineSteps = items.where((i) => !isUserStep(i)).toList();
    _userSteps = items.where(isUserStep).map(UserRoutineStep.fromItem).toList();
    _hidden = {for (final i in _engineSteps.where(isSkippedByUser)) routineStepKey(i)};
    _savedHidden = {..._hidden};
    _savedUserSteps = [..._userSteps];
  }

  bool get _dirty {
    if (!setEquals(_hidden, _savedHidden)) return true;
    if (_userSteps.length != _savedUserSteps.length) return true;
    for (var i = 0; i < _userSteps.length; i++) {
      final a = _userSteps[i];
      final b = _savedUserSteps[i];
      if (a.action != b.action || a.time != b.time || a.detail != b.detail) return true;
    }
    return false;
  }

  /// Rutinde yürürlükte kalan adım sayısı (hepsi çıkarılamaz: plan boşalırsa ekranın anlamı kalmaz).
  int get _keptCount => _engineSteps.length - _hidden.length + _userSteps.length;

  void _change(VoidCallback fn) => setState(() {
        fn();
        _error = null;
        _showSaved = false;
      });

  Future<void> _save() async {
    if (!_real || _saving || !_dirty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final res = await saveRoutineEdits(_uid!, hidden: _hidden, added: _userSteps);
    if (!mounted) return;
    final result = res.result;
    if (result == null) {
      setState(() {
        _saving = false;
        _error = (res.error ?? '').isEmpty ? I18n.instance.t('mobileRoutineEdit.saveFailed') : res.error;
      });
      return;
    }
    // Cihazdaki kopya da güncellenir: panel ağ olmadan da düzenlenmiş planı gösterir.
    await saveRoutineSnapshot(_uid, {'routine': result.routine});
    if (!mounted) return;
    setState(() {
      _saving = false;
      _showSaved = true;
      _apply([...result.routine, ...result.skipped]);
    });
    _savedTimer?.cancel();
    _savedTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showSaved = false);
    });
  }

  Future<void> _addStep() async {
    final added = await _userStepSheet();
    if (added == null || !mounted) return;
    _change(() => _userSteps = [..._userSteps, added]);
  }

  Future<void> _editStep(int index) async {
    final edited = await _userStepSheet(initial: _userSteps[index]);
    if (edited == null || !mounted) return;
    _change(() {
      final next = [..._userSteps];
      next[index] = edited;
      _userSteps = next;
    });
  }

  /// Kendi adımı için ad, zaman ve kısa not. Boş ad kaydedilmez.
  Future<UserRoutineStep?> _userStepSheet({UserRoutineStep? initial}) {
    final i18n = I18n.instance;
    return AppSheet.show<UserRoutineStep>(
      context,
      title: i18n.t(initial == null ? 'mobileRoutineEdit.addTitle' : 'mobileRoutineEdit.editTitle'),
      subtitle: i18n.t('mobileRoutineEdit.addBody'),
      body: (ctx) => _UserStepForm(initial: initial),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = context.watch<ThemeController>().theme;

    return StagePage(
      theme: theme,
      title: i18n.t('mobileRoutineEdit.title'),
      subtitle: i18n.t('mobileRoutineEdit.subtitle'),
      backTo: '/dashboard/routine',
      bottomBar: _saveBar(i18n, theme),
      children: [
        if (_loading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: RingSpinner()))
        else if (!_real)
          NoticeBox(
            text: i18n.t('mobileRoutineEdit.notSynced'),
            bg: Tw.amber50,
            border: Tw.amber200,
            fg: Tw.amber900,
            icon: LucideIcons.info,
            fontSize: 12,
          )
        else if (_engineSteps.isEmpty && _userSteps.isEmpty)
          NoticeBox(
            text: i18n.t('mobileRoutineEdit.noRoutine'),
            bg: Tw.amber50,
            border: Tw.amber200,
            fg: Tw.amber900,
            icon: LucideIcons.info,
            fontSize: 12,
          )
        else ...[
          if (_failed) ...[
            NoticeBox(
              text: i18n.t('mobileRoutineEdit.offline'),
              bg: Tw.amber50,
              border: Tw.amber200,
              fg: Tw.amber900,
              icon: LucideIcons.wifiOff,
              fontSize: 12,
            ),
            const SizedBox(height: 14),
          ],
          NoticeBox(
            text: i18n.t('mobileRoutineEdit.hint'),
            bg: Tw.surface,
            border: Tw.gray200,
            fg: Tw.gray600,
            icon: LucideIcons.info,
            fontSize: 12,
          ),
          const SizedBox(height: 14),
          _engineCard(i18n, theme),
          const SizedBox(height: 16),
          _userCard(i18n, theme),
        ],
      ],
    );
  }

  Widget _engineCard(I18n i18n, RebiTheme theme) {
    return RCard(
      padding: const EdgeInsets.all(16),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(i18n.t('mobileRoutineEdit.rebiSteps'), style: tx(14, w: 7, c: Tw.gray800)),
          const SizedBox(height: 2),
          Text(i18n.t('mobileRoutineEdit.rebiStepsHint'), style: tx(12, c: Tw.gray500, h: snug)),
          const SizedBox(height: 10),
          for (var i = 0; i < _engineSteps.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _stepRow(i18n, theme, _engineSteps[i]),
          ],
        ],
      ),
    );
  }

  Widget _stepRow(I18n i18n, RebiTheme theme, RoutineItem item) {
    final key = routineStepKey(item);
    final kept = !_hidden.contains(key);
    final action = pickAction(item, localized: i18n.prefersLocalized);
    final time = str(item['time']);
    // Son adım da çıkarılamaz: plan tamamen boşalmasın.
    final canDrop = !kept || _keptCount > 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action,
                  style: tx(13.5, w: 6, c: kept ? Tw.gray900 : Tw.gray400, h: snug).copyWith(
                    decoration: kept ? null : TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  kept ? time : '$time · ${i18n.t('mobileRoutineEdit.dropped')}',
                  style: tx(11.5, w: 5, c: Tw.gray500),
                ),
              ],
            ),
          ),
          Semantics(
            label: action,
            child: Switch(
              key: Key('step-$key'),
              value: kept,
              onChanged: canDrop
                  ? (on) => _change(() => on ? _hidden.remove(key) : _hidden.add(key))
                  : null,
              activeThumbColor: Colors.white,
              activeTrackColor: theme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _userCard(I18n i18n, RebiTheme theme) {
    final full = _userSteps.length >= maxUserSteps;
    return RCard(
      padding: const EdgeInsets.all(16),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(i18n.t('mobileRoutineEdit.mySteps'), style: tx(14, w: 7, c: Tw.gray800)),
          const SizedBox(height: 2),
          Text(i18n.t('mobileRoutineEdit.myStepsHint'), style: tx(12, c: Tw.gray500, h: snug)),
          const SizedBox(height: 10),
          if (_userSteps.isEmpty)
            Text(i18n.t('mobileRoutineEdit.myStepsEmpty'), style: tx(12.5, c: Tw.gray500, h: relaxed))
          else
            for (var i = 0; i < _userSteps.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _userRow(i18n, theme, i),
            ],
          const SizedBox(height: 12),
          SecondaryButton(
            key: const Key('add-user-step'),
            icon: LucideIcons.plus,
            label: i18n.t('mobileRoutineEdit.addStep'),
            onPressed: full ? null : _addStep,
          ),
          if (full) ...[
            const SizedBox(height: 8),
            Text(i18n.t('mobileRoutineEdit.myStepsFull', {'n': maxUserSteps}), style: tx(11.5, c: Tw.gray500, h: snug)),
          ],
        ],
      ),
    );
  }

  Widget _userRow(I18n i18n, RebiTheme theme, int index) {
    final step = _userSteps[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.action, style: tx(13.5, w: 6, c: Tw.gray900, h: snug)),
                const SizedBox(height: 2),
                Text(
                  [i18n.t('mobileRoutineEdit.time.${step.time}', const {}, step.time), if (step.detail.isNotEmpty) step.detail].join(' · '),
                  style: tx(11.5, w: 5, c: Tw.gray500, h: snug),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: i18n.t('mobileRoutineEdit.editTitle'),
            onPressed: () => _editStep(index),
            icon: Icon(LucideIcons.pencil, size: 17, color: Tw.gray500),
          ),
          IconButton(
            key: Key('remove-user-step-$index'),
            tooltip: i18n.t('mobileRoutineEdit.removeStep'),
            onPressed: () => _change(() => _userSteps = [..._userSteps]..removeAt(index)),
            icon: Icon(LucideIcons.trash2, size: 17, color: Tw.red600),
          ),
        ],
      ),
    );
  }

  Widget? _saveBar(I18n i18n, RebiTheme theme) {
    final visible = _real && !_loading && (_dirty || _saving || _showSaved || _error != null);
    if (!visible) return null;
    return StageBottomBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            NoticeBox(text: _error!, bg: Tw.red50, border: Tw.red200, fg: Tw.red700, icon: LucideIcons.circleAlert, fontSize: 12.5),
            const SizedBox(height: 8),
          ],
          if (_showSaved) ...[
            StatusLine(ok: true, text: i18n.t('mobileRoutineEdit.saved')),
            const SizedBox(height: 8),
          ],
          PrimaryButton(
            key: const Key('routine-edit-save'),
            color: theme.primary,
            loading: _saving,
            label: i18n.t('mobileRoutineEdit.save'),
            onPressed: _dirty ? _save : null,
          ),
        ],
      ),
    );
  }
}

/// Kendi adımının formu. Yazı denetleyicileri bu parçaya aittir: sayfa kapanma animasyonu
/// biterken hâlâ kullanıldıkları için `whenComplete` ile değil, `dispose` ile bırakılırlar.
class _UserStepForm extends StatefulWidget {
  const _UserStepForm({this.initial});

  final UserRoutineStep? initial;

  @override
  State<_UserStepForm> createState() => _UserStepFormState();
}

class _UserStepFormState extends State<_UserStepForm> {
  late final TextEditingController _action = TextEditingController(text: widget.initial?.action ?? '');
  late final TextEditingController _detail = TextEditingController(text: widget.initial?.detail ?? '');
  late String _time = widget.initial?.time ?? 'Sabah';

  @override
  void dispose() {
    _action.dispose();
    _detail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = context.watch<ThemeController>().theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('user-step-action'),
          controller: _action,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [LengthLimitingTextInputFormatter(maxUserStepActionChars)],
          decoration: InputDecoration(
            labelText: i18n.t('mobileRoutineEdit.actionLabel'),
            hintText: i18n.t('mobileRoutineEdit.actionHint'),
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final t in userStepTimes)
              ChoiceChipBox(
                label: i18n.t('mobileRoutineEdit.time.$t', const {}, t),
                selected: _time == t,
                onTap: () => setState(() => _time = t),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('user-step-detail'),
          controller: _detail,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [LengthLimitingTextInputFormatter(maxUserStepDetailChars)],
          decoration: InputDecoration(
            labelText: i18n.t('mobileRoutineEdit.detailLabel'),
            hintText: i18n.t('mobileRoutineEdit.detailHint'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          key: const Key('user-step-save'),
          color: theme.primary,
          label: i18n.t('mobileRoutineEdit.addSave'),
          onPressed: _action.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(
                    UserRoutineStep(action: _action.text.trim(), time: _time, detail: _detail.text.trim()),
                  ),
        ),
      ],
    );
  }
}
