import { useState, useRef, useEffect } from "react";
import { useAuth } from "../context/AuthContext";
import { useTheme } from "../context/ThemeContext";
import { API_URL } from "../lib/supabase";
import { apiAuthHeaders } from "../lib/apiAuth";
import { DEMO_USER_ID } from "../lib/demoUser";
import { formatApiErrorDetail, isNetworkError } from "../lib/apiErrors";
import { Bot, Send, Loader2, Sparkles } from "lucide-react";

export default function Chat() {
  const { user } = useAuth();
  const { theme } = useTheme();
  const chatEndRef = useRef(null);
  const inputRef = useRef(null);

  const [history, setHistory] = useState(() => {
    try {
      const saved = localStorage.getItem("rebi-chat-history");
      return saved ? JSON.parse(saved) : [];
    } catch {
      return [];
    }
  });
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);

  const userName = user?.user_metadata?.full_name || "Kullanıcı";

  useEffect(() => {
    if (history.length === 0) {
      setHistory([{
        role: "assistant",
        content: `Merhaba ${userName}! Ben Rebi, cilt bakım asistanın. Cilt, yüz ve el bakımı hakkında her şeyi sorabilirsin. Ürünler, maddeler, bakım rutinleri, sorunlar... Nasıl yardımcı olabilirim?`,
      }]);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- yalnızca ilk boş oturumda karşılama
  }, []);

  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [history, loading]);

  useEffect(() => {
    if (!loading) inputRef.current?.focus();
  }, [loading, history]);

  useEffect(() => {
    try {
      if (history.length > 1) localStorage.setItem("rebi-chat-history", JSON.stringify(history.slice(-30)));
    } catch {
      /* localStorage dolu veya erişilemez */
    }
  }, [history]);

  const sendMessage = async () => {
    if (!input.trim() || loading) return;
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
        const errText = formatApiErrorDetail(data) + (res.status ? ` (${res.status})` : "");
        setHistory([...newHist, { role: "assistant", content: `Şu an yanıt alınamadı: ${errText}` }]);
        return;
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
    setHistory([{
      role: "assistant",
      content: `Sohbet temizlendi. Yeniden başlayalım! Cilt bakımı hakkında ne merak ediyorsun?`,
    }]);
    try {
      localStorage.removeItem("rebi-chat-history");
    } catch {
      /* ignore */
    }
  };

  return (
    <div className={`min-h-screen ${theme.bg}`}>
      <div className="max-w-lg mx-auto flex flex-col h-[calc(100vh-128px)]">
        {/* Header */}
        <div className="flex items-center gap-3 px-4 py-3 border-b border-gray-100">
          <div className="w-10 h-10 rounded-2xl flex items-center justify-center shadow-lg"
            style={{ background: `linear-gradient(135deg, ${theme.accent}, ${theme.primary})` }}>
            <Bot className="w-5 h-5 text-white" />
          </div>
          <div className="flex-1">
            <h3 className="font-bold text-gray-900 text-sm">Rebi AI</h3>
            <p className="text-[11px] text-gray-400">Cilt, yüz & el bakımı uzmanı</p>
          </div>
          <button onClick={clearChat} className="text-[10px] text-gray-400 hover:text-gray-600 px-2 py-1 rounded-lg hover:bg-gray-100 transition-colors">
            Temizle
          </button>
        </div>

        {/* Messages */}
        <div className="flex-1 overflow-y-auto px-4 py-4 space-y-3">
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
                <span className="text-sm text-gray-400">Rebi düşünüyor...</span>
              </div>
            </div>
          )}
          <div ref={chatEndRef} />
        </div>

        {/* Input */}
        <div className="px-4 py-3 border-t border-gray-100 bg-white/80 backdrop-blur-sm">
          <div className="flex gap-2">
            <input
              ref={inputRef}
              type="text"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && sendMessage()}
              placeholder="Ürünler, maddeler, sorunlar hakkında sor..."
              className="flex-1 input-field !py-3 text-sm"
              disabled={loading}
            />
            <button
              onClick={sendMessage}
              disabled={loading || !input.trim()}
              className="w-12 h-12 text-white rounded-2xl flex items-center justify-center transition-colors shrink-0 disabled:bg-gray-300"
              style={!loading && input.trim() ? { backgroundColor: theme.primary } : {}}
            >
              <Send className="w-5 h-5" />
            </button>
          </div>
          <p className="text-[10px] text-gray-400 text-center mt-1.5">
            <Sparkles className="w-3 h-3 inline" /> Cilt, yüz ve el bakımı hakkında her şeyi sorabilirsin
          </p>
        </div>
      </div>
    </div>
  );
}
