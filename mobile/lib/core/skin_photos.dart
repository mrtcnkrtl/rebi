import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'api.dart';
import 'image_quality.dart';

/// Cilt fotoğrafları: Supabase `skin-photos` deposunda `<kullanıcı>/<zaman>.<uzantı>` olarak durur (özel; yalnızca
/// kullanıcının kendisi okur). Bağlantılar kısa süreli imzalıdır. Günlük, hesap ekranı ve hızlı yükleme aynı depoyu kullanır.
class SkinPhoto {
  const SkinPhoto({required this.path, required this.url, required this.takenAt});

  final String path;

  /// İmzalı bağlantı (15 dk); alınamadıysa boş.
  final String url;
  final DateTime? takenAt;
}

final _imageExt = RegExp(r'\.(jpe?g|png|webp|gif|heic|avif)$', caseSensitive: false);

/// Testler gerçek depo yerine bunu takar.
abstract class SkinPhotoStore {
  /// Yeniden eskiye.
  Future<List<SkinPhoto>> list(String userId);

  Future<void> upload(String userId, File file, String extension);
}

class SupabaseSkinPhotoStore implements SkinPhotoStore {
  const SupabaseSkinPhotoStore();

  StorageFileApi get _bucket {
    final client = supabase;
    if (client == null) throw StateError('storage');
    return client.storage.from('skin-photos');
  }

  @override
  Future<List<SkinPhoto>> list(String userId) async {
    final bucket = _bucket;
    List<FileObject> files;
    try {
      files = await bucket.list(
        path: userId,
        searchOptions: const SearchOptions(limit: 100, offset: 0, sortBy: SortBy(column: 'created_at', order: 'desc')),
      );
    } catch (_) {
      files = await bucket.list(path: userId, searchOptions: const SearchOptions(limit: 100, offset: 0));
    }
    final images = files.where((f) => f.name.isNotEmpty && !f.name.startsWith('.') && _imageExt.hasMatch(f.name));
    final photos = await Future.wait(images.map((f) async {
      final path = '$userId/${f.name}';
      var url = '';
      try {
        url = await bucket.createSignedUrl(path, 900);
      } catch (_) {
        url = '';
      }
      return SkinPhoto(path: path, url: url, takenAt: photoTime(f.name, f.createdAt));
    }));
    return sortNewestFirst(photos);
  }

  @override
  Future<void> upload(String userId, File file, String extension) async {
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.${cleanPhotoExtension(extension)}';
    await _bucket.upload(path, file);
  }
}

SkinPhotoStore skinPhotoStore = const SupabaseSkinPhotoStore();

/// Çekim zamanı: dosya adı yükleme anının milisaniyesidir (`1731500000000.jpg`); okunamazsa deponun `created_at`'i.
DateTime? photoTime(String name, String? createdAt) {
  final stem = name.split('/').last.split('.').first;
  final ms = int.tryParse(stem);
  if (ms != null && ms > 1000000000000) return DateTime.fromMillisecondsSinceEpoch(ms);
  return createdAt == null ? null : DateTime.tryParse(createdAt)?.toLocal();
}

List<SkinPhoto> sortNewestFirst(Iterable<SkinPhoto> photos) {
  int ts(SkinPhoto p) => p.takenAt?.millisecondsSinceEpoch ?? 0;
  return photos.toList()
    ..sort((a, b) {
      final d = ts(b) - ts(a);
      return d != 0 ? d : b.path.compareTo(a.path);
    });
}

/// Uzantıdaki harf/rakam dışı karakterler atılır (web ile aynı temizlik).
String cleanPhotoExtension(String ext) {
  final cleaned = ext.replaceAll(RegExp('[^a-z0-9]', caseSensitive: false), '');
  return cleaned.isEmpty ? 'jpg' : cleaned;
}

/// Günlük haftada bir fotoğraf ister: son fotoğraftan bu kadar gün geçince yenisi "zamanı geldi" sayılır.
const journalIntervalDays = 7;

/// Bir sonraki günlük fotoğrafının günü; hiç fotoğraf yoksa ya da zamanı geldiyse null (şimdi çekilebilir).
DateTime? nextJournalPhotoDay(List<SkinPhoto> newestFirst, DateTime now) {
  final last = newestFirst.isEmpty ? null : newestFirst.first.takenAt;
  if (last == null) return null;
  final due = DateTime(last.year, last.month, last.day).add(const Duration(days: journalIntervalDays - 1));
  final today = DateTime(now.year, now.month, now.day);
  return today.isBefore(due) ? due : null;
}

/// Kalite notu: çok karanlık ya da bulanık fotoğraf karşılaştırmayı bozar.
bool photoNeedsRetake(PhotoQuality? q) => q != null && (q.tooDark || q.tooBlurry);
