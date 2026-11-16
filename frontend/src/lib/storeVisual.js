/** Aileye göre hue; konsantrasyon arttıkça hafif koyulaşır (görselleri karartmadan). */
const PALETTES = {
  serum: { h: 168, s: 42 },
  brightening: { h: 198, s: 38 },
  acid: { h: 348, s: 36 },
  barrier: { h: 192, s: 30 },
  moisturizer: { h: 192, s: 30 },
  eye: { h: 262, s: 28 },
  sunscreen: { h: 38, s: 48 },
};

/** Etiketten ortalama yüzde / sayı çıkarır (ör. "%4-5" → 4.5). */
export function parseConcentration(label) {
  const m = String(label || "").match(/(\d+(?:[.,]\d+)?)\s*(?:[-–—]\s*(\d+(?:[.,]\d+)?))?/);
  if (!m) return null;
  const a = Number.parseFloat(m[1].replace(",", "."));
  const b = m[2] ? Number.parseFloat(m[2].replace(",", ".")) : a;
  if (!Number.isFinite(a) || !Number.isFinite(b)) return null;
  return (a + b) / 2;
}

/** Aynı dose_key içinde 0 (açık) … 1 (koyu). */
export function buildStrengthIndex(products) {
  const byKey = new Map();
  for (const p of products || []) {
    const key = p.dose_key || p.slug;
    if (!byKey.has(key)) byKey.set(key, []);
    byKey.get(key).push(p);
  }
  const out = new Map();
  for (const [, group] of byKey) {
    const scored = group.map((p) => ({ slug: p.slug, v: parseConcentration(p.size_label) }));
    const vals = scored.map((s) => s.v).filter((v) => v != null);
    const min = vals.length ? Math.min(...vals) : 0;
    const max = vals.length ? Math.max(...vals) : 1;
    for (const s of scored) {
      let t = 0.35;
      if (s.v != null && max > min) t = (s.v - min) / (max - min);
      else if (group.length === 1) t = 0.4;
      out.set(s.slug, Math.max(0, Math.min(1, t)));
    }
  }
  return out;
}

export function strengthFor(product, index) {
  if (!product?.slug) return 0.35;
  if (index?.has(product.slug)) return index.get(product.slug);
  return 0.35;
}

export function visualPalette(visual) {
  return PALETTES[visual] || PALETTES.serum;
}

/** Kart zemini / levha / border — görseli siyahlaştırmadan ton ayrımı. */
export function tintFor(product, strength = 0.35) {
  const { h, s } = visualPalette(product?.visual);
  const sat = s + strength * 8;
  const light = 86 - strength * 18;
  const deep = 72 - strength * 16;
  const edgeL = Math.max(36, deep - 10);
  return {
    face: `linear-gradient(145deg, hsl(${h} ${sat}% ${light}%), hsl(${h} ${Math.min(52, sat + 6)}% ${deep}%))`,
    edge: `hsl(${h} ${sat + 4}% ${edgeL}%)`,
    solid: `hsl(${h} ${sat}% ${Math.max(38, deep - 4)}%)`,
    wash: `hsl(${h} ${sat}% ${Math.max(42, deep)}% / ${0.06 + strength * 0.12})`,
    cardBg: `linear-gradient(165deg, #f7f3ec 0%, hsl(${h} ${Math.max(16, sat - 6)}% ${92 - strength * 8}%) 55%, hsl(${h} ${sat}% ${86 - strength * 12}%) 100%)`,
    border: `hsl(${h} ${sat}% ${Math.max(40, deep)}% / ${0.28 + strength * 0.22})`,
    bar: `linear-gradient(90deg, hsl(${h} ${sat}% ${light}%), hsl(${h} ${sat + 4}% ${deep}%))`,
    text: "#0b3d38",
    strength,
  };
}

/** Görsellerde hafif doygunluk; brightness’i düşük tutma (siyahlaşma yok). */
export function imageFilter(strength = 0.35) {
  const saturate = 1 + strength * 0.18;
  const contrast = 1 + strength * 0.04;
  return `saturate(${saturate.toFixed(3)}) contrast(${contrast.toFixed(3)})`;
}
