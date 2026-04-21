import { useState, useRef, useEffect } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { useTheme } from "../context/ThemeContext";
import { API_URL } from "../lib/supabase";
import { apiAuthHeaders } from "../lib/apiAuth";
import { DEMO_USER_ID } from "../lib/demoUser";
import { formatApiErrorDetail, isNetworkError } from "../lib/apiErrors";
import { Bot, Send, Loader2, Sparkles, Crown, Lock, ArrowRight, X } from "lucide-react";
import ThemePatternOverlay from "../components/ThemePatternOverlay";
import RebiIntroSplash from "../components/RebiIntroSplash";
import { useTranslation } from "react-i18next";
import { getRoutineSnapshot, isRoutineTrackingAccepted } from "../lib/routineTracking";

export default function Chat() {
  const { user } = useAuth();
  const { theme } = useTheme();
  const { t } = useTranslation();
  const navigate = useNavigate();
  const chatEndRef = useRef(null);
  const inputRef = useRef(null);

  const [history, setHistory] = useState(() => {
    try {
      const saved = localStorage.getItem("rebi-chat-history");
      if (!saved) return [];
      const parsed = JSON.parse(saved);
      if (!Array.isArray(parsed)) return [];
      /* Yalnızca kullanıcı mesajı olan oturumları yükle; eski “karşılama balonu” kayıtlarını at */
      return parsed.some((m) => m && m.role === "user") ? parsed : [];
    } catch {
      return [];
    }
  });
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  /** Sohbet kotası: free_daily | plus_monthly | plus_unlimited | none */
  const [usage, setUsage] = useState(null);
  const [paywallOpen, setPaywallOpen] = useState(false);
  const [paywallKind, setPaywallKind] = useState("free_daily");
  const [routineSnap, setRoutineSnap] = useState(null);
  const [routineAccepted, setRoutineAccepted] = useState(false);
  const [edgeOpen, setEdgeOpen] = useState(false);

  const userName = user?.user_metadata?.full_name || "Kullanıcı";
  const subscribeHref = user ? "/dashboard/subscribe" : "/auth?next=/dashboard/subscribe";
  const loginForChatHref = "/auth?next=/dashboard/chat";

  const hasConversation = history.some((m) => m.role === "user");

  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [history, loading]);

  useEffect(() => {
    if (!loading) inputRef.current?.focus();
  }, [loading, history]);

  useEffect(() => {
    try {
      if (history.some((m) => m.role === "user")) {
        localStorage.setItem("rebi-chat-history", JSON.stringify(history.slice(-30)));
      } else {
        localStorage.removeItem("rebi-chat-history");
      }
    } catch {
      /* localStorage dolu veya erişilemez */
    }
  }, [history]);

  useEffect(() => {
    setUsage(null);
    setPaywallOpen(false);
    setPaywallKind("free_daily");
    setRoutineSnap(null);
    setRoutineAccepted(false);
    setEdgeOpen(false);
  }, [user?.id]);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const uid = user?.id;
      if (!uid) return;
      // Last-known usage: köşe sayaç hemen görünsün
      try {
        const raw = localStorage.getItem(`rebi-chat-usage_${uid}`);
        if (raw) {
          const parsed = JSON.parse(raw);
          if (parsed && typeof parsed === "object" && parsed.kind) {
            setUsage(parsed);
          }
        }
      } catch {
        /* ignore */
      }
      try {
        setRoutineAccepted(isRoutineTrackingAccepted(uid));
        setRoutineSnap(getRoutineSnapshot(uid));
      } catch {
        /* ignore */
      }
      try {
        const auth = await apiAuthHeaders();
        const r = await fetch(`${API_URL}/chat_usage?user_id=${encodeURIComponent(uid)}`, {
          headers: { ...auth },
        });
        if (!r.ok || cancelled) return;
        const d = await r.json().catch(() => ({}));
        if (cancelled || !d?.kind || d.kind === "none") return;
        const next = {
          kind: d.kind,
          remaining: d.remaining ?? null,
          limit: d.limit ?? null,
          period: d.period || null,
        };
        setUsage(next);
        try {
          localStorage.setItem(`rebi-chat-usage_${uid}`, JSON.stringify(next));
        } catch {
          /* ignore */
        }
      } catch {
        /* ağ / oturum */
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [user?.id]);

  const applyUsageFromChatResponse = (data) => {
    const uid = user?.id;
    if (data.usage_kind) {
      const next = {
        kind: data.usage_kind,
        remaining: data.usage_remaining ?? null,
        limit: data.usage_limit ?? null,
        period: data.usage_kind === "plus_monthly" ? "month" : data.usage_kind === "free_daily" ? "day" : null,
      };
      setUsage(next);
      if (uid) {
        try {
          localStorage.setItem(`rebi-chat-usage_${uid}`, JSON.stringify(next));
        } catch {
          /* ignore */
        }
      }
      return;
    }
    if (data.free_chat_remaining != null && data.free_chat_limit != null) {
      const next = {
        kind: "free_daily",
        remaining: data.free_chat_remaining,
        limit: data.free_chat_limit,
        period: "day",
      };
      setUsage(next);
      if (uid) {
        try {
          localStorage.setItem(`rebi-chat-usage_${uid}`, JSON.stringify(next));
        } catch {
          /* ignore */
        }
      }
      return;
    }
    setUsage(null);
  };

  const sendMessage = async () => {
    if (!input.trim() || loading || paywallOpen) return;
    const msg = input.trim();
    setInput("");
    const newHist = [...history, { role: "user", content: msg }];
    setHistory(newHist);
    setLoading(true);

    try {
      const auth = await apiAuthHeaders();
      const res = await fetch(`${API_URL}/chat_assessment`, {
        method: "POST",
        headers: { "Content-Type": "application/json", ...auth },
        body: JSON.stringify({
          user_id: user?.id || DEMO_USER_ID,
          message: msg,
          history: newHist,
          user_profile: { name: userName, mode: "free_chat" },
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        let errText = formatApiErrorDetail(data) + (res.status ? ` (${res.status})` : "");
        if (res.status === 401) {
          errText =
            "Oturum süresi doldu veya giriş doğrulanamadı. Çıkış yapıp tekrar giriş yapmayı dene. " +
            errText;
        }
        if (res.status === 502 || res.status === 503) {
          errText =
            "Sunucu geçici olarak yanıt vermiyor. Biraz sonra tekrar dene. " + errText;
        }
        setHistory([...newHist, { role: "assistant", content: `Şu an yanıt alınamadı: ${errText}` }]);
        return;
      }
      if (data.chat_quota_exceeded) {
        applyUsageFromChatResponse(data);
        setPaywallKind(data.usage_kind === "plus_monthly" ? "plus_monthly" : "free_daily");
        setPaywallOpen(true);
      } else {
        applyUsageFromChatResponse(data);
      }
      const reply = typeof data.reply === "string" ? data.reply : formatApiErrorDetail(data);
      setHistory([...newHist, { role: "assistant", content: reply }]);
    } catch (e) {
      const net = isNetworkError(e);
      setHistory([
        ...newHist,
        {
          role: "assistant",
          content: net
            ? "Bağlantı kurulamadı. İnternetini ve API adresini kontrol et; backend çalışıyor mu?"
            : "Bir hata oluştu, tekrar dener misin?",
        },
      ]);
    } finally {
      setLoading(false);
    }
  };

  const clearChat = () => {
    setHistory([]);
    setPaywallOpen(false);
    try {
      localStorage.removeItem("rebi-chat-history");
    } catch {
      /* ignore */
    }
  };

  const routineHasItems = Array.isArray(routineSnap?.routine) && routineSnap.routine.length > 0;
  const routineCorner =
    user?.id && routineHasItems
      ? {
          title: t("chat.cornerRoutineReadyTitle"),
          body: routineAccepted ? t("chat.cornerRoutineAcceptedBody") : t("chat.cornerRoutineDraftBody"),
          href: "/dashboard",
          cta: t("chat.cornerRoutineCta"),
        }
      : user?.id
        ? {
            title: t("chat.cornerRoutineMissingTitle"),
            body: t("chat.cornerRoutineMissingBody"),
            href: "/dashboard/analyze",
            cta: t("chat.cornerRoutineMissingCta"),
          }
        : null;

  const cornerUsageText =
    usage?.kind === "free_daily" && usage.remaining != null && usage.limit != null
      ? t("chat.usageBadgeDay", { rem: usage.remaining, lim: usage.limit })
      : usage?.kind === "plus_monthly" && usage.remaining != null && usage.limit != null
        ? t("chat.usageBadgeMonth", { rem: usage.remaining, lim: usage.limit })
        : usage?.kind === "plus_unlimited"
          ? t("chat.usageBadgeUnlimited")
          : null;

  return (
    <div className={`min-h-screen ${theme.bg} relative`}>
      <RebiIntroSplash scope="chat" accentColor={theme.accent} primaryColor={theme.primary} />
      <ThemePatternOverlay pattern={theme.pattern} />

      {/* Köşe sayaç (özellikle web) */}
      {cornerUsageText && (
        <div className="fixed top-4 right-4 z-[30]">
          <div className="bg-white/90 backdrop-blur-md border border-gray-200/80 shadow-sm rounded-full px-3 py-1 text-[11px] font-semibold tabular-nums text-gray-800">
            {cornerUsageText}
          </div>
        </div>
      )}

      {/* Sol açılır edge (web) */}
      {routineCorner && (
        <>
          {/* Tutacak */}
          <button
            type="button"
            onClick={() => setEdgeOpen(true)}
            className="hidden md:flex fixed top-24 left-0 z-[28] items-center gap-2 pl-2 pr-3 py-2 rounded-r-2xl bg-white/85 backdrop-blur-md border border-gray-200/80 shadow-sm hover:bg-white/95 transition-colors"
            aria-label={t("chat.edgeOpen")}
          >
            <div
              className="w-9 h-9 rounded-xl flex items-center justify-center text-white shadow"
              style={{ background: `linear-gradient(135deg, ${theme.accent}, ${theme.primary})` }}
            >
              <Bot className="w-4 h-4" />
            </div>
            <div className="text-left">
              <div className="text-[11px] font-extrabold text-gray-900 leading-tight">{t("chat.edgeTitle")}</div>
              <div className="text-[10px] text-gray-500 leading-tight">{routineCorner.title}</div>
            </div>
          </button>

          {/* Overlay */}
          {edgeOpen && (
            <div className="hidden md:block fixed inset-0 z-[35]">
              <div
                className="absolute inset-0 bg-slate-950/25 backdrop-blur-[2px]"
                onClick={() => setEdgeOpen(false)}
                aria-hidden="true"
              />
              <div
                className="absolute top-0 left-0 h-full w-[340px] bg-white/95 backdrop-blur-md border-r border-gray-200 shadow-2xl"
                role="dialog"
                aria-label={t("chat.edgeTitle")}
              >
                <div className="px-4 py-4 border-b border-gray-200 flex items-center justify-between">
                  <div className="min-w-0">
                    <div className="text-xs font-black text-gray-900">{t("chat.edgeTitle")}</div>
                    <div className="text-[11px] text-gray-500 truncate">{t("chat.edgeSubtitle")}</div>
                  </div>
                  <button
                    type="button"
                    onClick={() => setEdgeOpen(false)}
                    className="w-9 h-9 rounded-2xl bg-gray-100 hover:bg-gray-200 flex items-center justify-center"
                    aria-label={t("chat.edgeClose")}
                  >
                    <X className="w-4 h-4 text-gray-700" />
                  </button>
                </div>

                <div className="p-4 space-y-4">
                  <div className="rounded-2xl border border-gray-200 bg-white px-4 py-3">
                    <div className="text-[11px] font-extrabold text-gray-900">{routineCorner.title}</div>
                    <div className="text-[11px] text-gray-600 mt-1 leading-snug">{routineCorner.body}</div>
                    <Link
                      to={routineCorner.href}
                      onClick={() => setEdgeOpen(false)}
                      className="inline-flex items-center gap-1.5 mt-2 text-[11px] font-bold underline-offset-2 hover:underline"
                      style={{ color: theme.primary }}
                    >
                      {routineCorner.cta}
                      <ArrowRight className="w-3 h-3" />
                    </Link>
                  </div>

                  <div className="rounded-2xl border border-gray-200 bg-white px-4 py-3">
                    <div className="text-[11px] font-extrabold text-gray-900">{t("chat.edgeQuickTitle")}</div>
                    <div className="mt-2 grid gap-2">
                      <button
                        type="button"
                        onClick={() => {
                          setEdgeOpen(false);
                          navigate("/dashboard");
                        }}
                        className="w-full text-left rounded-xl border border-gray-200 hover:border-gray-300 bg-gray-50 hover:bg-gray-100 px-3 py-2 text-[11px] font-bold text-gray-800 transition-colors"
                      >
                        {t("chat.edgeQuickDashboard")}
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          setEdgeOpen(false);
                          navigate("/dashboard/analyze");
                        }}
                        className="w-full text-left rounded-xl border border-gray-200 hover:border-gray-300 bg-gray-50 hover:bg-gray-100 px-3 py-2 text-[11px] font-bold text-gray-800 transition-colors"
                      >
                        {t("chat.edgeQuickAnalyze")}
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          )}
        </>
      )}

      <div className="max-w-2xl mx-auto flex flex-col h-[calc(100vh-128px)] relative z-[1] w-full">
        {/* Header */}
        <div className={`flex items-center gap-3 px-4 py-3 border-b ${theme.cardBorder} bg-white/70 backdrop-blur-md shrink-0`}>
          <div className="w-10 h-10 rounded-2xl flex items-center justify-center shadow-lg"
            style={{ background: `linear-gradient(135deg, ${theme.accent}, ${theme.primary})` }}>
            <Bot className="w-5 h-5 text-white" />
          </div>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <h3 className="font-bold text-gray-900 text-sm truncate">Rebi</h3>
              {usage && usage.kind === "free_daily" && usage.limit != null && usage.remaining != null && (
                <span
                  className="text-[10px] font-semibold tabular-nums px-2 py-0.5 rounded-full bg-gray-100 text-gray-700 border border-gray-200/80 shrink-0"
                  title={t("chat.usageHintDay")}
                >
                  {t("chat.usageBadgeDay", { rem: usage.remaining, lim: usage.limit })}
                </span>
              )}
              {usage && usage.kind === "plus_monthly" && usage.limit != null && usage.remaining != null && (
                <span
                  className="text-[10px] font-semibold tabular-nums px-2 py-0.5 rounded-full bg-violet-50 text-violet-900 border border-violet-200/80 shrink-0"
                  title={t("chat.usageHintMonth")}
                >
                  {t("chat.usageBadgeMonth", { rem: usage.remaining, lim: usage.limit })}
                </span>
              )}
              {usage && usage.kind === "plus_unlimited" && (
                <span
                  className="text-[10px] font-semibold px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-900 border border-emerald-200/80 shrink-0"
                  title={t("chat.usageHintUnlimited")}
                >
                  {t("chat.usageBadgeUnlimited")}
                </span>
              )}
            </div>
            <p className="text-[11px] text-gray-500 truncate">{t("chat.subtitle")}</p>
          </div>
          <button
            type="button"
            onClick={clearChat}
            disabled={!hasConversation}
            className="text-[10px] text-gray-400 hover:text-gray-600 px-2 py-1 rounded-lg hover:bg-gray-100 transition-colors disabled:opacity-40 disabled:pointer-events-none shrink-0"
          >
            {t("chat.clear")}
          </button>
        </div>

        {/* Boş: Claude/Gemini tarzı orta alan; mesaj var: klasik sohbet */}
        {!hasConversation ? (
          <div className="flex-1 min-h-0 flex flex-col items-center justify-center px-5 sm:px-8 pb-6">
            <div className="w-14 h-14 rounded-2xl flex items-center justify-center shadow-xl mb-6 opacity-95"
              style={{ background: `linear-gradient(145deg, ${theme.accent}, ${theme.primary})` }}>
              <Sparkles className="w-7 h-7 text-white" strokeWidth={1.75} />
            </div>
            <h1 className="text-center text-2xl sm:text-3xl font-semibold text-gray-900 tracking-tight leading-snug max-w-md">
              {t("chat.emptyTitle")}
            </h1>
            <p className="mt-3 text-center text-base text-gray-600 max-w-md leading-relaxed">
              {t("chat.emptySubtitle")}
            </p>
            <p className="mt-6 text-center text-xs sm:text-sm text-gray-500 max-w-sm leading-relaxed">
              {t("chat.dataHint")}
            </p>
          </div>
        ) : (
          <div className="flex-1 min-h-0 overflow-y-auto px-4 py-4 space-y-3">
            {history.map((msg, i) => (
              <div key={i} className={`flex ${msg.role === "user" ? "justify-end" : "justify-start"}`}>
                <div className={`max-w-[85%] px-4 py-3 rounded-2xl text-sm leading-relaxed ${
                  msg.role === "user"
                    ? "text-white rounded-br-md"
                    : "bg-gray-100 text-gray-800 rounded-bl-md"
                }`} style={msg.role === "user" ? { backgroundColor: theme.primary } : {}}>
                  {msg.content}
                </div>
              </div>
            ))}
            {loading && (
              <div className="flex justify-start">
                <div className="bg-gray-100 px-4 py-3 rounded-2xl rounded-bl-md flex items-center gap-2">
                  <Loader2 className="w-4 h-4 animate-spin" style={{ color: theme.primary }} />
                  <span className="text-sm text-gray-400">{t("chat.thinking")}</span>
                </div>
              </div>
            )}
            <div ref={chatEndRef} />
          </div>
        )}

        {/* Input — her iki modda altta sabit */}
        <div className={`px-4 py-3 border-t ${theme.cardBorder} bg-white/90 backdrop-blur-md shrink-0`}>
          <div className="flex gap-2">
            <input
              ref={inputRef}
              type="text"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && !e.shiftKey && sendMessage()}
              placeholder={t("chat.placeholder")}
              className="flex-1 input-field !py-3 text-sm"
              disabled={loading || paywallOpen}
            />
            <button
              onClick={sendMessage}
              disabled={loading || paywallOpen || !input.trim()}
              className="w-12 h-12 text-white rounded-2xl flex items-center justify-center transition-colors shrink-0 disabled:bg-gray-300"
              style={!loading && input.trim() ? { backgroundColor: theme.primary } : {}}
            >
              <Send className="w-5 h-5" />
            </button>
          </div>
          {usage?.kind === "free_daily" ? (
            <p className="text-[10px] text-gray-500 text-center mt-1.5">
              <Link
                to={subscribeHref}
                className="font-semibold underline-offset-2 hover:underline"
                style={{ color: theme.primary }}
              >
                {t("chat.plusUpgradeLink")}
              </Link>
              {" · "}
              <span className="text-gray-400">{t("chat.footerHintShort")}</span>
            </p>
          ) : usage?.kind === "plus_monthly" ? (
            <p className="text-[10px] text-violet-800/90 text-center mt-1.5">
              {t("chat.plusPack1000Footer")}
            </p>
          ) : usage?.kind === "plus_unlimited" ? (
            <p className="text-[10px] text-emerald-800/85 text-center mt-1.5 font-medium">{t("chat.plusUnlimitedFooter")}</p>
          ) : (
            <p className="text-[10px] text-gray-400 text-center mt-1.5">
              <Sparkles className="w-3 h-3 inline" /> {t("chat.footerHint")}
            </p>
          )}
          <p className="text-[10px] text-gray-400 text-center mt-1 leading-snug">
            {t("chat.disclaimerShort")}
          </p>
        </div>
      </div>

      {/* Paywall / Gate overlay */}
      {paywallOpen && (
        <div className="absolute inset-0 z-[20] flex items-center justify-center px-4 py-8">
          <div
            className="absolute inset-0 bg-slate-950/70 backdrop-blur-sm"
            onClick={() => setPaywallOpen(false)}
            aria-hidden="true"
          />
          <div className="relative w-full max-w-md rounded-3xl overflow-hidden border border-white/10 shadow-2xl">
            <div className="absolute inset-0 bg-gradient-to-br from-slate-950 via-violet-950/95 to-slate-950" />
            <div
              className="absolute inset-0 opacity-55"
              style={{
                backgroundImage:
                  "radial-gradient(circle at 18% 25%, rgba(167,139,250,0.45) 0%, transparent 42%), radial-gradient(circle at 82% 70%, rgba(244,114,182,0.28) 0%, transparent 38%)",
              }}
            />
            <div className="relative p-6">
              <button
                type="button"
                onClick={() => setPaywallOpen(false)}
                className="absolute top-4 right-4 w-9 h-9 rounded-2xl bg-white/10 hover:bg-white/15 border border-white/10 flex items-center justify-center"
                aria-label="Kapat"
              >
                <X className="w-4 h-4 text-white/80" />
              </button>

              <div className="flex items-start gap-3">
                <div
                  className="w-12 h-12 rounded-2xl flex items-center justify-center text-white shadow-lg"
                  style={{ background: `linear-gradient(135deg, ${theme.accent}, ${theme.primary})` }}
                >
                  <Crown className="w-6 h-6" />
                </div>
                <div className="min-w-0">
                  <div className="text-xs font-bold text-amber-200/90">REBI PLUS</div>
                  <h3 className="text-2xl font-black text-white leading-tight mt-1">
                    {paywallKind === "plus_monthly"
                      ? t("chat.paywallTitleMonth")
                      : t("chat.paywallTitleDay")}
                  </h3>
                  <p className="text-sm text-violet-100/85 mt-2 leading-relaxed">
                    {paywallKind === "plus_monthly"
                      ? t("chat.paywallBodyMonth")
                      : t("chat.paywallBodyDay")}
                  </p>
                </div>
              </div>

              <div className="mt-5 grid gap-3">
                {!user ? (
                  <>
                    <button
                      type="button"
                      onClick={() => navigate(loginForChatHref)}
                      className="w-full inline-flex items-center justify-center gap-2 rounded-2xl bg-white text-violet-950 font-extrabold px-5 py-3 shadow-lg shadow-black/20 hover:bg-violet-50 transition-colors"
                    >
                      <Lock className="w-4 h-4" />
                      Giriş yap
                      <ArrowRight className="w-4 h-4" />
                    </button>
                    <button
                      type="button"
                      onClick={() => navigate(subscribeHref)}
                      className="w-full inline-flex items-center justify-center gap-2 rounded-2xl bg-white/10 hover:bg-white/15 border border-white/15 text-white font-bold px-5 py-3 transition-colors"
                    >
                      <Crown className="w-4 h-4 text-amber-300" />
                      Plus’a geç
                      <ArrowRight className="w-4 h-4" />
                    </button>
                    <div className="text-[11px] text-white/60 text-center mt-1">
                      Not: Rutin tarafına geçmek istersen zaten kayıt/giriş gerekiyor.
                    </div>
                  </>
                ) : (
                  <>
                    <button
                      type="button"
                      onClick={() => navigate("/dashboard/subscribe")}
                      className="w-full inline-flex items-center justify-center gap-2 rounded-2xl bg-white text-violet-950 font-extrabold px-5 py-3 shadow-lg shadow-black/20 hover:bg-violet-50 transition-colors"
                    >
                      <Crown className="w-4 h-4 text-amber-600" />
                      Rebi Plus’ı aç
                      <ArrowRight className="w-4 h-4" />
                    </button>
                    <button
                      type="button"
                      onClick={() => setPaywallOpen(false)}
                      className="w-full inline-flex items-center justify-center gap-2 rounded-2xl bg-white/10 hover:bg-white/15 border border-white/15 text-white font-bold px-5 py-3 transition-colors"
                    >
                      Şimdilik kapat
                    </button>
                  </>
                )}
              </div>

              <div className="mt-5 rounded-2xl bg-white/5 border border-white/10 px-4 py-3">
                <div className="text-xs font-bold text-white/90">Plus ile</div>
                <ul className="mt-2 space-y-1.5 text-xs text-white/70">
                  <li className="flex items-start gap-2">
                    <span className="mt-1 w-1.5 h-1.5 rounded-full bg-amber-300/90 shrink-0" />
                    {t("chat.paywallBulletUnlimited")}
                  </li>
                  <li className="flex items-start gap-2">
                    <span className="mt-1 w-1.5 h-1.5 rounded-full bg-amber-300/90 shrink-0" />
                    Takip + check-in verisiyle daha tutarlı öneriler
                  </li>
                  <li className="flex items-start gap-2">
                    <span className="mt-1 w-1.5 h-1.5 rounded-full bg-amber-300/90 shrink-0" />
                    Premium temalar ve yeni özellikler
                  </li>
                </ul>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
