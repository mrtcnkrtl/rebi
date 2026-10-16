/// Rafım: "ürün bitti" işaretlenip henüz yenisi alınmamış ürünler. Sunucu bunu gün içi olaylardan türetir
/// (`GET /today/plan` → `products_out`, `docs/MOBIL-API.md`); bu dosya yanıtı okur ve henüz sunucuya ulaşmamış
/// olayların etkisini ekrana hemen yansıtır (çevrimdışı kuyruk).
library;

const shelfFinishedEvent = 'product_finished';
const shelfRestockedEvent = 'product_restocked';

/// Ürün adı sunucuya en fazla bu kadar uzunlukta gider (sunucudaki kırpmayla aynı).
const shelfMaxNameLength = 120;

/// Aynı ürünü eşleştirmek için: büyük/küçük harf ve fazla boşluk fark yaratmaz; sunucu gibi ilk 120 karakter.
String shelfKey(String name) {
  final trimmed = name.trim();
  final cut = trimmed.length > shelfMaxNameLength ? trimmed.substring(0, shelfMaxNameLength) : trimmed;
  return cut.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).join(' ').toLowerCase();
}

/// Sunucuya gönderilecek ürün adı (kırpılmış).
String shelfName(String name) {
  final trimmed = name.trim();
  return trimmed.length > shelfMaxNameLength ? trimmed.substring(0, shelfMaxNameLength) : trimmed;
}

class ShelfItem {
  const ShelfItem({required this.product, this.stepOrder, this.finishedAt, this.daysOut = 0});

  factory ShelfItem.fromJson(Map<String, dynamic> j) => ShelfItem(
        product: '${j['product'] ?? ''}'.trim(),
        stepOrder: j['step_order'] is num ? (j['step_order'] as num).toInt() : null,
        finishedAt: DateTime.tryParse('${j['finished_at'] ?? ''}')?.toLocal(),
        daysOut: j['days_out'] is num ? (j['days_out'] as num).toInt().clamp(0, 100000) : 0,
      );

  final String product;

  /// Rutindeki adım sırası (biliniyorsa).
  final int? stepOrder;
  final DateTime? finishedAt;

  /// Kaç gün önce bitti (kullanıcının yerel gününe göre; bugün 0).
  final int daysOut;

  String get key => shelfKey(product);
}

/// `products_out` listesi; bozuk kayıtlar (ürün adı boş) atlanır.
List<ShelfItem> parseShelf(Object? json) => [
      for (final e in (json is List ? json : const []))
        if (e is Map && '${e['product'] ?? ''}'.trim().isNotEmpty) ShelfItem.fromJson(e.cast<String, dynamic>()),
    ];

/// Henüz sunucuya ulaşmamış bir ürün olayının etkisi. Sunucudaki türetmeyle aynı kural: son olay geçerlidir;
/// zaten bitmişse tekrar bitti işareti ilk tarihi korur, hiç bitmemişse "aldım" bir şey yapmaz.
List<ShelfItem> shelfWith(List<ShelfItem> items, String type, Map<String, dynamic> payload, {DateTime? now}) {
  final name = shelfName('${payload['product'] ?? ''}');
  final key = shelfKey(name);
  if (key.isEmpty) return items;
  switch (type) {
    case shelfFinishedEvent:
      if (items.any((i) => i.key == key)) return items;
      final step = payload['step_order'];
      return [
        ShelfItem(product: name, stepOrder: step is num ? step.toInt() : null, finishedAt: now ?? DateTime.now()),
        ...items,
      ];
    case shelfRestockedEvent:
      return [for (final i in items) if (i.key != key) i];
    default:
      return items;
  }
}

/// "3 gün önce bitti" gibi metin için: bugün / dün / n gün.
({String kind, int days}) shelfAge(ShelfItem item) => switch (item.daysOut) {
      0 => (kind: 'today', days: 0),
      1 => (kind: 'yesterday', days: 1),
      final n => (kind: 'days', days: n),
    };
