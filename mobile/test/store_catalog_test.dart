import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/store_catalog.dart';

void main() {
  final catalog = [
    const StoreProduct(slug: 'niacinamid-4-5', nameTr: 'Niasinamid · %4-5', sizeLabel: '%4-5', stepOrder: 20),
    const StoreProduct(slug: 'vitamin-c-10-15', nameTr: 'C vitamini · %10-15', sizeLabel: '%10-15', stepOrder: 25),
    const StoreProduct(slug: 'mineral-spf-spf-50', nameTr: 'Güneş kremi · SPF 50+', sizeLabel: 'SPF 50+', stepOrder: 40),
  ];

  test('eş ve adım eşleşince vitrin ürünü bulunur', () {
    final hit = matchShelfProduct('Niasinamid %4-5 serum', 20, catalog);
    expect(hit?.slug, 'niacinamid-4-5');
  });

  test('eşleşmeyen ürün null döner', () {
    expect(matchShelfProduct('Bilinmeyen krem', 99, catalog), isNull);
  });

  test('sayfa adresi mağaza slugunu taşır', () {
    expect(catalog.first.pageUrl, contains('/magaza/niacinamid-4-5'));
  });
}
