/**
 * SeverityTest - Concern'e özel klinik şiddet testi
 */
import { useState } from "react";

const SEVERITY_TESTS = {
  acne: {
    title: "Akne Değerlendirme Testi",
    subtitle: "Şu an yüzündeki durumu en iyi tanımlayan seçenekleri işaretle",
    icon: "😤",
    questions: [
      {
        id: "active_count",
        text: "Yüzünde kaç aktif sivilce/kızarıklık var?",
        options: [
          { label: "Yok veya 1-2 tane", score: 0 },
          { label: "3-10 tane", score: 1 },
          { label: "10-25 tane", score: 2 },
          { label: "25'ten fazla / sayamıyorum", score: 3 },
        ],
      },
      {
        id: "blackheads",
        text: "Siyah nokta veya beyaz nokta durumun?",
        options: [
          { label: "Yok veya çok az", score: 0 },
          { label: "Burun çevresinde var", score: 1 },
          { label: "Burun + alın + çene yaygın", score: 2 },
        ],
      },
      {
        id: "cystic",
        text: "Derin, ağrılı, şişmiş sivilceler (kistik) var mı?",
        options: [
          { label: "Hayır, yüzeysel sivilceler", score: 0 },
          { label: "Ara sıra 1-2 tane oluyor", score: 1 },
          { label: "Sık sık derin sivilceler çıkıyor", score: 2 },
          { label: "Sürekli var, çok ağrılı", score: 3 },
        ],
      },
      {
        id: "frequency",
        text: "Yeni sivilceler ne sıklıkla çıkıyor?",
        options: [
          { label: "Ayda 1-2 kez", score: 0 },
          { label: "Haftada 1-2 kez", score: 1 },
          { label: "Neredeyse her gün yenisi çıkıyor", score: 2 },
        ],
      },
      {
        id: "scarring",
        text: "Sivilce izi (skar) kalıyor mu?",
        options: [
          { label: "Hayır, iz kalmıyor", score: 0 },
          { label: "Hafif kırmızı izler kalıyor (geçici)", score: 1 },
          { label: "Kalıcı çukur veya kabartı izleri var", score: 2 },
        ],
      },
    ],
  },

  aging: {
    title: "Yaşlanma Belirtileri Testi",
    subtitle: "Aynada yüzünü incele ve en uygun seçenekleri işaretle",
    icon: "✨",
    questions: [
      {
        id: "fine_lines",
        text: "İnce çizgiler (mimik çizgileri) durumun?",
        options: [
          { label: "Hiç yok veya sadece gülünce belli", score: 0 },
          { label: "Göz çevresi ve alında hafif çizgiler", score: 1 },
          { label: "Dinlenirken de belirgin çizgiler var", score: 2 },
        ],
      },
      {
        id: "deep_wrinkles",
        text: "Derin kırışıklıklar var mı?",
        options: [
          { label: "Hayır", score: 0 },
          { label: "Alın veya göz kenarında 1-2 tane", score: 1 },
          { label: "Birden fazla bölgede belirgin kırışıklıklar", score: 2 },
          { label: "Yüz genelinde derin kırışıklıklar", score: 3 },
        ],
      },
      {
        id: "sagging",
        text: "Cilt sarkması hissediyor musun?",
        options: [
          { label: "Hayır, cildim sıkı", score: 0 },
          { label: "Çene hattında hafif gevşeklik", score: 1 },
          { label: "Yanak ve çene belirgin sarkıyor", score: 2 },
          { label: "Boyun dahil genel sarkma var", score: 3 },
        ],
      },
      {
        id: "elasticity",
        text: "Cildin elastikiyetini test et: yanağını hafifçe çimdikle ve bırak. Ne oluyor?",
        options: [
          { label: "Anında geri dönüyor", score: 0 },
          { label: "1-2 saniye gecikiyor", score: 1 },
          { label: "Yavaş geri dönüyor (3+ saniye)", score: 2 },
        ],
      },
      {
        id: "spots",
        text: "Yaş lekeleri veya pigment değişiklikleri var mı?",
        options: [
          { label: "Hayır", score: 0 },
          { label: "Birkaç küçük leke", score: 1 },
          { label: "Belirgin ve yaygın lekelenmeler", score: 2 },
        ],
      },
    ],
  },

  dryness: {
    title: "Kuruluk Değerlendirme Testi",
    subtitle: "Cildin nemsiz halini düşünerek cevapla",
    icon: "🏜️",
    questions: [
      {
        id: "tightness",
        text: "Yüzünü yıkadıktan sonra ne hissediyorsun?",
        options: [
          { label: "Normal, rahat hissediyorum", score: 0 },
          { label: "Hafif bir sıkılık hissi", score: 1 },
          { label: "Belirgin gerginlik, nemlendirici sürmem lazım", score: 2 },
          { label: "Çok gergin, acıyabilir", score: 3 },
        ],
      },
      {
        id: "flaking",
        text: "Pul pul dökülme var mı?",
        options: [
          { label: "Hayır", score: 0 },
          { label: "Burun kenarlarında hafif", score: 1 },
          { label: "Yanak ve alın bölgesinde belirgin", score: 2 },
          { label: "Yüz genelinde yaygın", score: 3 },
        ],
      },
      {
        id: "itching",
        text: "Cildin kaşınıyor mu?",
        options: [
          { label: "Hayır", score: 0 },
          { label: "Ara sıra, özellikle soğukta", score: 1 },
          { label: "Sık sık kaşıntı oluyor", score: 2 },
        ],
      },
      {
        id: "cracking",
        text: "Çatlak veya yarık oluşuyor mu?",
        options: [
          { label: "Hayır", score: 0 },
          { label: "Dudak çevresinde", score: 1 },
          { label: "Birden fazla bölgede çatlaklar", score: 2 },
          { label: "Derin çatlaklar, kanayabilir", score: 3 },
        ],
      },
      {
        id: "makeup",
        text: "Makyaj veya nemlendirici uygulama deneyimin?",
        options: [
          { label: "Normal tutuyor, sorun yok", score: 0 },
          { label: "Topaklanıyor veya çabuk kuruyor", score: 1 },
          { label: "Nemlendirici bile yetmiyor, hemen emiyor", score: 2 },
        ],
      },
    ],
  },

  pigmentation: {
    title: "Leke Değerlendirme Testi",
    subtitle: "Yüzündeki leke/ton eşitsizliği durumunu değerlendir",
    icon: "🎯",
    questions: [
      {
        id: "spot_count",
        text: "Yüzünde kaç leke/koyu alan var?",
        options: [
          { label: "1-2 küçük leke", score: 0 },
          { label: "3-5 leke", score: 1 },
          { label: "5'ten fazla veya geniş alanlar", score: 2 },
        ],
      },
      {
        id: "area_size",
        text: "Etkilenen toplam alan ne kadar büyük?",
        options: [
          { label: "Çok küçük, nokta noktalar", score: 0 },
          { label: "Yanaklar veya alında bölgesel", score: 1 },
          { label: "Yüzün büyük bölümünde", score: 2 },
          { label: "Tüm yüz genelinde ton eşitsizliği", score: 3 },
        ],
      },
      {
        id: "color_intensity",
        text: "Lekelerin renk yoğunluğu?",
        options: [
          { label: "Çok hafif, yakından bakınca belli", score: 0 },
          { label: "Belirgin ama makyajla kapatılır", score: 1 },
          { label: "Koyu, zor kapatılır", score: 2 },
          { label: "Çok koyu, belirgin kontrast", score: 3 },
        ],
      },
      {
        id: "sun_effect",
        text: "Güneşe çıkınca lekeler koyulaşıyor mu?",
        options: [
          { label: "Fark etmedim", score: 0 },
          { label: "Biraz koyulaşıyor", score: 1 },
          { label: "Çok belirgin koyulaşma", score: 2 },
        ],
      },
      {
        id: "spreading",
        text: "Son 6 ayda lekeler arttı mı?",
        options: [
          { label: "Aynı kaldı", score: 0 },
          { label: "Biraz arttı", score: 1 },
          { label: "Belirgin şekilde arttı / yenileri çıktı", score: 2 },
        ],
      },
    ],
  },

  sensitivity: {
    title: "Hassasiyet Değerlendirme Testi",
    subtitle: "Cildin tepkilerini en iyi tanımlayan seçenekleri işaretle",
    icon: "🌸",
    questions: [
      {
        id: "redness_freq",
        text: "Cildinde kızarıklık ne sıklıkla oluyor?",
        options: [
          { label: "Nadiren", score: 0 },
          { label: "Haftada 1-2 kez", score: 1 },
          { label: "Neredeyse her gün", score: 2 },
          { label: "Sürekli kırmızı", score: 3 },
        ],
      },
      {
        id: "stinging",
        text: "Batma veya yanma hissi yaşıyor musun?",
        options: [
          { label: "Hayır", score: 0 },
          { label: "Bazı maddelerle oluyor", score: 1 },
          { label: "Çoğu maddede batıyor", score: 2 },
          { label: "Su bile batıyor", score: 3 },
        ],
      },
      {
        id: "product_reaction",
        text: "Yeni madde denediğinde ne oluyor?",
        options: [
          { label: "Genellikle sorun olmuyor", score: 0 },
          { label: "Bazen kızarıklık/kaşıntı yapıyor", score: 1 },
          { label: "Çoğu yeni maddeye tepki veriyor", score: 2 },
        ],
      },
      {
        id: "redness_duration",
        text: "Kızarıklık ne kadar sürüyor?",
        options: [
          { label: "Birkaç dakika", score: 0 },
          { label: "Saatlerce", score: 1 },
          { label: "Günlerce / hiç geçmiyor", score: 2 },
        ],
      },
      {
        id: "triggers",
        text: "Aşağıdakilerden kaç tanesi cildini tetikliyor? (Güneş, rüzgar, soğuk, sıcak su, parfüm, stres)",
        options: [
          { label: "0-1 tanesi", score: 0 },
          { label: "2-3 tanesi", score: 1 },
          { label: "4-5 tanesi", score: 2 },
          { label: "Hepsi veya çoğu", score: 3 },
        ],
      },
    ],
  },
};

