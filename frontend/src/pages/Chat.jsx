import { useState, useRef, useEffect } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { useTheme } from "../context/ThemeContext";
import { API_URL } from "../lib/supabase";
import { apiAuthHeaders } from "../lib/apiAuth";
import { DEMO_USER_ID } from "../lib/demoUser";
import { formatApiErrorDetail, isNetworkError } from "../lib/apiErrors";
import { isConsentError, requestConsentRecovery } from "../lib/consentRecovery";
import { Bot, Send, Loader2, Sparkles, Crown, Lock, ArrowRight, X, RotateCcw, ClipboardList } from "lucide-react";
import ThemePatternOverlay from "../components/ThemePatternOverlay";
import AiDisclaimer from "../components/AiDisclaimer";
import { useTranslation } from "react-i18next";
import { getRoutineSnapshot, isRoutineTrackingAccepted } from "../lib/routineTracking";

function chatHistoryKey(userId) {
  return `rebi-chat-history_${userId || "anonymous"}`;
}

function chatImportedKey(userId) {
  return `rebi-chat-imported-v1_${userId || "anonymous"}`;
}

function loadChatHistory(userId) {
  try {
    const saved = localStorage.getItem(chatHistoryKey(userId));
    if (!saved) return [];
    const parsed = JSON.parse(saved);
    if (!Array.isArray(parsed)) return [];
    return parsed.some((m) => m && m.role === "user") ? parsed : [];
  } catch {
    return [];
  }
}

/** Dokunmatik cihazda her cevaptan sonra odaklanmak klavyeyi açıp cevabı örtüyor. */
function isCoarsePointer() {
  try {
    return window.matchMedia?.("(pointer: coarse)").matches === true;
  } catch {
    return false;
  }
}

const URL_SPLIT = /(https?:\/\/[^\s<>()]+[^\s<>().,;:!?'"])/g;

function MessageText({ text, linkColor }) {
  const parts = String(text || "").split(URL_SPLIT);
  return parts.map((part, i) =>
    i % 2 === 1 ? (
      <a
        key={i}
        href={part}
        target="_blank"
        rel="noopener noreferrer"
        className="underline underline-offset-2 break-all"
        style={linkColor ? { color: linkColor } : undefined}
      >
        {part}
      </a>
    ) : (
      <span key={i}>{part}</span>
    ),
  );
}

async function importLocalHistory(userId, auth) {
  let alreadyTried = true;
  try {
    alreadyTried = localStorage.getItem(chatImportedKey(userId)) === "1";
  } catch {
    /* localStorage kapalıysa aktarmayı denemeyelim */
  }
  if (alreadyTried) return;
  const local = loadChatHistory(userId)
    .filter((m) => m && (m.role === "user" || m.role === "assistant") && String(m.content || "").trim())
    .map((m) => ({ role: m.role, content: String(m.content) }));
  try {
    localStorage.setItem(chatImportedKey(userId), "1");
  } catch {
    /* ignore */
  }
  if (!local.length) return;
  try {
    await fetch(`${API_URL}/chat/history/import`, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...auth },
      body: JSON.stringify({ user_id: userId, messages: local, surface: "general" }),
    });
  } catch {
    /* çevrimdışı: yerel geçmiş yerinde kalır */
  }
}

