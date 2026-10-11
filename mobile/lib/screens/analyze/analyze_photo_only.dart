import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show StorageException;

import '../../core/api.dart';
import '../../core/daily_tracking.dart';
import '../../core/i18n.dart';
import '../../core/image_quality.dart';
import '../../state/auth_controller.dart';
import '../../state/theme_controller.dart';
import '../../ui/components/photo_picker.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';

/// Profilden veya rutin hazır ekranından: yalnızca depoya foto yükle (tam analiz zorunlu değil).
class AnalyzePhotoOnly extends StatefulWidget {
  const AnalyzePhotoOnly({super.key});

  @override
  State<AnalyzePhotoOnly> createState() => _AnalyzePhotoOnlyState();
}

class _AnalyzePhotoOnlyState extends State<AnalyzePhotoOnly> {
  PickedPhoto? _photo;
  bool _busy = false;
  (String, String) _msg = ('', '');
  String _photoContext = 'unsure';

  Future<void> _pick(ImageSource source, CameraDevice camera) async {
    PickedPhoto? picked;
    try {
      picked = await pickSkinPhoto(source, camera: camera);
    } on PlatformException {
      return;
    }
    if (picked == null || !mounted) return;
    setState(() {
      _photo = picked;
      _msg = ('', '');
    });
    final q = await analyzeSkinPhotoQuality(picked.bytes);
    if (mounted && identical(_photo, picked)) setState(() => picked!.quality = q);
  }

  /// Uzantıdaki harf/rakam dışı karakterleri at (web ile aynı temizlik).
  static String _cleanExt(String ext) {
    final cleaned = ext.replaceAll(RegExp('[^a-z0-9]', caseSensitive: false), '');
    return cleaned.isEmpty ? 'jpg' : cleaned;
  }

  Future<void> _upload(Pack pack) async {
    final photo = _photo;
    if (photo == null) {
      setState(() => _msg = ('err', pack.s('errors.pickPhotoFirst')));
      return;
    }
    final client = supabase;
    if (client == null) {
      setState(() => _msg = ('err', pack.s('errors.storageNotConfigured')));
      return;
    }
    final uid = context.read<AuthController>().user?.id;
    if (uid == null) {
      setState(() => _msg = ('err', pack.s('errors.sessionRequired')));
      return;
    }
    setState(() {
      _busy = true;
      _msg = ('', '');
    });
    try {
      final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.${_cleanExt(photo.extension)}';
      await client.storage.from('skin-photos').upload(path, File(photo.file.path));
      await ingestDailyTrackingEvent(uid, 'photo_meta', {
        'context': _photoContext,
        'meanLuma': photo.quality?.meanLuma,
        'variance': photo.quality?.variance,
        'sharpnessApprox': photo.quality?.sharpnessApprox,
        'flow': 'photo_only',
      });
      if (!mounted) return;
      setState(() {
        _msg = ('ok', pack.s('errors.uploadSuccess'));
        _photo = null;
      });
    } catch (e) {
      if (!mounted) return;
      final m = e is StorageException ? e.message : '';
      setState(() => _msg = ('err', m.isNotEmpty ? m : pack.s('errors.uploadFailed')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final pack = Pack(i18n.analyzeWizardPack);
    final theme = context.watch<ThemeController>().theme;

    if (supabase == null) {
      return ThemedBackground(
        theme: theme,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(pack.s('errors.supabaseAnalyzeMissing'), textAlign: TextAlign.center, style: tx(14, c: Tw.gray600)),
          ),
        ),
      );
    }

    final intro2 = pack.s('errors.photoOnlyIntro2');
    return ThemedPage(
      theme: theme,
      padding: EdgeInsets.fromLTRB(16, 32, 16, 32 + MediaQuery.of(context).padding.bottom),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: InkWell(
            onTap: () => context.canPop() ? context.pop() : context.go('/dashboard'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.arrowLeft, size: 16, color: Tw.gray500),
                  const SizedBox(width: 4),
                  Text(i18n.t('analyze.photoOnlyBack'), style: tx(12, w: 5, c: Tw.gray500)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(child: GradientIconBox(icon: LucideIcons.camera, from: theme.accent, to: theme.primary)),
        const SizedBox(height: 8),
        Text(i18n.t('analyze.photoOnlyTitle'), textAlign: TextAlign.center, style: tx(20, w: 7)),
        const SizedBox(height: 8),
        Text(
          '${pack.s('errors.photoOnlyIntro1')}${intro2.isNotEmpty ? ' $intro2' : ''}',
          textAlign: TextAlign.center,
          style: tx(14, c: Tw.gray600, h: relaxed),
        ),
        if (_msg.$2.isNotEmpty) ...[
          const SizedBox(height: 16),
          NoticeBox(
            text: _msg.$2,
            bg: _msg.$1 == 'ok' ? Tw.emerald50 : Tw.red50,
            border: _msg.$1 == 'ok' ? Tw.emerald100 : Tw.red100,
            fg: _msg.$1 == 'ok' ? Tw.emerald900 : Tw.red800,
          ),
        ],
        const SizedBox(height: 16),
        RCard(
          child: PhotoPickerCard(
            photo: _photo,
            photoContext: _photoContext,
            changeLabel: pack.s('photoOnly.change'),
            onPick: _pick,
            onClear: () => setState(() => _photo = null),
            onContextChanged: (v) => setState(() => _photoContext = v),
          ),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          onPressed: _busy || _photo == null ? null : () => _upload(pack),
          loading: _busy,
          color: theme.primary,
          label: pack.s('photoOnly.savePhoto'),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextLink(
            pack.s('photoOnly.goProfilePhotos'),
            onTap: () => context.go('/dashboard/profile'),
            style: tx(14, w: 6, c: theme.primary),
          ),
        ),
        Center(
          child: TextLink(
            pack.s('photoOnly.fullFormLink'),
            onTap: () => context.go('/dashboard/analyze'),
            style: tx(12, c: Tw.gray500),
          ),
        ),
      ],
    );
  }
}
