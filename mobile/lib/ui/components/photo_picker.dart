import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../core/image_quality.dart';
import '../tw.dart';
import '../widgets/common.dart';

/// Seçilen cilt fotoğrafı + kalite ölçümü + bağlam (web: `photoFile`, `photoPreview`, `photoQuality`).
class PickedPhoto {
  PickedPhoto(this.file, this.bytes);

  final XFile file;
  final Uint8List bytes;
  PhotoQuality? quality;

  /// Dosya uzantısı (web: `photoFile.name.split(".").pop()`).
  String get extension {
    final name = file.name.isNotEmpty ? file.name : file.path;
    final dot = name.lastIndexOf('.');
    return dot >= 0 && dot < name.length - 1 ? name.substring(dot + 1) : 'jpg';
  }
}

final _picker = ImagePicker();

/// Galeri / ön kamera / arka kamera. JPEG %92 kalite: webcam çekimi ve iOS'un HEIC→JPEG
/// dönüşümüyle aynı biçim; çözünürlük korunur.
Future<PickedPhoto?> pickSkinPhoto(ImageSource source, {CameraDevice camera = CameraDevice.rear}) async {
  final file = await _picker.pickImage(source: source, preferredCameraDevice: camera, imageQuality: 92);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  return PickedPhoto(file, bytes);
}

/// Fotoğraf yoksa seçim düğmeleri, varsa önizleme + bağlam + kalite notları.
class PhotoPickerCard extends StatelessWidget {
  const PhotoPickerCard({
    super.key,
    required this.photo,
    required this.photoContext,
    required this.onPick,
    required this.onClear,
    required this.onContextChanged,
    required this.changeLabel,
    this.header,
  });

  final PickedPhoto? photo;
  final String photoContext;
  final void Function(ImageSource source, CameraDevice camera) onPick;
  final VoidCallback onClear;
  final ValueChanged<String> onContextChanged;
  final String changeLabel;

  /// Fotoğraf yokken düğmelerin üstünde gösterilecek ipuçları.
  final List<Widget>? header;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final pack = Pack(i18n.analyzeWizardPack);
    final p = photo;
    final q = p?.quality;

    if (p != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(p.bytes, height: 256, fit: BoxFit.cover, gaplessPlayback: true),
          ),
          const SizedBox(height: 12),
          SecondaryButton(onPressed: onClear, label: changeLabel, fontSize: 14),
          const SizedBox(height: 12),
          Text(i18n.t('analyze.photoContextLabel'), style: tx(12, w: 6, c: Tw.gray700)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: photoContext,
            isExpanded: true,
            style: tx(14, c: Tw.gray900),
            decoration: inputDecoration(
              radius: 12,
              borderWidth: 1,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: [
              DropdownMenuItem(value: 'first', child: Text(i18n.t('analyze.photoContextFirst'))),
              DropdownMenuItem(value: 'same_light', child: Text(i18n.t('analyze.photoContextSame'))),
              DropdownMenuItem(value: 'progress', child: Text(i18n.t('analyze.photoContextProgress'))),
              DropdownMenuItem(value: 'unsure', child: Text(i18n.t('analyze.photoContextUnsure'))),
            ],
            onChanged: (v) {
              if (v != null) onContextChanged(v);
            },
          ),
          if (q?.tooDark ?? false) ...[
            const SizedBox(height: 8),
            _QualityNote(i18n.t('analyze.photoTooDark'), ok: false),
          ],
          if (q?.tooBlurry ?? false) ...[
            const SizedBox(height: 8),
            _QualityNote(i18n.t('analyze.photoTooBlurry'), ok: false),
          ],
          if (q != null && !q.tooDark && !q.tooBlurry) ...[
            const SizedBox(height: 8),
            _QualityNote(i18n.t('analyze.photoQualityOk'), ok: true),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...?header,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _SourceButton(
                icon: LucideIcons.imagePlus,
                iconColor: Tw.gray700,
                label: pack.s('step4.galleryFile'),
                labelColor: Tw.gray800,
                border: Tw.gray200,
                bg: Tw.surface,
                onTap: () => onPick(ImageSource.gallery, CameraDevice.rear),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SourceButton(
                icon: LucideIcons.camera,
                iconColor: Tw.gray700,
                label: pack.s('step4.cameraFront'),
                labelColor: Tw.gray800,
                border: Tw.gray200,
                bg: Tw.surface,
                onTap: () => onPick(ImageSource.camera, CameraDevice.front),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SourceButton(
                icon: LucideIcons.camera,
                iconColor: Tw.gray700,
                label: pack.s('step4.cameraRear'),
                labelColor: Tw.gray800,
                border: Tw.gray200,
                bg: Tw.surface,
                onTap: () => onPick(ImageSource.camera, CameraDevice.rear),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.labelColor,
    required this.border,
    required this.bg,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Color labelColor;
  final Color border;
  final Color bg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border, width: 1.4),
          ),
          child: Column(
            children: [
              Icon(icon, size: 26, color: iconColor),
              const SizedBox(height: 8),
              Text(label, textAlign: TextAlign.center, style: tx(13, w: 6, c: labelColor, h: tight)),
            ],
          ),
        ),
      ),
    );
  }
}

class _QualityNote extends StatelessWidget {
  const _QualityNote(this.text, {required this.ok});

  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: ok ? Tw.emerald50 : Tw.amber50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ok ? Tw.emerald100 : Tw.amber100),
      ),
      child: Text(text, style: tx(11, c: ok ? Tw.emerald800 : Tw.amber900)),
    );
  }
}

/// Yerel dosya mı uzak adres mi, ikisini de gösterir (dashboard ilerleme fotoğrafı).
Widget photoFromUrlOrPath(String src, {double? height, BoxFit fit = BoxFit.cover}) {
  Widget fallback(BuildContext c, Object e, StackTrace? s) => Container(height: height, color: Tw.gray100);
  if (src.startsWith('http')) {
    return Image.network(src, height: height, width: double.infinity, fit: fit, errorBuilder: fallback);
  }
  return Image.file(File(src), height: height, width: double.infinity, fit: fit, errorBuilder: fallback);
}
