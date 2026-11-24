import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/screens/routine/routine_parts.dart';

void main() {
  test('adım başlığı: tür kalın satır, ürün tarifi alt satır; metin kısaltılmaz', () {
    expect(splitStepHeading('Temizleme: Yüzey aktif (SLES-free) köpük temizleyici'),
        (title: 'Temizleme', subtitle: 'Yüzey aktif (SLES-free) köpük temizleyici'));
    expect(splitStepHeading('Sabah: Nemlendirici: Niasinamid %4'), (title: 'Nemlendirici', subtitle: 'Niasinamid %4'));
    expect(splitStepHeading('SPF 30+ (mat bitişli, yağsız SPF)'), (title: 'SPF 30+', subtitle: 'mat bitişli, yağsız SPF'));
    expect(splitStepHeading('Bol su iç'), (title: 'Bol su iç', subtitle: ''));
    expect(splitStepHeading('Not (saat: 22:00) uyu'), (title: 'Not (saat: 22:00) uyu', subtitle: ''));
  });
}
