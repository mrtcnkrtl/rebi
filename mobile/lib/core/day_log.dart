/// Gün içi kayıtların seçenekleri ve sunucuya giden yükleri (`docs/MOBIL-API.md`).
library;

/// Rutin blokları. Adım işaretleri ve "yaptım" kaydı blok başınadır.
const routineBlocks = ['morning', 'evening'];

/// Saat 16'dan önce sabah, sonra akşam rutini öne çıkar.
String blockForTime(DateTime now) => now.hour < 16 ? 'morning' : 'evening';

/// Tek bir su kaydının sınırı; sunucudaki `_MAX_WATER_EVENT_ML` ile aynıdır.
const maxWaterEntryMl = 5000;

/// Panelde "ürün bitti" olarak bir günde tutulan en çok ürün (sunucuyla aynı).
const maxFinishedProductsPerDay = 20;

/// Su için hızlı ekleme miktarları (ml).
const waterQuickAmounts = [100, 200, 250, 330, 500, 750];

/// "Diğer" alanına yazılabilecek en büyük tek seferlik miktar (ml).
const maxCustomWaterMl = 2000;

/// Makyaj temizleme yöntemleri; sunucudaki `_MAKEUP_REMOVAL_METHODS` ile aynıdır.
/// `none`: makyaj temizlenmedi.
const cleansingMethods = ['double', 'cleanser', 'water', 'wipe', 'none'];

/// Makyajın nasıl temizlendiğini kaydeden olay yükü.
Map<String, dynamic> cleansingPayload(String method) =>
    method == 'none' ? {'removed': false, 'method': 'none'} : {'removed': true, 'method': method};

/// Beslenme seçenekleri. `balanced` diğerleriyle birlikte seçilemez.
const nutritionChoices = ['snacks', 'sweets', 'fried_food', 'dairy', 'balanced'];

const _junkChoices = {'snacks', 'sweets', 'fried_food'};

/// Beslenme olayı: her seçenek ayrı bir alan, `junk_food` bunların özeti.
/// Sunucu alanları gün içinde birleştirir; hepsini göndermek kaldırılan seçimi de günceller.
Map<String, dynamic> nutritionPayload(Set<String> selected) => {
      for (final choice in nutritionChoices) choice: selected.contains(choice),
      'junk_food': selected.any(_junkChoices.contains),
    };

/// Kayıtlı beslenme verisinden seçili seçenekler. Eski kayıtlar yalnızca `junk_food: true` taşır.
Set<String> nutritionSelection(Map<String, dynamic> nutrition) {
  final picked = {for (final choice in nutritionChoices) if (nutrition[choice] == true) choice};
  if (picked.isEmpty && nutrition['junk_food'] == true) picked.add('snacks');
  return picked;
}

/// Bir seçim ekranı. Hatırlatıcı eylemleri ve panel bunlardan birini açar.
enum DaySheet { cleansing, nutrition, water, products }
