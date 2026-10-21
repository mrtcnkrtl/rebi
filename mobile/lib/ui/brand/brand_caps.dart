// Küçük, aralıklı büyük harfli etiketler (ör. "DERMOKOZMETİK YAPAY ZEKÂ") için yardımcılar.

/// Büyük harfe çevirir. Türkçe ve Azericede i→İ, ı→I olmalı; Dart'ın `toUpperCase`'i yerel ayar bilmez
/// ve "dermokozmetik"i "DERMOKOZMETIK" yapardı. Arapçada büyük harf yoktur, metin olduğu gibi kalır.
String brandCaps(String text, String lang) {
  if (lang == 'ar') return text;
  final t = (lang == 'tr' || lang == 'az') ? text.replaceAll('i', 'İ').replaceAll('ı', 'I') : text;
  return t.toUpperCase();
}

/// Harf aralığı. Arapçada aralık harfleri birbirinden koparır (bitişik yazı), bu yüzden orada sıfırdır.
double brandTracking(String lang, double spacing) => lang == 'ar' ? 0 : spacing;
