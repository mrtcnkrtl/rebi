/**
 * FaceZoneSelector - İnteraktif yüz bölge seçici (akne lokasyon analizi)
 *
 * Bölgeler ve dermatokozmetik anlamları:
 * - Alın (Forehead): Stres, sindirim, T-bölge yağlanma
 * - Burun (Nose): Sebum üretimi, gözenek
 * - Sol/Sağ yanak (Cheeks): Bakteri (telefon, yastık), solunum
 * - Çene (Chin/Jaw): Hormonal (özellikle kadınlarda adet döngüsü)
 * - Şakaklar (Temples): Saç bakımı, stres
 */
import { useState } from "react";

const ZONES = [
  { id: "forehead", label: "Alın", cause: "Stres, sindirim, T-bölge yağlanma" },
  { id: "nose", label: "Burun", cause: "Sebum üretimi, gözenek problemi" },
  { id: "left_cheek", label: "Sol Yanak", cause: "Telefon bakterisi, yastık kirliliği" },
  { id: "right_cheek", label: "Sağ Yanak", cause: "Telefon bakterisi, yastık kirliliği" },
  { id: "chin", label: "Çene / Alt Çene", cause: "Hormonal (özellikle adet döngüsü)" },
  { id: "temples", label: "Şakaklar", cause: "Saç bakımı, stres" },
];