function calculateScore(answers, maxPossible) {
  const total = Object.values(answers).reduce((sum, val) => sum + val, 0);
  const normalized = Math.round((total / maxPossible) * 9) + 1;
  return Math.min(10, Math.max(1, normalized));
}

function getSeverityLabel(score) {
  if (score <= 3) return { text: "Hafif", color: "text-green-600", bg: "bg-green-100" };
  if (score <= 6) return { text: "Orta", color: "text-amber-600", bg: "bg-amber-100" };
  return { text: "Şiddetli", color: "text-red-600", bg: "bg-red-100" };
}

export default function SeverityTest({ concern, onScoreChange }) {
  const [answers, setAnswers] = useState({});
  const test = SEVERITY_TESTS[concern];
  if (!test) return null;

  const maxPossible = test.questions.reduce(
    (sum, q) => sum + Math.max(...q.options.map((o) => o.score)),
    0
  );

  const answeredCount = Object.keys(answers).length;
  const totalCount = test.questions.length;
  const isComplete = answeredCount === totalCount;
  const score = isComplete ? calculateScore(answers, maxPossible) : null;
  const severity = score ? getSeverityLabel(score) : null;

  const handleSelect = (qId, optScore) => {
    const newAnswers = { ...answers, [qId]: optScore };
    setAnswers(newAnswers);

    if (Object.keys(newAnswers).length === totalCount) {
      const s = calculateScore(newAnswers, maxPossible);
      onScoreChange(s);
    }
  };

  return (
    <div className="card space-y-5 border-teal-100 bg-teal-50/20">
      <div className="flex items-center gap-2">
        <span className="text-2xl">{test.icon}</span>
        <div>
          <h3 className="font-bold text-gray-900 text-sm">{test.title}</h3>
          <p className="text-xs text-gray-500">{test.subtitle}</p>
        </div>
      </div>

      <div className="text-xs text-gray-400 text-right">
        {answeredCount}/{totalCount} cevaplandı
      </div>

      {test.questions.map((q) => (
        <div key={q.id} className="space-y-2">
          <p className="text-sm font-medium text-gray-700">{q.text}</p>
          <div className="grid grid-cols-1 gap-1.5">
            {q.options.map((opt, oi) => {
              const isSelected = answers[q.id] === opt.score && answers[q.id] !== undefined;
              const isQuestionAnswered = q.id in answers;
              return (
                <button
                  key={oi}
                  onClick={() => handleSelect(q.id, opt.score)}
                  className={`text-left px-3 py-2.5 rounded-xl text-sm transition-all border ${
                    isSelected
                      ? "border-teal-500 bg-teal-50 text-teal-800 font-medium"
                      : isQuestionAnswered
                      ? "border-gray-100 bg-gray-50 text-gray-400"
                      : "border-gray-200 bg-white text-gray-700 hover:border-teal-300 hover:bg-teal-50/30"
                  }`}
                >
                  <span className="flex items-center gap-2">
                    <span className={`w-4 h-4 rounded-full border-2 flex items-center justify-center shrink-0 ${
                      isSelected ? "border-teal-500" : "border-gray-300"
                    }`}>
                      {isSelected && <span className="w-2 h-2 rounded-full bg-teal-500" />}
                    </span>
                    {opt.label}
                  </span>
                </button>
              );
            })}
          </div>
        </div>
      ))}

      {/* Score Result */}
      {isComplete && severity && (
        <div className={`rounded-2xl p-4 text-center ${severity.bg}`}>
          <p className="text-xs text-gray-500 mb-1">Hesaplanan Şiddet Skoru</p>
          <div className="flex items-center justify-center gap-3">
            <span className={`text-3xl font-bold ${severity.color}`}>{score}/10</span>
            <span className={`text-sm font-semibold px-3 py-1 rounded-full ${severity.bg} ${severity.color}`}>
              {severity.text}
            </span>
          </div>
        </div>
      )}

      {!isComplete && (
        <p className="text-xs text-center text-gray-400">
          Tüm soruları cevapla, şiddet skorun otomatik hesaplansın
        </p>
      )}
    </div>
  );
}
