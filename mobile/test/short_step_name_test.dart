import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/routine_logic.dart';

void main() {
  test('sunucunun gerçek adım metinlerinden kısa ad', () {
    const cases = {
      'Temizleme: Yüzey aktif (SLES-free) köpük temizleyici': 'Temizleme',
      'Nemlendirici: Niasinamid %4 + Hyaluronik asit (hafif jel)': 'Nemlendirici',
      'SPF 30+ (mat bitişli, yağsız SPF)': 'SPF 30+',
      'Çift aşama temizlik: yağ/balm bazlı temizleyici + nazik temizleyici': 'Çift aşama temizlik',
      '⏸️ Salisilik asit %1 tonik (BHA, INCI: Salicylic Acid) — alın & T-bölge hedefli — şimdilik kullanma': 'Salisilik asit %1 tonik',
      'Niasinamid %10 serum (INCI: Niacinamide; niasin ile karıştırma) + Azelaik asit %10-15 (INCI: Azelaic Acid; dikarboksilli asit) (sırayla veya tek formül)':
          'Niasinamid %10 serum',
      'Gece: Niasinamid %4 + HA (hafif jel, gece)': 'Niasinamid %4 + HA',
      '5 Dakika Nefes Egzersizi': '5 Dakika Nefes Egzersizi',
      'Göz kenarı: asit/retinol yok — ince nem veya peptid': 'Göz kenarı',
      'Night: Niacinamide 4% + HA (light gel)': 'Niacinamide 4% + HA',
    };
    cases.forEach((input, expected) => expect(shortStepName(input), expected, reason: input));
  });

  test('uzun ad kelime sınırından kısaltılır, asla 31 karakteri geçmez', () {
    final s = shortStepName('Seramid + niasinamid içeren bariyer nemlendirici (öncelik)');
    expect(s, 'Seramid + niasinamid içeren…');
    expect(s.length, lessThanOrEqualTo(shortStepMaxLength + 1));
  });

  test('yalnızca parantezden oluşan ya da boş metin bozulmaz', () {
    expect(shortStepName(''), '');
    expect(shortStepName('(öncelik)'), '(öncelik)');
  });

  test('açıklama satırı: iki nokta sonrası ya da parantez içi, sade', () {
    const cases = {
      'Temizleme: Yüzey aktif (SLES-free) köpük temizleyici': 'Yüzey aktif köpük temizleyici',
      'Nemlendirici: Niasinamid %4 + Hyaluronik asit (hafif jel)': 'Niasinamid %4 + Hyaluronik asit',
      'SPF 30+ (mat bitişli, yağsız SPF)': 'mat bitişli, yağsız SPF',
      'Göz kenarı: asit/retinol yok — ince nem veya peptid': 'asit/retinol yok',
      '5 Dakika Nefes Egzersizi': '',
      'Gece: Niasinamid %4 + HA (hafif jel, gece)': 'hafif jel, gece',
    };
    cases.forEach((input, expected) => expect(stepParts(input).subtitle, expected, reason: input));
  });
}