export default function FaceZoneSelector({ value = [], onChange }) {
  const [hovered, setHovered] = useState(null);

  const toggle = (zoneId) => {
    if (value.includes(zoneId)) {
      onChange(value.filter((z) => z !== zoneId));
    } else {
      onChange([...value, zoneId]);
    }
  };

  const isActive = (id) => value.includes(id);
  const isHover = (id) => hovered === id;

  const getZoneFill = (id) => {
    if (isActive(id)) return "rgba(239, 68, 68, 0.35)";
    if (isHover(id)) return "rgba(239, 68, 68, 0.15)";
    return "rgba(0,0,0,0)";
  };

  const getZoneStroke = (id) => {
    if (isActive(id)) return "#ef4444";
    if (isHover(id)) return "#fca5a5";
    return "rgba(0,0,0,0.08)";
  };

  const selectedZones = ZONES.filter((z) => value.includes(z.id));

  return (
    <div className="space-y-4">
      <div className="flex justify-center">
        <div className="relative">
          <svg width="220" height="280" viewBox="0 0 220 280" fill="none" className="drop-shadow-sm">
            {/* Hair */}
            <ellipse cx="110" cy="65" rx="82" ry="55" fill="#8B6F47" />

            {/* Face shape */}
            <path d="M 45 100 Q 38 140 50 180 Q 60 220 80 245 Q 95 260 110 265 Q 125 260 140 245 Q 160 220 170 180 Q 182 140 175 100 Q 170 72 110 65 Q 50 72 45 100 Z"
              fill="#FDEBD0" stroke="#E8C9A0" strokeWidth="1.5" />

            {/* Ears */}
            <ellipse cx="42" cy="145" rx="8" ry="18" fill="#F5D5B5" stroke="#E8C9A0" strokeWidth="1" />
            <ellipse cx="178" cy="145" rx="8" ry="18" fill="#F5D5B5" stroke="#E8C9A0" strokeWidth="1" />

            {/* Eyes */}
            <ellipse cx="82" cy="135" rx="12" ry="7" fill="white" stroke="#C4956A" strokeWidth="0.8" />
            <ellipse cx="138" cy="135" rx="12" ry="7" fill="white" stroke="#C4956A" strokeWidth="0.8" />
            <circle cx="82" cy="135" r="4" fill="#5B4636" />
            <circle cx="138" cy="135" r="4" fill="#5B4636" />
            <circle cx="83.5" cy="133.5" r="1.5" fill="white" />
            <circle cx="139.5" cy="133.5" r="1.5" fill="white" />

            {/* Eyebrows */}
            <path d="M 65 122 Q 82 116 98 122" stroke="#7A6040" strokeWidth="2" fill="none" strokeLinecap="round" />
            <path d="M 122 122 Q 138 116 155 122" stroke="#7A6040" strokeWidth="2" fill="none" strokeLinecap="round" />

            {/* Nose */}
            <path d="M 107 140 Q 105 160 100 170 Q 105 174 110 175 Q 115 174 120 170 Q 115 160 113 140"
              stroke="#D4A080" strokeWidth="1.2" fill="none" />

            {/* Mouth */}
            <path d="M 92 200 Q 100 195 110 196 Q 120 195 128 200" stroke="#D4A080" strokeWidth="1.5" fill="none" strokeLinecap="round" />
            <path d="M 92 200 Q 110 210 128 200" stroke="#E8B0A0" strokeWidth="1" fill="#F0C0B0" opacity="0.5" />

            {/* ===== CLICKABLE ZONES ===== */}

            {/* Forehead zone */}
            <ellipse cx="110" cy="95" rx="52" ry="22"
              fill={getZoneFill("forehead")} stroke={getZoneStroke("forehead")} strokeWidth="1.5" strokeDasharray={isActive("forehead") ? "0" : "4 2"}
              className="cursor-pointer transition-all duration-200"
              onClick={() => toggle("forehead")}
              onMouseEnter={() => setHovered("forehead")}
              onMouseLeave={() => setHovered(null)}
            />

            {/* Nose zone */}
            <ellipse cx="110" cy="163" rx="14" ry="20"
              fill={getZoneFill("nose")} stroke={getZoneStroke("nose")} strokeWidth="1.5" strokeDasharray={isActive("nose") ? "0" : "4 2"}
              className="cursor-pointer transition-all duration-200"
              onClick={() => toggle("nose")}
              onMouseEnter={() => setHovered("nose")}
              onMouseLeave={() => setHovered(null)}
            />

            {/* Left cheek zone */}
            <ellipse cx="68" cy="175" rx="22" ry="28"
              fill={getZoneFill("left_cheek")} stroke={getZoneStroke("left_cheek")} strokeWidth="1.5" strokeDasharray={isActive("left_cheek") ? "0" : "4 2"}
              className="cursor-pointer transition-all duration-200"
              onClick={() => toggle("left_cheek")}
              onMouseEnter={() => setHovered("left_cheek")}
              onMouseLeave={() => setHovered(null)}
            />

            {/* Right cheek zone */}
            <ellipse cx="152" cy="175" rx="22" ry="28"
              fill={getZoneFill("right_cheek")} stroke={getZoneStroke("right_cheek")} strokeWidth="1.5" strokeDasharray={isActive("right_cheek") ? "0" : "4 2"}
              className="cursor-pointer transition-all duration-200"
              onClick={() => toggle("right_cheek")}
              onMouseEnter={() => setHovered("right_cheek")}
              onMouseLeave={() => setHovered(null)}
            />

            {/* Chin/Jaw zone */}
            <ellipse cx="110" cy="235" rx="30" ry="22"
              fill={getZoneFill("chin")} stroke={getZoneStroke("chin")} strokeWidth="1.5" strokeDasharray={isActive("chin") ? "0" : "4 2"}
              className="cursor-pointer transition-all duration-200"
              onClick={() => toggle("chin")}
              onMouseEnter={() => setHovered("chin")}
              onMouseLeave={() => setHovered(null)}
            />

            {/* Left temple zone */}
            <ellipse cx="52" cy="115" rx="12" ry="18"
              fill={getZoneFill("temples")} stroke={getZoneStroke("temples")} strokeWidth="1.5" strokeDasharray={isActive("temples") ? "0" : "4 2"}
              className="cursor-pointer transition-all duration-200"
              onClick={() => toggle("temples")}
              onMouseEnter={() => setHovered("temples")}
              onMouseLeave={() => setHovered(null)}
            />

            {/* Right temple zone */}
            <ellipse cx="168" cy="115" rx="12" ry="18"
              fill={getZoneFill("temples")} stroke={getZoneStroke("temples")} strokeWidth="1.5" strokeDasharray={isActive("temples") ? "0" : "4 2"}
              className="cursor-pointer transition-all duration-200"
              onClick={() => toggle("temples")}
              onMouseEnter={() => setHovered("temples")}
              onMouseLeave={() => setHovered(null)}
            />

            {/* Zone labels on hover */}
            {hovered && (
              <text x="110" y="275" textAnchor="middle" fill="#6b7280" fontSize="11" fontWeight="500">
                {ZONES.find((z) => z.id === hovered)?.label}
              </text>
            )}
          </svg>
        </div>
      </div>

      <p className="text-xs text-gray-400 text-center">Aknenin yoğun olduğu bölgelere dokun</p>

      {/* Selected zones info */}
      {selectedZones.length > 0 && (
        <div className="space-y-2">
          {selectedZones.map((zone) => (
            <div key={zone.id} className="flex items-center gap-2 bg-red-50 rounded-xl p-2.5 text-sm">
              <span className="w-2 h-2 rounded-full bg-red-400 shrink-0" />
              <div>
                <span className="font-medium text-red-800">{zone.label}</span>
                <span className="text-red-600 ml-1">— {zone.cause}</span>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
