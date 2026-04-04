import { createContext, useContext, useState, useEffect } from "react";

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
