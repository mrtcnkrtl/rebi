import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../state/auth_controller.dart';
import '../../state/theme_controller.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import 'account_parts.dart';

final _imageExt = RegExp(r'\.(jpe?g|png|webp|gif|heic|avif)$', caseSensitive: false);

class _Photo {
  const _Photo(this.name, this.path, this.url, this.createdAt);

  final String name;
  final String path;
  final String url;
  final String? createdAt;
}

/// Analizde yüklenen cilt fotoğrafları (`skin-photos` deposu, 15 dk geçerli imzalı bağlantılarla), yeniden eskiye.
class AccountPhotosCard extends StatefulWidget {
  const AccountPhotosCard({super.key, required this.theme});

  final RebiTheme theme;

  @override
  State<AccountPhotosCard> createState() => _AccountPhotosCardState();
}

class _AccountPhotosCardState extends State<AccountPhotosCard> {
  List<_Photo> _photos = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = supabase;
    final uid = context.read<AuthController>().user?.id;
    if (client == null || uid == null) {
      setState(() {
        _photos = [];
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final bucket = client.storage.from('skin-photos');
      List<FileObject> list;
      try {
        list = await bucket.list(
          path: uid,
          searchOptions: const SearchOptions(limit: 100, offset: 0, sortBy: SortBy(column: 'created_at', order: 'desc')),
        );
      } catch (_) {
        list = await bucket.list(path: uid, searchOptions: const SearchOptions(limit: 100, offset: 0));
      }
      final files = list.where((f) => f.name.isNotEmpty && !f.name.startsWith('.') && _imageExt.hasMatch(f.name));
      final withUrls = await Future.wait(files.map((f) async {
        final path = '$uid/${f.name}';
        var url = '';
        try {
          url = await bucket.createSignedUrl(path, 900);
        } catch (_) {
          url = '';
        }
        return _Photo(f.name, path, url, f.createdAt);
      }));
      int ts(_Photo p) => p.createdAt == null ? 0 : (DateTime.tryParse(p.createdAt!)?.millisecondsSinceEpoch ?? 0);
      final sorted = withUrls.toList()
        ..sort((a, b) {
          final d = ts(b) - ts(a);
          return d != 0 ? d : b.name.compareTo(a.name);
        });
      if (mounted) setState(() => _photos = sorted);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is StorageException ? e.message : I18n.instance.t('mobileAccount.photos.error');
          _photos = [];
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _body(I18n i18n) {
    final theme = widget.theme;
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: SizedBox(width: 32, height: 32, child: CircularProgressIndicator(color: theme.primary))),
      );
    }
    if (_error.isNotEmpty) {
      return Row(
        children: [
          Icon(LucideIcons.circleAlert, size: 16, color: Tw.red600),
          const SizedBox(width: 8),
          Expanded(child: Text(_error, style: tx(14, c: Tw.red600))),
        ],
      );
    }
    if (_photos.isEmpty) {
      return RCard(
        dashed: true,
        borderColor: Tw.gray200,
        color: Tw.surface.withValues(alpha: .5),
        radius: 16,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(
          children: [
            Icon(LucideIcons.image, size: 40, color: Tw.gray300),
            const SizedBox(height: 8),
            Text(i18n.t('mobileAccount.photos.empty'), style: tx(14, c: Tw.gray600)),
            const SizedBox(height: 4),
            TextLink(i18n.t('analyze.quickPhotoUpload'), onTap: () => context.push('/dashboard/analyze?photo=1'), style: tx(14, w: 6, c: theme.fg)),
          ],
        ),
      );
    }
    final df = DateFormat.yMMMd(i18n.lang).add_Hm();
    return Column(
      children: [
        for (final p in _photos) ...[
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Tw.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Tw.gray100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (p.url.isNotEmpty)
                  Image.network(
                    p.url,
                    height: 192,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Container(height: 192, color: Tw.gray100),
                    loadingBuilder: (c, child, prog) => prog == null ? child : Container(height: 192, color: Tw.gray100),
                  )
                else
                  SizedBox(height: 128, child: Center(child: Text(i18n.t('mobileAccount.photos.noPreview'), style: tx(14, c: Tw.gray600)))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: Tw.gray50))),
                  child: Text(
                    p.createdAt != null ? df.format(DateTime.parse(p.createdAt!).toLocal()) : '—',
                    style: tx(12.5, c: Tw.gray600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = widget.theme;
    return RCard(
      padding: const EdgeInsets.all(18),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: AccountSectionTitle(icon: LucideIcons.camera, color: theme.fg, text: i18n.t('profile.photosTitle'))),
              TextLink(i18n.t('profile.refresh'), onTap: _load, style: tx(13, w: 6, c: theme.fg)),
            ],
          ),
          const SizedBox(height: 6),
          Text(i18n.t('mobileAccount.photos.hint'), style: tx(12.5, c: Tw.gray600, h: relaxed)),
          const SizedBox(height: 14),
          _body(i18n),
        ],
      ),
    );
  }
}
