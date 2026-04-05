/**
 * Seçili temanın desenini (kalp, ayıcık, yaprak vb.) sayfa arka planında gösterir.
 * Konumlar sabit — hydration / SSR uyumu için rastgele kullanılmaz.
 */

const HEART_POSITIONS = [
  { left: "8%", top: "12%", size: 14, rotate: -8 },
  { left: "88%", top: "18%", size: 12, rotate: 12 },
  { left: "22%", top: "42%", size: 11, rotate: 5 },
  { left: "72%", top: "38%", size: 13, rotate: -14 },
  { left: "45%", top: "8%", size: 10, rotate: 0 },
  { left: "15%", top: "78%", size: 12, rotate: 18 },
  { left: "85%", top: "72%", size: 11, rotate: -6 },
  { left: "50%", top: "88%", size: 10, rotate: 10 },
  { left: "5%", top: "55%", size: 9, rotate: -12 },
  { left: "92%", top: "48%", size: 10, rotate: 8 },
];

const BEAR_POSITIONS = [
  { left: "10%", top: "20%", size: 18, rotate: -6, char: "🧸" },
  { left: "82%", top: "15%", size: 16, rotate: 10, char: "🧸" },
  { left: "25%", top: "65%", size: 15, rotate: 4, char: "🧸" },
  { left: "70%", top: "58%", size: 17, rotate: -8, char: "🧸" },
  { left: "48%", top: "35%", size: 14, rotate: 0, char: "🐻" },
  { left: "12%", top: "85%", size: 14, rotate: 12, char: "🧸" },
  { left: "88%", top: "82%", size: 13, rotate: -10, char: "🧸" },
];

const LEAF_CHARS = ["🌿", "🍃", "🌱"];
const LEAF_POSITIONS = [
  { left: "12%", top: "18%", i: 0, rotate: -20 },
  { left: "78%", top: "22%", i: 1, rotate: 15 },
  { left: "35%", top: "55%", i: 2, rotate: 8 },
  { left: "65%", top: "48%", i: 0, rotate: -12 },
  { left: "8%", top: "75%", i: 1, rotate: 25 },
  { left: "90%", top: "70%", i: 2, rotate: -18 },
];

const CAT_CHARS = ["🐱", "🐾", "😺", "🐈"];
const CAT_POSITIONS = [
  { left: "14%", top: "25%", i: 0, rotate: -5 },
  { left: "80%", top: "20%", i: 1, rotate: 8 },
  { left: "30%", top: "70%", i: 2, rotate: 12 },
  { left: "75%", top: "65%", i: 3, rotate: -10 },
  { left: "50%", top: "40%", i: 0, rotate: 0 },
];

const STAR_POSITIONS = [
  { left: "10%", top: "15%", s: 8 },
  { left: "85%", top: "12%", s: 10 },
  { left: "25%", top: "35%", s: 7 },
  { left: "70%", top: "30%", s: 9 },
  { left: "45%", top: "18%", s: 6 },
  { left: "15%", top: "60%", s: 8 },
  { left: "88%", top: "55%", s: 7 },
  { left: "50%", top: "75%", s: 10 },
  { left: "5%", top: "45%", s: 6 },
  { left: "92%", top: "40%", s: 8 },
];

export default function ThemePatternOverlay({ pattern, className = "" }) {
  if (!pattern) return null;

  const wrap = `absolute inset-0 overflow-hidden pointer-events-none z-0 ${className}`;

  if (pattern === "hearts") {
    return (
      <div className={wrap} aria-hidden>
        {HEART_POSITIONS.map((p, idx) => (
          <span
            key={idx}
            className="absolute text-pink-400/35 select-none"
            style={{
              fontSize: p.size,
              left: p.left,
              top: p.top,
              transform: `rotate(${p.rotate}deg)`,
            }}
          >
            &#10084;
          </span>
        ))}
      </div>
    );
  }

  if (pattern === "bears") {
    return (
      <div className={wrap} aria-hidden>
        {BEAR_POSITIONS.map((p, idx) => (
          <span
            key={idx}
            className="absolute select-none opacity-[0.22]"
            style={{
              fontSize: p.size,
              left: p.left,
              top: p.top,
              transform: `rotate(${p.rotate}deg)`,
            }}
          >
            {p.char}
          </span>
        ))}
      </div>
    );
  }

  if (pattern === "leaves") {
    return (
      <div className={wrap} aria-hidden>
        {LEAF_POSITIONS.map((p, idx) => (
          <span
            key={idx}
            className="absolute text-green-600/25 select-none"
            style={{
              fontSize: 13 + (idx % 3),
              left: p.left,
              top: p.top,
              transform: `rotate(${p.rotate}deg)`,
            }}
          >
            {LEAF_CHARS[p.i % 3]}
          </span>
        ))}
      </div>
    );
  }

  if (pattern === "cats") {
    return (
      <div className={wrap} aria-hidden>
        {CAT_POSITIONS.map((p, idx) => (
          <span
            key={idx}
            className="absolute select-none opacity-[0.2]"
            style={{
              fontSize: 12 + (idx % 3),
              left: p.left,
              top: p.top,
              transform: `rotate(${p.rotate}deg)`,
            }}
          >
            {CAT_CHARS[p.i % 4]}
          </span>
        ))}
      </div>
    );
  }

  if (pattern === "landscape") {
    return (
      <div className={wrap} aria-hidden>
        <div className="absolute bottom-0 left-0 right-0 h-1/3 bg-gradient-to-t from-violet-200/25 to-transparent" />
        <span className="absolute bottom-2 left-3 text-sm opacity-25">🏔️</span>
        <span className="absolute bottom-2 right-5 text-sm opacity-25">🌸</span>
        <span className="absolute top-6 right-8 text-xs opacity-20">☁️</span>
      </div>
    );
  }

  if (pattern === "sunburst") {
    return (
      <div
        className={`${wrap} opacity-[0.22]`}
        aria-hidden
        style={{
          background:
            "conic-gradient(from 180deg at 50% 75%, #f0abfc 0deg, transparent 42deg, #fdba74 118deg, transparent 198deg, #e879f9 278deg, transparent 360deg)",
        }}
      />
    );
  }

  if (pattern === "waves") {
    return (
      <div className={wrap} aria-hidden>
        <div className="absolute -bottom-1 left-0 right-0 h-14 bg-[repeating-linear-gradient(90deg,transparent,transparent_8px,rgba(14,165,233,0.12)_8px,rgba(14,165,233,0.12)_16px)] rounded-t-full scale-x-150 opacity-80" />
        <div className="absolute bottom-2 left-0 right-0 h-9 bg-[repeating-linear-gradient(90deg,transparent,transparent_6px,rgba(6,182,212,0.14)_6px,rgba(6,182,212,0.14)_14px)] rounded-t-full scale-x-125 opacity-70" />
      </div>
    );
  }

  if (pattern === "stars") {
    return (
      <div className={wrap} aria-hidden>
        {STAR_POSITIONS.map((p, idx) => (
          <span
            key={idx}
            className="absolute text-indigo-500/30 select-none"
            style={{
              fontSize: p.s,
              left: p.left,
              top: p.top,
            }}
          >
            ✦
          </span>
        ))}
      </div>
    );
  }

  return null;
}
