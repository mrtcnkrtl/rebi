import 'api.dart';
import '../config/env.dart';

/// Vitrin ürünü (GET /store/products).
class StoreProduct {
  const StoreProduct({
    required this.slug,
    required this.nameTr,
    this.nameEn,
    this.sizeLabel,
    this.stepOrder,
    this.productType,
  });

  final String slug;
  final String nameTr;
  final String? nameEn;
  final String? sizeLabel;
  final int? stepOrder;
  final String? productType;

  factory StoreProduct.fromJson(Map<String, dynamic> json) => StoreProduct(
        slug: '${json['slug'] ?? ''}',
        nameTr: '${json['name_tr'] ?? ''}',
        nameEn: json['name_en']?.toString(),
        sizeLabel: json['size_label']?.toString(),
        stepOrder: json['step_order'] is int ? json['step_order'] as int : int.tryParse('${json['step_order'] ?? ''}'),
        productType: json['product_type']?.toString(),
      );

  String get pageUrl => '${Env.siteUrl}/magaza/$slug';
}

String _norm(String? s) => (s ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Rafım serbest metin ürününü vitrin SKU'suna yaklaştırır (sunucu `match_shelf_product` ile aynı fikir).
StoreProduct? matchShelfProduct(String shelfName, int? stepOrder, List<StoreProduct> products) {
  final name = _norm(shelfName);
  if (name.isEmpty || products.isEmpty) return null;
  final pool = stepOrder == null ? products : products.where((p) => p.stepOrder == stepOrder).toList();
  final candidates = pool.isEmpty ? products : pool;
  StoreProduct? best;
  var bestScore = 0;
  for (final p in candidates) {
    final label = _norm(p.sizeLabel);
    final nameTr = _norm(p.nameTr);
    final base = nameTr.contains('·') ? nameTr.split('·').first.trim() : nameTr;
    var score = 0;
    if (label.isNotEmpty && name.contains(label)) score += 3;
    if (base.isNotEmpty) {
      if (name.contains(base)) {
        score += 2;
      } else {
        for (final tok in base.replaceAll('/', ' ').split(' ')) {
          if (tok.length > 3 && name.contains(tok)) {
            score += 2;
            break;
          }
        }
      }
    }
    if (stepOrder != null && p.stepOrder == stepOrder) score += 1;
    if (score >= 3 && score > bestScore) {
      bestScore = score;
      best = p;
    }
  }
  return best;
}

/// Vitrin listesini çeker. Auth gerekmez. Hata/ boşta boş liste.
Future<List<StoreProduct>> fetchStoreProducts() async {
  try {
    final res = await apiGet('/store/products', auth: false);
    if (!res.ok) return const [];
    final raw = res.data['products'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) StoreProduct.fromJson(Map<String, dynamic>.from(item)),
    ].where((p) => p.slug.isNotEmpty).toList();
  } catch (_) {
    return const [];
  }
}
