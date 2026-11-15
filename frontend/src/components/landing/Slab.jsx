/** Yüz ve kenar renkleri: mobil uygulamadaki anlamlarıyla (bal = güneş, su mavisi, lavanta = akşam, pudra = raf). */
const TONES = {
  honey: { face: "linear-gradient(145deg, #f8dc92, #e8b44e)", edge: "#b98524", fg: "#5b3a06" },
  water: { face: "linear-gradient(145deg, #c6e3f1, #7fb7d6)", edge: "#3f7fa3", fg: "#12384f" },
  lilac: { face: "linear-gradient(145deg, #ddd5f2, #a99bd6)", edge: "#6b599c", fg: "#2e2350" },
  blush: { face: "linear-gradient(145deg, #f6d8e1, #dda0b5)", edge: "#954f69", fg: "#4b2435" },
  forest: { face: "linear-gradient(145deg, #17907f, #0f766e)", edge: "#0b3d38", fg: "#f7f3ec" },
  ink: { face: "linear-gradient(145deg, #135a52, #0b3d38)", edge: "#041f1c", fg: "#f7f3ec" },
  cream: { face: "linear-gradient(145deg, #ffffff, #f0eadc)", edge: "#cfc6b3", fg: "#0b3d38" },
  // Mağazadaki uygulama ikonunun zemini.
  app: { face: "linear-gradient(145deg, #2dd4bf, #0d9488)", edge: "#0a5f58", fg: "#ffffff" },
};

/**
 * Kalınlığı olan levha. `depth` piksel kadar, 2 piksel aralıklı katman dizer; sahne döndükçe kenar gerçekten görünür.
 * İçerik yüzün `lift` piksel önünde durur, böylece simge levhanın üstünde yüzer.
 */
export function Slab({ tone = "cream", depth = 10, radius = 16, lift = 0, className = "", style, children }) {
  const colors = TONES[tone] || TONES.cream;
  const layers = Math.max(1, Math.round(depth / 2));
  return (
    <span className={`slab ${className}`} style={{ "--slab-r": `${radius}px`, color: colors.fg, ...style }}>
      {Array.from({ length: layers }, (_, i) => (
        <span
          key={i}
          className="slab__layer"
          style={{
            background: colors.edge,
            transform: `translateZ(${-(layers - i) * 2}px)`,
            boxShadow: i === 0 ? "0 22px 30px -12px rgba(6, 43, 39, 0.45)" : undefined,
          }}
        />
      ))}
      <span className="slab__face" style={{ background: colors.face }}>
        <span className="slab__lift" style={{ transform: `translateZ(${lift}px)` }}>
          {children}
        </span>
      </span>
    </span>
  );
}

/** Çizgi ikonlu üç boyutlu simge. Üst öğede `.scene-3d` (bakış noktası) bulunmalı. */
export function Symbol3D({ icon, tone = "forest", size = 64, rotate = "rotateY(-22deg) rotateX(14deg)", className = "" }) {
  const Icon = icon;
  return (
    <span className={`pose-3d ${className}`} style={{ width: size, height: size, transform: rotate }} aria-hidden="true">
      <Slab
        tone={tone}
        depth={Math.round(size / 6)}
        radius={Math.round(size * 0.28)}
        lift={Math.round(size / 7)}
        style={{ width: size, height: size }}
      >
        <Icon style={{ width: size * 0.48, height: size * 0.48 }} strokeWidth={2.1} />
      </Slab>
    </span>
  );
}
