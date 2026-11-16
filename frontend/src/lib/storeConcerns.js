import { CircleDot, Clock3, Droplets, Eye, Flame, Scan, ShieldAlert, Sparkles } from "lucide-react";

/** Sorun → renk / 3D ton / ikon (mağaza filtre ve etiketleri). */
export const CONCERN_META = {
  acne: {
    icon: Flame,
    tone: "blush",
    chip: "bg-[#f6d8e1] text-[#4b2435] border-[#dda0b5]",
    soft: "#f6d8e1",
    solid: "#954f69",
  },
  pigmentation: {
    icon: Sparkles,
    tone: "honey",
    chip: "bg-[#f5e7c6] text-[#5b3a06] border-[#e8b44e]",
    soft: "#f5e7c6",
    solid: "#b98524",
  },
  dryness: {
    icon: Droplets,
    tone: "water",
    chip: "bg-[#c6e3f1] text-[#12384f] border-[#7fb7d6]",
    soft: "#c6e3f1",
    solid: "#3f7fa3",
  },
  aging: {
    icon: Clock3,
    tone: "lilac",
    chip: "bg-[#ddd5f2] text-[#2e2350] border-[#a99bd6]",
    soft: "#ddd5f2",
    solid: "#6b599c",
  },
  sensitivity: {
    icon: ShieldAlert,
    tone: "cream",
    chip: "bg-[#f0eadc] text-[#0b3d38] border-[#cfc6b3]",
    soft: "#f0eadc",
    solid: "#8a6a4a",
  },
  undereye: {
    icon: Eye,
    tone: "lilac",
    chip: "bg-[#e4ddf5] text-[#2e2350] border-[#b7a8de]",
    soft: "#e4ddf5",
    solid: "#5c4d8a",
  },
  oiliness: {
    icon: Droplets,
    tone: "honey",
    chip: "bg-[#f8e9c2] text-[#5b3a06] border-[#e0c06a]",
    soft: "#f8e9c2",
    solid: "#a88420",
  },
  pores: {
    icon: Scan,
    tone: "forest",
    chip: "bg-[#d5ebe7] text-[#0b3d38] border-[#7fb3aa]",
    soft: "#d5ebe7",
    solid: "#0f766e",
  },
};

export function concernMeta(id) {
  return (
    CONCERN_META[id] || {
      icon: CircleDot,
      tone: "forest",
      chip: "bg-paper text-ink-soft border-rule",
      soft: "#f7f3ec",
      solid: "#0f766e",
    }
  );
}
