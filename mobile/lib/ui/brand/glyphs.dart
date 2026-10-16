import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Emoji yerine çizgi ikonlar: uygulamanın dili çizgi ikonlarla kurulur, emoji platforma göre farklı görünür
/// (iOS'ta renkli, bazı Android sürümlerinde tek renkli) ve tipografiyle uyuşmaz.

/// Backend'in rutin ve öneri öğelerinde `icon` olarak gönderdiği emojiler → ikon. Bilinmeyen emoji [fallback] olur.
IconData glyphForEmoji(String? emoji, {IconData fallback = LucideIcons.sparkles}) {
  final key = (emoji ?? '').replaceAll('️', '').trim();
  return _byEmoji[key] ?? fallback;
}

const _byEmoji = <String, IconData>{
  '🧴': LucideIcons.pipette,
  '🧊': LucideIcons.droplet,
  '🧼': LucideIcons.droplets,
  '🧪': LucideIcons.flaskConical,
  '💧': LucideIcons.droplet,
  '💦': LucideIcons.droplets,
  '🌊': LucideIcons.waves,
  '🏜': LucideIcons.wind,
  '🛡': LucideIcons.shieldCheck,
  '☀': LucideIcons.sun,
  '🌤': LucideIcons.cloudSun,
  '☁': LucideIcons.cloud,
  '🌙': LucideIcons.moon,
  '✨': LucideIcons.sparkles,
  '🌿': LucideIcons.leaf,
  '🌸': LucideIcons.flower,
  '💋': LucideIcons.smile,
  '🥗': LucideIcons.salad,
  '🧠': LucideIcons.brain,
  '🌡': LucideIcons.thermometer,
  '⚠': LucideIcons.triangleAlert,
};

/// Makyaj temizleme yöntemi (`cleansingMethods`).
IconData cleansingGlyph(String method) => switch (method) {
      'double' => LucideIcons.layers,
      'cleanser' => LucideIcons.droplet,
      'water' => LucideIcons.waves,
      'wipe' => LucideIcons.eraser,
      'none' => LucideIcons.moon,
      _ => LucideIcons.droplet,
    };

/// Beslenme seçimi (`nutritionChoices`).
IconData nutritionGlyph(String choice) => switch (choice) {
      'snacks' => LucideIcons.cookie,
      'sweets' => LucideIcons.candy,
      'fried_food' => LucideIcons.drumstick,
      'dairy' => LucideIcons.milk,
      'balanced' => LucideIcons.salad,
      _ => LucideIcons.utensils,
    };

/// Analiz sihirbazındaki cilt derdi.
IconData concernGlyph(String id) => switch (id) {
      'general' => LucideIcons.sparkles,
      'oiliness' => LucideIcons.droplet,
      'pores' => LucideIcons.circleDot,
      'acne' => LucideIcons.circleAlert,
      'aging' => LucideIcons.hourglass,
      'dryness' => LucideIcons.wind,
      'pigmentation' => LucideIcons.sun,
      'sensitivity' => LucideIcons.flower,
      _ => LucideIcons.sparkles,
    };

/// Check-in: cildin bugünkü hissi.
IconData skinFeelingGlyph(String id) => switch (id) {
      'iyi' => LucideIcons.smile,
      'kuru' => LucideIcons.wind,
      'yagli' => LucideIcons.droplet,
      'kirik' => LucideIcons.bandage,
      'irritasyon' => LucideIcons.flame,
      _ => LucideIcons.smile,
    };

/// Check-in: stres düzeyi 1–5.
IconData stressGlyph(int level) => switch (level) {
      1 => LucideIcons.smile,
      2 => LucideIcons.smile,
      3 => LucideIcons.meh,
      4 => LucideIcons.frown,
      _ => LucideIcons.annoyed,
    };
