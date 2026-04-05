import { createContext, useContext, useState, useEffect } from "react";
import { useAuth } from "./AuthContext";

const themes = {
  teal: {
    id: "teal", label: "Klasik Teal", emoji: "🌿",
    primary: "#0d9488", primaryLight: "#ccfbf1", primaryDark: "#115e59",
    accent: "#14b8a6", gradientFrom: "from-teal-50/50", gradientTo: "to-white",
    cardBorder: "border-gray-100", navBg: "bg-white/90",
    btnBg: "bg-teal-600", btnHover: "hover:bg-teal-700", btnShadow: "shadow-teal-600/25",
    btnSecBorder: "border-teal-200", btnSecText: "text-teal-700",
    inputFocus: "focus:border-teal-400 focus:ring-teal-100",
    chipActive: "border-teal-500 bg-teal-50 text-teal-800",
    bg: "bg-gradient-to-b from-teal-50/50 to-white",
    pattern: "",
  },
  pink: {
    id: "pink", label: "Pembe Kalp", emoji: "💗",
    primary: "#db2777", primaryLight: "#fce7f3", primaryDark: "#9d174d",
    accent: "#ec4899", gradientFrom: "from-pink-50/50", gradientTo: "to-white",
    cardBorder: "border-pink-100", navBg: "bg-pink-50/90",
    btnBg: "bg-pink-600", btnHover: "hover:bg-pink-700", btnShadow: "shadow-pink-600/25",
    btnSecBorder: "border-pink-200", btnSecText: "text-pink-700",
    inputFocus: "focus:border-pink-400 focus:ring-pink-100",
    chipActive: "border-pink-500 bg-pink-50 text-pink-800",
    bg: "bg-gradient-to-b from-pink-50/60 to-rose-50/30",
    pattern: "hearts",
  },
  green: {
    id: "green", label: "Yeşil Doğa", emoji: "🌱",
    primary: "#16a34a", primaryLight: "#dcfce7", primaryDark: "#14532d",
    accent: "#22c55e", gradientFrom: "from-green-50/50", gradientTo: "to-white",
    cardBorder: "border-green-100", navBg: "bg-green-50/90",
    btnBg: "bg-green-600", btnHover: "hover:bg-green-700", btnShadow: "shadow-green-600/25",
    btnSecBorder: "border-green-200", btnSecText: "text-green-700",
    inputFocus: "focus:border-green-400 focus:ring-green-100",
    chipActive: "border-green-500 bg-green-50 text-green-800",
    bg: "bg-gradient-to-b from-green-50/50 to-emerald-50/20",
    pattern: "leaves",
  },
  lavender: {
    id: "lavender", label: "Lavanta Manzara", emoji: "🏔️",
    primary: "#7c3aed", primaryLight: "#ede9fe", primaryDark: "#4c1d95",
    accent: "#8b5cf6", gradientFrom: "from-violet-50/50", gradientTo: "to-white",
    cardBorder: "border-violet-100", navBg: "bg-violet-50/90",
    btnBg: "bg-violet-600", btnHover: "hover:bg-violet-700", btnShadow: "shadow-violet-600/25",
    btnSecBorder: "border-violet-200", btnSecText: "text-violet-700",
    inputFocus: "focus:border-violet-400 focus:ring-violet-100",
    chipActive: "border-violet-500 bg-violet-50 text-violet-800",
    bg: "bg-gradient-to-b from-violet-50/50 to-purple-50/20",
    pattern: "landscape",
  },
  cat: {
    id: "cat", label: "Kedi Sever", emoji: "🐱",
    primary: "#ea580c", primaryLight: "#fff7ed", primaryDark: "#9a3412",
    accent: "#f97316", gradientFrom: "from-orange-50/50", gradientTo: "to-amber-50/20",
    cardBorder: "border-orange-100", navBg: "bg-orange-50/90",
    btnBg: "bg-orange-600", btnHover: "hover:bg-orange-700", btnShadow: "shadow-orange-600/25",
    btnSecBorder: "border-orange-200", btnSecText: "text-orange-700",
    inputFocus: "focus:border-orange-400 focus:ring-orange-100",
    chipActive: "border-orange-500 bg-orange-50 text-orange-800",
    bg: "bg-gradient-to-b from-orange-50/40 to-amber-50/20",
    pattern: "cats",
  },
  teddy: {
    id: "teddy", label: "Ayıcık", emoji: "🧸",
    primary: "#b45309", primaryLight: "#fef3c7", primaryDark: "#78350f",
    accent: "#d97706", gradientFrom: "from-amber-50/60", gradientTo: "to-orange-50/30",
    cardBorder: "border-amber-200", navBg: "bg-amber-50/90",
    btnBg: "bg-amber-700", btnHover: "hover:bg-amber-800", btnShadow: "shadow-amber-700/25",
    btnSecBorder: "border-amber-200", btnSecText: "text-amber-900",
    inputFocus: "focus:border-amber-400 focus:ring-amber-100",
    chipActive: "border-amber-600 bg-amber-50 text-amber-950",
    bg: "bg-gradient-to-b from-amber-50/55 via-orange-50/25 to-rose-50/20",
    pattern: "bears",
  },
  /** Rebi Plus — premium */
  sunset: {
    id: "sunset", label: "Gün Batımı", emoji: "🌅", premium: true,
    primary: "#c026d3", primaryLight: "#fae8ff", primaryDark: "#86198f",
    accent: "#f97316", gradientFrom: "from-fuchsia-50/60", gradientTo: "to-orange-50/40",
    cardBorder: "border-fuchsia-100", navBg: "bg-gradient-to-r from-fuchsia-50/90 to-orange-50/80",
    btnBg: "bg-fuchsia-600", btnHover: "hover:bg-fuchsia-700", btnShadow: "shadow-fuchsia-600/25",
    btnSecBorder: "border-fuchsia-200", btnSecText: "text-fuchsia-800",
    inputFocus: "focus:border-fuchsia-400 focus:ring-fuchsia-100",
    chipActive: "border-fuchsia-500 bg-fuchsia-50 text-fuchsia-900",
    bg: "bg-gradient-to-br from-fuchsia-50/70 via-orange-50/40 to-rose-50/50",
    pattern: "sunburst",
    shape: "sunburst",
  },
  ocean: {
    id: "ocean", label: "Derin Okyanus", emoji: "🌊", premium: true,
    primary: "#0369a1", primaryLight: "#e0f2fe", primaryDark: "#0c4a6e",
    accent: "#06b6d4", gradientFrom: "from-sky-50/50", gradientTo: "to-cyan-50/40",
    cardBorder: "border-sky-200", navBg: "bg-sky-50/90",
    btnBg: "bg-sky-700", btnHover: "hover:bg-sky-800", btnShadow: "shadow-sky-700/25",
    btnSecBorder: "border-sky-200", btnSecText: "text-sky-800",
    inputFocus: "focus:border-sky-400 focus:ring-sky-100",
    chipActive: "border-sky-600 bg-sky-50 text-sky-900",
    bg: "bg-gradient-to-b from-sky-100/50 via-cyan-50/30 to-blue-50/40",
    pattern: "waves",
    shape: "waves",
  },
  noir: {
    id: "noir", label: "Gece Şehir", emoji: "🌃", premium: true,
    primary: "#4338ca", primaryLight: "#e0e7ff", primaryDark: "#312e81",
    accent: "#a855f7", gradientFrom: "from-indigo-50/50", gradientTo: "to-violet-50/30",
    cardBorder: "border-indigo-200", navBg: "bg-indigo-50/95",
    btnBg: "bg-indigo-600", btnHover: "hover:bg-indigo-700", btnShadow: "shadow-indigo-600/30",
    btnSecBorder: "border-indigo-200", btnSecText: "text-indigo-800",
    inputFocus: "focus:border-indigo-400 focus:ring-indigo-100",
    chipActive: "border-indigo-500 bg-indigo-50 text-indigo-900",
    bg: "bg-gradient-to-b from-indigo-100/40 via-violet-50/30 to-slate-100/50",
    pattern: "stars",
    shape: "angular",
  },
};