export default function Chat() {
  const { user } = useAuth();
  const { theme } = useTheme();
  const { t } = useTranslation();
  const navigate = useNavigate();
  const location = useLocation();
  const chatEndRef = useRef(null);
  const lastReplyRef = useRef(null);
  const inputRef = useRef(null);
  const effectiveUserId = user?.id || DEMO_USER_ID;
  const withBottomNav = Boolean(user) && location.pathname.startsWith("/dashboard");

  const [history, setHistory] = useState(() => loadChatHistory(effectiveUserId));
  const [historyOwnerId, setHistoryOwnerId] = useState(effectiveUserId);
  // Bu oturumda mesaj gönderildiyse sunucu geçmişi üzerine yazmaz.
  const sentThisSessionRef = useRef(false);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  /** Sohbet kotası: free_daily | plus_monthly | plus_unlimited | none */
  const [usage, setUsage] = useState(null);
  const [paywallOpen, setPaywallOpen] = useState(false);
  const [paywallKind, setPaywallKind] = useState("free_daily");
  const [routineSnap, setRoutineSnap] = useState(null);
  const [routineAccepted, setRoutineAccepted] = useState(false);
  const [edgeOpen, setEdgeOpen] = useState(false);

  const subscribeHref = user ? "/dashboard/subscribe" : "/auth?next=/dashboard/subscribe";
  const loginForChatHref = "/auth?next=/dashboard/chat";

  const hasConversation = history.some((m) => m.role === "user");

  // Yeni cevap gelince cevabın başını göster; uzun cevapta en alta atlayıp başını kaçırmasın.
  useEffect(() => {
    const last = history[history.length - 1];
    if (!loading && last?.role === "assistant" && lastReplyRef.current) {
      lastReplyRef.current.scrollIntoView({ behavior: "smooth", block: "start" });
      return;
    }
    chatEndRef.current?.scrollIntoView({ behavior: "smooth", block: "end" });
  }, [history, loading]);

  useEffect(() => {
    if (!loading && !isCoarsePointer()) inputRef.current?.focus();
  }, [loading]);

  // Rutin adımından "Rebi'ye sor" ile gelen soru: kutuya yaz, göndermeyi kullanıcıya bırak.
  useEffect(() => {
    const q = new URLSearchParams(location.search).get("q");
    if (!q) return;
    setInput(q.slice(0, 500));
    navigate(location.pathname, { replace: true });
    window.setTimeout(() => inputRef.current?.focus(), 50);
  }, [location.search, location.pathname, navigate]);

  useEffect(() => {
    const el = inputRef.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${Math.min(el.scrollHeight, 132)}px`;
  }, [input]);

  useEffect(() => {
    if (historyOwnerId !== effectiveUserId) return;
    try {
      if (history.some((m) => m.role === "user")) {
        localStorage.setItem(chatHistoryKey(effectiveUserId), JSON.stringify(history.slice(-30)));
      } else {
        localStorage.removeItem(chatHistoryKey(effectiveUserId));
      }
    } catch {
      /* localStorage dolu veya erişilemez */
    }
  }, [history, historyOwnerId, effectiveUserId]);

  useEffect(() => {
    sentThisSessionRef.current = false;
    setHistory(loadChatHistory(effectiveUserId));
    setHistoryOwnerId(effectiveUserId);
    setUsage(null);
    setPaywallOpen(false);
    setPaywallKind("free_daily");
    setRoutineSnap(null);
    setRoutineAccepted(false);
    setEdgeOpen(false);
  }, [effectiveUserId]);

  // Sunucudaki geçmiş: web ve mobil aynı konuşmayı görür.
  useEffect(() => {
    if (!user?.id) return;
    let cancelled = false;
    (async () => {
      try {
        const auth = await apiAuthHeaders();
        const r = await fetch(
          `${API_URL}/chat/history?user_id=${encodeURIComponent(user.id)}&surface=general&limit=50`,
          { headers: { ...auth } },
        );
        if (!r.ok || cancelled) return;
        const data = await r.json().catch(() => ({}));
        const messages = Array.isArray(data?.messages) ? data.messages : [];
        if (!messages.length) {
          // Sunucu öncesi dönemden kalan yerel sohbeti bir kez yukarı taşı.
          await importLocalHistory(user.id, auth);
          return;
        }
        if (sentThisSessionRef.current) return;
        setHistory(messages.map((m) => ({ role: m.role, content: m.content })));
        setHistoryOwnerId(user.id);
      } catch {
        /* çevrimdışı: yerel geçmişle devam */
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [user?.id]);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const uid = effectiveUserId;
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
        // Demo kullanıcıda rutin snapshot yok sayılabilir; kullanıcı girişinde çalışır.
        if (user?.id) {
          setRoutineAccepted(isRoutineTrackingAccepted(uid));
          setRoutineSnap(getRoutineSnapshot(uid));
        }
      } catch {
        /* ignore */
      }
      try {
        const auth = user?.id ? await apiAuthHeaders() : {};
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
  }, [effectiveUserId, user?.id]);

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

  const sendMessage = async (textOverride, baseHistory = history) => {
    const msg = String(textOverride ?? input).trim();
    if (!msg || loading || paywallOpen) return;
    if (textOverride == null) setInput("");
    sentThisSessionRef.current = true;
    const newHist = [...baseHistory, { role: "user", content: msg }];
    setHistory(newHist);
    setLoading(true);
    const failWith = (content) =>
      setHistory([...newHist, { role: "assistant", content, error: true, retryText: msg }]);

    try {
      const auth = await apiAuthHeaders();
      const res = await fetch(`${API_URL}/chat_general`, {
        method: "POST",
        headers: { "Content-Type": "application/json", ...auth },
        body: JSON.stringify({
          user_id: user?.id || DEMO_USER_ID,
          message: msg,
          history: newHist.filter((m) => !m.error).map((m) => ({ role: m.role, content: m.content })),
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        if (isConsentError(res.status, data)) {
          // Rıza kaydı yok: kullanıcıyı çıkışa zorlamadan onay kutusunu aç.
          requestConsentRecovery();
          setHistory([...newHist, { role: "assistant", content: t("common.consentRecoveryBody") }]);
          return;
        }
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
        failWith(`${t("chat.errorNoReply")} ${errText}`);
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
      failWith(isNetworkError(e) ? t("chat.errorNetwork") : t("chat.errorGeneric"));
    } finally {
      setLoading(false);
    }
  };

  const retryAt = (index) => {
    const failed = history[index];
    if (!failed?.retryText) return;
    const prevIsSameUser = history[index - 1]?.role === "user" && history[index - 1]?.content === failed.retryText;
    sendMessage(failed.retryText, history.slice(0, prevIsSameUser ? index - 1 : index));
  };

  const onInputKeyDown = (e) => {
    if (e.key !== "Enter" || e.shiftKey || e.nativeEvent?.isComposing) return;
    // Telefonda Enter yeni satır; gönderme butonla.
    if (isCoarsePointer()) return;
    e.preventDefault();
    sendMessage();
  };

  const clearChat = async () => {
    setHistory([]);
    setPaywallOpen(false);
    try {
      localStorage.removeItem(chatHistoryKey(effectiveUserId));
    } catch {
      /* ignore */
    }
    if (!user?.id) return;
    // Sunucudan da sil; aksi halde mobilde veya yeniden girişte geri gelir.
    try {
      const auth = await apiAuthHeaders();
      await fetch(`${API_URL}/chat/history?user_id=${encodeURIComponent(user.id)}`, {
        method: "DELETE",
        headers: { ...auth },
      });
    } catch {
      /* çevrimdışı: sonraki temizlemede silinir */
    }
  };

  const recentUserTurns = history
    .filter((m) => m && m.role === "user" && String(m.content || "").trim())
    .slice(-3)
    .reverse();

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

  const suggestionList = (key) => {
    const v = t(key, { returnObjects: true });
    return Array.isArray(v) ? v.filter((s) => typeof s === "string" && s.trim()) : [];
  };
  const suggestions = [
    ...(user?.id && routineHasItems ? suggestionList("chat.suggestRoutine") : []),
    ...suggestionList("chat.suggestGeneral"),
  ].slice(0, 4);

  return (
    <div className={`${theme.bg} relative`}>
      <ThemePatternOverlay pattern={theme.pattern} />

      {/* Sol açılır edge (web) */}
      {routineCorner && (
        <>
          {/* Tutacak */}
          <button
            type="button"
            onClick={() => setEdgeOpen(true)}
            className="hidden sm:flex fixed top-24 left-0 z-[28] items-center gap-2 pl-2 pr-3 py-2 rounded-r-2xl bg-white/85 backdrop-blur-md border border-gray-200/80 shadow-sm hover:bg-white/95 transition-colors"
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
            <div className="hidden sm:block fixed inset-0 z-[35]">
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

                  {recentUserTurns.length > 0 && (
                    <div className="rounded-2xl border border-gray-200 bg-white px-4 py-3">
                      <div className="text-[11px] font-extrabold text-gray-900">{t("chat.edgeRecentTitle")}</div>
                      <div className="mt-2 grid gap-2">
                        {recentUserTurns.map((m, idx) => (
                          <button
                            key={idx}
                            type="button"
                            onClick={() => {
                              setEdgeOpen(false);
                              setInput(String(m.content || ""));
                              window.setTimeout(() => inputRef.current?.focus(), 50);
                            }}
                            className="w-full text-left rounded-xl border border-gray-200 hover:border-gray-300 bg-gray-50 hover:bg-gray-100 px-3 py-2 text-[11px] text-gray-800 transition-colors"
                            title={String(m.content || "")}
                          >
                            <span className="font-bold">{t("chat.edgeRecentPick")}</span>{" "}
                            <span className="text-gray-600">
                              {String(m.content || "").trim().slice(0, 64)}
                              {String(m.content || "").trim().length > 64 ? "…" : ""}
                            </span>
                          </button>
                        ))}
                      </div>
                    </div>
                  )}

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

      <div
        className={`max-w-2xl mx-auto flex flex-col relative z-[1] w-full ${withBottomNav ? "chat-shell--with-nav" : "chat-shell"}`}
      >
        {/* Header */}
        <div className={`flex items-center gap-2.5 px-4 py-2.5 border-b ${theme.cardBorder} bg-white/70 backdrop-blur-md shrink-0`}>
          <div className="w-8 h-8 rounded-xl flex items-center justify-center shadow"
            style={{ background: `linear-gradient(135deg, ${theme.accent}, ${theme.primary})` }}>
            <Bot className="w-4 h-4 text-white" />
          </div>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <h3 className="font-bold text-gray-900 text-sm truncate">{t("nav.chat")}</h3>
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
          {routineCorner && (
            <Link
              to={routineCorner.href}
              className="sm:hidden inline-flex items-center gap-1 text-[11px] font-semibold px-2.5 py-1.5 rounded-xl border shrink-0"
              style={{ borderColor: theme.primaryLight, color: theme.primary }}
            >
              <ClipboardList className="w-3.5 h-3.5" />
              {routineHasItems ? t("chat.routineChip") : t("chat.analyzeChip")}
            </Link>
          )}
          {hasConversation && (
            <button
              type="button"
              onClick={clearChat}
              className="text-[11px] text-gray-500 hover:text-gray-700 px-2 py-1.5 rounded-lg hover:bg-gray-100 transition-colors shrink-0"
            >
              {t("chat.clear")}
            </button>
          )}
        </div>

        {/* Boş: Claude/Gemini tarzı orta alan; mesaj var: klasik sohbet */}
        {!hasConversation ? (
          <div className="flex-1 min-h-0 overflow-y-auto flex flex-col items-center justify-center px-5 sm:px-8 py-6">
            <div className="w-12 h-12 rounded-2xl flex items-center justify-center shadow-xl mb-5 opacity-95"
              style={{ background: `linear-gradient(145deg, ${theme.accent}, ${theme.primary})` }}>
              <Sparkles className="w-6 h-6 text-white" strokeWidth={1.75} />
            </div>
            <h1 className="text-center text-xl sm:text-3xl font-semibold text-gray-900 tracking-tight leading-snug max-w-md">
              {t("chat.emptyTitle")}
            </h1>
            <p className="mt-2 text-center text-sm sm:text-base text-gray-600 max-w-md leading-relaxed">
              {t("chat.dataHint")}
            </p>
            {suggestions.length > 0 && (
              <div className="mt-6 w-full max-w-md grid gap-2">
                {suggestions.map((s) => (
                  <button
                    key={s}
                    type="button"
                    onClick={() => sendMessage(s)}
                    disabled={loading || paywallOpen}
                    className="w-full text-left rounded-2xl border border-gray-200 bg-white/90 hover:bg-white px-4 py-3 text-sm text-gray-800 shadow-sm transition-colors disabled:opacity-50"
                  >
                    {s}
                  </button>
                ))}
              </div>
            )}
          </div>
        ) : (
          <div className="flex-1 min-h-0 overflow-y-auto overscroll-contain px-4 py-4 space-y-3">
            {history.map((msg, i) => {
              const isUser = msg.role === "user";
              const isLast = i === history.length - 1;
              return (
                <div
                  key={i}
                  ref={isLast && !isUser ? lastReplyRef : undefined}
                  className={`flex flex-col ${isUser ? "items-end" : "items-start"} scroll-mt-3`}
                >
                  <div
                    className={`max-w-[88%] px-4 py-3 rounded-2xl text-[15px] sm:text-sm leading-relaxed whitespace-pre-wrap break-words ${
                      isUser
                        ? "text-white rounded-br-md"
                        : msg.error
                          ? "bg-red-50 text-red-900 border border-red-100 rounded-bl-md"
                          : "bg-gray-100 text-gray-800 rounded-bl-md"
                    }`}
                    style={isUser ? { backgroundColor: theme.primary } : {}}
                  >
                    <MessageText text={msg.content} linkColor={isUser ? undefined : theme.primary} />
                  </div>
                  {msg.error && msg.retryText && isLast && (
                    <button
                      type="button"
                      onClick={() => retryAt(i)}
                      disabled={loading || paywallOpen}
                      className="mt-1.5 inline-flex items-center gap-1 text-xs font-semibold px-3 py-1.5 rounded-xl border bg-white disabled:opacity-50"
                      style={{ borderColor: theme.primaryLight, color: theme.primary }}
                    >
                      <RotateCcw className="w-3.5 h-3.5" />
                      {t("chat.retry")}
                    </button>
                  )}
                </div>
              );
            })}
            {loading && (
              <div className="flex justify-start">
                <div className="bg-gray-100 px-4 py-3 rounded-2xl rounded-bl-md flex items-center gap-2 text-xs text-gray-500">
                  <Loader2 className="w-4 h-4 animate-spin" style={{ color: theme.primary }} />
                  {t("chat.thinking")}
                </div>
              </div>
            )}
            <div ref={chatEndRef} />
          </div>
        )}

        {/* Input — her iki modda altta sabit */}
        <div className={`px-3 sm:px-4 pt-2.5 pb-2 border-t ${theme.cardBorder} bg-white/90 backdrop-blur-md shrink-0`}>
          <form
            className="flex items-end gap-2"
            onSubmit={(e) => {
              e.preventDefault();
              sendMessage();
            }}
          >
            <textarea
              ref={inputRef}
              rows={1}
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={onInputKeyDown}
              placeholder={t("chat.placeholder")}
              enterKeyHint="send"
              aria-label={t("chat.placeholder")}
              className="flex-1 input-field !py-3 text-base sm:text-sm resize-none leading-snug max-h-[132px]"
              disabled={loading || paywallOpen}
            />
            <button
              type="submit"
              aria-label={t("chat.send")}
              disabled={loading || paywallOpen || !input.trim()}
              className="w-12 h-12 text-white rounded-2xl flex items-center justify-center transition-colors shrink-0 disabled:bg-gray-300"
              style={!loading && input.trim() ? { backgroundColor: theme.primary } : {}}
            >
              <Send className="w-5 h-5" />
            </button>
          </form>
          <p className="text-[10px] text-gray-400 text-center mt-1.5 leading-snug">
            {usage?.kind === "free_daily" && (
              <>
                <Link
                  to={subscribeHref}
                  className="font-semibold underline-offset-2 hover:underline"
                  style={{ color: theme.primary }}
                >
                  {t("chat.plusUpgradeLink")}
                </Link>
                {" · "}
              </>
            )}
            <AiDisclaimer as="span" />
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
