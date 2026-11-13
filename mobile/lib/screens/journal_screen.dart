import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/daily_tracking.dart';
import '../core/haptics.dart';
import '../core/i18n.dart';
import '../core/image_quality.dart';
import '../core/privacy_preferences.dart';
import '../core/skin_photos.dart';
import '../state/auth_controller.dart';
import '../state/theme_controller.dart';
import '../ui/brand/palette.dart';
import '../ui/components/photo_picker.dart';
import '../ui/shell/page_stage.dart';
import '../ui/tw.dart';
import '../ui/widgets/app_sheet.dart';
import '../ui/widgets/common.dart';

/// Testler sistem kamerası yerine bunu takar.
Future<PickedPhoto?> Function(ImageSource source) journalPhotoPicker =
    (source) => pickSkinPhoto(source, camera: CameraDevice.front);

/// Cilt günlüğü: haftada bir fotoğraf ve önce/sonra karşılaştırması.
///
/// Tasarım dili: tek odak. Üstte iki fotoğraf üst üste, ortadaki kaydırıcıyla karşılaştırılır (ilk fotoğraf = "önce",
/// seçilen = "sonra"); altında kaç gün arayla çekildikleri. Ardından haftalık çekim düğmesi (zamanı gelmediyse ikincil,
/// bir sonraki günü söyler) ve tüm fotoğrafların küçük resimleri. Yüz fotoğrafı özel nitelikli veridir: kullanıcının
/// "fotoğraf saklama" izni yoksa önce o istenir.
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  bool _loading = true;
  bool _busy = false;
  bool? _photoAllowed;
  bool _locationAllowed = false;
  String _error = '';
  String _notice = '';
  List<SkinPhoto> _photos = const [];

  /// Karşılaştırmada "sonra" olan fotoğrafın sırası (`_photos` yeniden eskiye; 0 = en yeni).
  int _after = 0;

  String? get _uid => context.read<AuthController>().user?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final prefs = await getPrivacyPreferences(uid);
      _photoAllowed = prefs['photo_processing_allowed'] == true;
      _locationAllowed = prefs['location_processing_allowed'] == true;
    } catch (_) {
      // İzin okunamazsa (ağ yok) fotoğraflar yine listelenir; yükleme denemesi sunucunun cevabına kalır.
      _photoAllowed ??= true;
    }
    try {
      final photos = _photoAllowed == true ? await skinPhotoStore.list(uid) : const <SkinPhoto>[];
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _after = 0;
      });
    } catch (_) {
      if (mounted) setState(() => _error = I18n.instance.t('mobileJournal.error'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _allowPhotos() async {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _busy = true);
    try {
      await updatePrivacyPreferences(uid, location: _locationAllowed, photo: true);
      if (!mounted) return;
      setState(() => _photoAllowed = true);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openCapture() async {
    final i18n = I18n.instance;
    final source = await AppSheet.show<ImageSource>(
      context,
      title: i18n.t('mobileJournal.tipsTitle'),
      body: (ctx) => _CaptureTips(theme: context.read<ThemeController>().theme),
    );
    if (source == null || !mounted) return;
    await _capture(source);
  }

  Future<void> _capture(ImageSource source) async {
    final uid = _uid;
    if (uid == null) return;
    final i18n = I18n.instance;
    PickedPhoto? photo;
    try {
      photo = await journalPhotoPicker(source);
    } on PlatformException {
      return;
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
      return;
    }
    if (photo == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = '';
      _notice = '';
    });
    try {
      final quality = await analyzeSkinPhotoQuality(photo.bytes);
      await skinPhotoStore.upload(uid, File(photo.file.path), photo.extension);
      await ingestDailyTrackingEvent(uid, 'photo_meta', {
        'context': 'journal',
        'meanLuma': quality.meanLuma,
        'variance': quality.variance,
        'sharpnessApprox': quality.sharpnessApprox,
        'flow': 'journal',
      });
      Haptics.success();
      final issue = quality.tooDark ? i18n.t('mobileJournal.dark') : (quality.tooBlurry ? i18n.t('mobileJournal.blurry') : '');
      _notice = issue.isEmpty ? i18n.t('mobileJournal.saved') : i18n.t('mobileJournal.retake', {'issue': issue});
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = i18n.t('mobileJournal.uploadFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = context.watch<ThemeController>().theme;
    return StagePage(
      theme: theme,
      title: i18n.t('mobileJournal.title'),
      subtitle: i18n.t('mobileJournal.subtitle'),
      backTo: '/dashboard/profile',
      onRefresh: _load,
      children: [
        RCard(
          padding: const EdgeInsets.all(18),
          radius: 24,
          child: _main(i18n, theme),
        ),
        if (_photos.length > 1) ...[
          const SizedBox(height: 16),
          RCard(
            padding: const EdgeInsets.fromLTRB(18, 16, 0, 16),
            radius: 24,
            child: _timeline(i18n, theme),
          ),
        ],
      ],
    );
  }

  Widget _main(I18n i18n, RebiTheme theme) {
    if (_loading) {
      return SizedBox(height: 220, child: Center(child: CircularProgressIndicator(color: theme.primary)));
    }
    if (_photoAllowed == false) return _consent(i18n, theme);
    final df = DateFormat.MMMd(i18n.lang);
    final children = <Widget>[];
    if (_photos.length >= 2) {
      final before = _photos.last;
      final after = _photos[_after.clamp(0, _photos.length - 2)];
      final days = (before.takenAt != null && after.takenAt != null) ? after.takenAt!.difference(before.takenAt!).inDays : null;
      children.addAll([
        _CompareView(
          before: before,
          after: after,
          beforeLabel: '${i18n.t('mobileJournal.before')} · ${_date(df, before)}',
          afterLabel: '${i18n.t('mobileJournal.after')} · ${_date(df, after)}',
          semanticsLabel: i18n.t('mobileJournal.a11yCompare', {'before': _date(df, before), 'after': _date(df, after)}),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(LucideIcons.moveHorizontal, size: 16, color: Tw.gray500),
            const SizedBox(width: 6),
            Expanded(child: Text(i18n.t('mobileJournal.compareHint'), style: tx(12.5, c: Tw.gray500))),
            if (days != null && days > 0) Text(i18n.t('mobileJournal.apart', {'n': days}), style: tx(12.5, w: 6, c: Tw.gray700)),
          ],
        ),
      ]);
    } else if (_photos.length == 1) {
      children.addAll([
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(aspectRatio: 4 / 5, child: _PhotoImage(photo: _photos.first)),
        ),
        const SizedBox(height: 12),
        Text(_date(df, _photos.first), style: tx(13, w: 6, c: Tw.gray700)),
        const SizedBox(height: 4),
        Text(i18n.t('mobileJournal.oneBody'), style: tx(14, c: Tw.gray600, h: relaxed)),
      ]);
    } else {
      children.addAll([
        Text(i18n.t('mobileJournal.emptyTitle'), style: heading(24, h: 1.15)),
        const SizedBox(height: 8),
        Text(i18n.t('mobileJournal.emptyBody'), style: tx(14.5, c: Tw.gray600, h: relaxed)),
      ]);
    }
    final next = nextJournalPhotoDay(_photos, DateTime.now());
    children.addAll([
      const SizedBox(height: 20),
      if (next != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Icon(LucideIcons.calendarClock, size: 16, color: Tw.gray500),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  i18n.t('mobileJournal.next', {'day': DateFormat.EEEE(i18n.lang).format(next)}),
                  style: tx(13.5, w: 5, c: Tw.gray600),
                ),
              ),
            ],
          ),
        ),
      if (next == null)
        PrimaryButton(
          onPressed: _busy ? null : _openCapture,
          loading: _busy,
          color: theme.primary,
          icon: LucideIcons.camera,
          label: i18n.t('mobileJournal.capture'),
          minHeight: 54,
        )
      else
        SecondaryButton(
          onPressed: _busy ? null : _openCapture,
          loading: _busy,
          icon: LucideIcons.camera,
          label: i18n.t('mobileJournal.captureEarly'),
          minHeight: 52,
        ),
      if (_notice.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(_notice, style: tx(13.5, w: 5, c: Tw.emerald700, h: 1.4)),
      ],
      if (_error.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(_error, style: tx(13.5, w: 5, c: Tw.red600, h: 1.4)),
      ],
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _consent(I18n i18n, RebiTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: theme.primary.withValues(alpha: .12)),
            child: Icon(LucideIcons.lockKeyhole, size: 22, color: theme.fg),
          ),
        ),
        const SizedBox(height: 16),
        Text(i18n.t('mobileJournal.consentTitle'), style: heading(24, h: 1.15)),
        const SizedBox(height: 8),
        Text(i18n.t('mobileJournal.consentBody'), style: tx(14.5, c: Tw.gray600, h: relaxed)),
        const SizedBox(height: 20),
        PrimaryButton(
          onPressed: _busy ? null : _allowPhotos,
          loading: _busy,
          color: theme.primary,
          label: i18n.t('mobileJournal.consentCta'),
          minHeight: 54,
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(_error, style: tx(13.5, w: 5, c: Tw.red600, h: 1.4)),
        ],
      ],
    );
  }

  Widget _timeline(I18n i18n, RebiTheme theme) {
    final df = DateFormat.MMMd(i18n.lang);
    // En eski fotoğraf "önce"dür, seçilemez; diğerlerinden biri "sonra" olarak seçilir.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 18),
          child: Text(i18n.t('mobileJournal.all', {'n': _photos.length}), style: tx(13, w: 7, c: Tw.gray700)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 18),
            itemCount: _photos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final photo = _photos[i];
              final isBefore = i == _photos.length - 1;
              final selected = i == _after && !isBefore;
              return Semantics(
                button: !isBefore,
                selected: selected,
                label: _date(df, photo),
                child: GestureDetector(
                  onTap: isBefore ? null : () => setState(() => _after = i),
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 68,
                        height: 84,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: selected ? theme.primary : (isBefore ? Tw.gray300 : Colors.transparent), width: 2),
                        ),
                        child: ClipRRect(borderRadius: BorderRadius.circular(11), child: _PhotoImage(photo: photo)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isBefore ? i18n.t('mobileJournal.before') : _date(df, photo),
                        style: tx(11.5, w: selected || isBefore ? 7 : 5, c: selected ? theme.fg : Tw.gray500),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _date(DateFormat df, SkinPhoto p) => p.takenAt == null ? '—' : df.format(p.takenAt!);
}

/// İki fotoğraf üst üste; dikey çizgi sürüklenerek "önce" ile "sonra" arasında geçiş yapılır.
class _CompareView extends StatefulWidget {
  const _CompareView({
    required this.before,
    required this.after,
    required this.beforeLabel,
    required this.afterLabel,
    required this.semanticsLabel,
  });

  final SkinPhoto before;
  final SkinPhoto after;
  final String beforeLabel;
  final String afterLabel;
  final String semanticsLabel;

  @override
  State<_CompareView> createState() => _CompareViewState();
}

class _CompareViewState extends State<_CompareView> {
  double _split = .5;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticsLabel,
      slider: true,
      value: '${(_split * 100).round()}%',
      increasedValue: '${((_split + .1).clamp(0.0, 1.0) * 100).round()}%',
      decreasedValue: '${((_split - .1).clamp(0.0, 1.0) * 100).round()}%',
      onIncrease: () => setState(() => _split = (_split + .1).clamp(0.0, 1.0)),
      onDecrease: () => setState(() => _split = (_split - .1).clamp(0.0, 1.0)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio: 4 / 5,
          child: LayoutBuilder(
            builder: (context, box) {
              void move(double dx) => setState(() => _split = (dx / box.maxWidth).clamp(0.0, 1.0));
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (d) => move(d.localPosition.dx),
                onTapDown: (d) => move(d.localPosition.dx),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _PhotoImage(photo: widget.after),
                    ClipRect(
                      clipper: _LeftClipper(_split),
                      child: _PhotoImage(photo: widget.before),
                    ),
                    Positioned(
                      left: box.maxWidth * _split - 1,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 2, color: Colors.white),
                    ),
                    Positioned(
                      left: box.maxWidth * _split - 18,
                      top: box.maxHeight / 2 - 18,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 8)],
                        ),
                        child: const Icon(LucideIcons.chevronsLeftRight, size: 18, color: Brand.forest),
                      ),
                    ),
                    Positioned(left: 10, top: 10, child: _Tag(text: widget.beforeLabel)),
                    Positioned(right: 10, top: 10, child: _Tag(text: widget.afterLabel)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LeftClipper extends CustomClipper<Rect> {
  _LeftClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_LeftClipper old) => old.fraction != fraction;
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: .45), borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: tx(11.5, w: 6, c: Colors.white)),
    );
  }
}