const ThemeContext = createContext({});

export function ThemeProvider({ children }) {
  const [themeId, setThemeId] = useState(() => {
    try {
      return localStorage.getItem("rebi-theme") || "teal";
    } catch {
      /* localStorage erişilemez */
      return "teal";
    }
  });

  const theme = themes[themeId] || themes.teal;

  useEffect(() => {
    try {
      localStorage.setItem("rebi-theme", themeId);
    } catch {
      /* localStorage erişilemez */
    }
    document.documentElement.style.setProperty("--theme-primary", theme.primary);
    document.documentElement.style.setProperty("--theme-primary-light", theme.primaryLight);
    document.documentElement.style.setProperty("--theme-accent", theme.accent);
  }, [themeId, theme]);

  return (
    <ThemeContext.Provider value={{ theme, themeId, setThemeId, themes }}>
      {children}
    </ThemeContext.Provider>
  );
}

// eslint-disable-next-line react-refresh/only-export-components -- context hook
export const useTheme = () => useContext(ThemeContext);

// eslint-disable-next-line react-refresh/only-export-components
export function isPremiumThemeId(id) {
  return Boolean(themes[id]?.premium);
}

function userHasRebiPlusFromUser(user) {
  if (!user?.user_metadata) return false;
  const m = user.user_metadata;
  if (m.rebi_plus === true) return true;
  return ["plus", "pro", "premium"].includes(String(m.subscription_tier || "").toLowerCase());
}

/** Plus olmayan kullanıcıda kayıtlı premium temayı teal’e çeker. */
export function ThemePremiumGate() {
  const { user } = useAuth();
  const { themeId, setThemeId } = useTheme();

  useEffect(() => {
    if (!user) return;
    if (!userHasRebiPlusFromUser(user) && isPremiumThemeId(themeId)) {
      setThemeId("teal");
    }
  }, [user, themeId, setThemeId]);

  return null;
}
