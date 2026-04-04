import { useLocation, useNavigate } from "react-router-dom";
import { useTheme } from "../context/ThemeContext";
import { useAuth } from "../context/AuthContext";
import { isRoutineTrackingAccepted, hasCompletedOnboarding } from "../lib/routineTracking";
import { Home, MessageCircle, Scan, Palette, ClipboardCheck, UserRound } from "lucide-react";

export default function BottomNav() {
  const location = useLocation();
  const navigate = useNavigate();
  const { theme } = useTheme();
  const { user } = useAuth();

  const analyzeLabel =
    user?.id && hasCompletedOnboarding(user.id) ? "Yeniden" : "Analiz";

  const tabs = [
    { id: "/dashboard", label: "Ana Sayfa", icon: Home },
    { id: "/dashboard/checkin", label: "Check-in", icon: ClipboardCheck },
    { id: "/dashboard/chat", label: "Rebi AI", icon: MessageCircle },
    { id: "/dashboard/analyze", label: analyzeLabel, icon: Scan },
    { id: "/dashboard/themes", label: "Tema", icon: Palette },
    { id: "/dashboard/profile", label: "Profil", icon: UserRound },
  ];

  const active =
    tabs.find((t) => location.pathname === t.id)?.id
    ?? tabs.find((t) => t.id !== "/dashboard" && location.pathname.startsWith(t.id))?.id
    ?? (location.pathname === "/dashboard" ? "/dashboard" : null);

  return (
    <nav className="fixed bottom-0 left-0 right-0 z-50 border-t border-gray-200/60 bg-white/95 backdrop-blur-xl safe-area-bottom">
      <div className="max-w-lg mx-auto flex items-stretch h-16 px-1 overflow-x-auto gap-0.5 [scrollbar-width:thin]">
        {tabs.map((tab) => {
          const isActive = active === tab.id;
          const Icon = tab.icon;
          return (
            <button
              key={tab.id}
              type="button"
              onClick={() => {
                if (
                  tab.id === "/dashboard/checkin" &&
                  user?.id &&
                  !isRoutineTrackingAccepted(user.id)
                ) {
                  navigate("/dashboard", { state: { flashNeedAccept: true } });
                  return;
                }
                navigate(tab.id);
              }}
              className={`flex flex-col items-center justify-center gap-0.5 py-1.5 min-w-[3.65rem] shrink-0 rounded-xl transition-all ${
                isActive
                  ? "scale-105"
                  : "text-gray-400 hover:text-gray-600"
              }`}
            >
              <div className={`p-1.5 rounded-xl transition-all ${
                isActive ? "shadow-sm" : ""
              }`} style={isActive ? { backgroundColor: theme.primaryLight, color: theme.primary } : {}}>
                <Icon className="w-5 h-5" />
              </div>
              <span className={`text-[10px] font-medium ${isActive ? "" : "text-gray-400"}`}
                style={isActive ? { color: theme.primary } : {}}>
                {tab.label}
              </span>
            </button>
          );
        })}
      </div>
    </nav>
  );
}