class _PhotoImage extends StatelessWidget {
  const _PhotoImage({required this.photo});

  final SkinPhoto photo;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(color: Tw.gray100, child: Center(child: Icon(LucideIcons.image, size: 28, color: Tw.gray300)));
    if (photo.url.isEmpty) return placeholder;
    return Image.network(
      photo.url,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (c, e, s) => placeholder,
      loadingBuilder: (c, child, prog) => prog == null ? child : placeholder,
    );
  }
}

/// Çekimden önce üç kısa ipucu ve kaynak seçimi. Sayfa, seçilen kaynağı döndürerek kapanır.
class _CaptureTips extends StatelessWidget {
  const _CaptureTips({required this.theme});

  final RebiTheme theme;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    Widget tip(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: theme.primary.withValues(alpha: .1)),
                child: Icon(icon, size: 18, color: theme.fg),
              ),
              const SizedBox(width: 12),
              Expanded(child: Padding(padding: const EdgeInsets.only(top: 8), child: Text(text, style: tx(14.5, c: Tw.gray700, h: 1.4)))),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tip(LucideIcons.sun, i18n.t('mobileJournal.tipLight')),
          tip(LucideIcons.sparkles, i18n.t('mobileJournal.tipBare')),
          tip(LucideIcons.scanFace, i18n.t('mobileJournal.tipFrame')),
          const SizedBox(height: 8),
          PrimaryButton(
            onPressed: () => Navigator.of(context).pop(ImageSource.camera),
            color: theme.primary,
            icon: LucideIcons.camera,
            label: i18n.t('mobileJournal.camera'),
            minHeight: 54,
          ),
          const SizedBox(height: 10),
          SecondaryButton(
            onPressed: () => Navigator.of(context).pop(ImageSource.gallery),
            icon: LucideIcons.image,
            label: i18n.t('mobileJournal.gallery'),
            minHeight: 52,
          ),
        ],
      ),
    );
  }
}
