import { Bot, Send, Sparkles } from "lucide-react";

export default function ChatPreview() {
  return (
    <div className="h-full w-full bg-white/70 backdrop-blur-xl border border-gray-200/70 rounded-[2rem] overflow-hidden shadow-lg">
      <div className="px-5 py-4 border-b border-gray-200/70 bg-white/60">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-2xl bg-gradient-to-br from-teal-600 to-emerald-500 flex items-center justify-center shadow-sm">
            <Bot className="w-5 h-5 text-white" />
          </div>
          <div className="min-w-0">
            <div className="text-sm font-black text-gray-900">Rebi AI</div>
            <div className="text-[11px] text-gray-500 flex items-center gap-1">
              <Sparkles className="w-3 h-3 text-teal-600" /> Canlı sohbet önizlemesi
            </div>
          </div>
          <div className="ml-auto text-[10px] font-semibold text-teal-700 bg-teal-50 border border-teal-100 px-2 py-1 rounded-full">
            Preview
          </div>
        </div>
      </div>

      <div className="px-5 py-5 space-y-3">
        <div className="flex justify-start">
          <div className="max-w-[88%] rounded-2xl rounded-bl-md bg-gray-100 text-gray-800 px-4 py-3 text-sm leading-relaxed">
            Merhaba! Bugün ne merak ediyorsun? Cilt, aktif madde, ürün, rutin…
          </div>
        </div>
        <div className="flex justify-end">
          <div className="max-w-[88%] rounded-2xl rounded-br-md bg-teal-600 text-white px-4 py-3 text-sm leading-relaxed">
            Retinol kullanıyorum, sabah sürmeli miyim?
          </div>
        </div>
        <div className="flex justify-start">
          <div className="max-w-[88%] rounded-2xl rounded-bl-md bg-gray-100 text-gray-800 px-4 py-3 text-sm leading-relaxed">
            Genelde hayır. Retinoid’leri akşama al, gündüz mutlaka SPF kullan. İstersen cildinin
            hassasiyetini sorup daha net ayarlayabilirim.
          </div>
        </div>
      </div>

      <div className="px-5 py-4 border-t border-gray-200/70 bg-white/60">
        <div className="flex gap-2">
          <div className="flex-1 rounded-2xl border-2 border-gray-200 bg-white px-4 py-3 text-sm text-gray-400">
            Buraya yaz…
          </div>
          <div className="w-12 h-12 rounded-2xl bg-teal-600 flex items-center justify-center shadow-sm">
            <Send className="w-5 h-5 text-white" />
          </div>
        </div>
        <div className="mt-2 h-1.5 w-28 bg-gray-200 rounded-full overflow-hidden">
          <div className="h-full w-1/2 bg-teal-500/70 animate-pulse" />
        </div>
      </div>
    </div>
  );
}

