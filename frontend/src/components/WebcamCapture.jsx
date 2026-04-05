import { useRef, useEffect, useState } from "react";
import { X, Camera } from "lucide-react";

/**
 * Masaüstü: getUserMedia ile önizleme + JPEG çekim.
 * Kapatınca stream durur.
 */
export default function WebcamCapture({ open, onClose, onPhoto }) {
  const videoRef = useRef(null);
  const [err, setErr] = useState("");

  useEffect(() => {
    if (!open) return undefined;
    let stream;
    setErr("");
    (async () => {
      try {
        if (!navigator.mediaDevices?.getUserMedia) {
          setErr("Bu tarayıcı kamera erişimini desteklemiyor.");
          return;
        }
        stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: "user", width: { ideal: 1280 }, height: { ideal: 720 } },
          audio: false,
        });
        const el = videoRef.current;
        if (el && stream) {
          el.srcObject = stream;
          await el.play().catch(() => {});
        }
      } catch {
        setErr("Kamera açılamadı. HTTPS kullanın ve tarayıcıda kamera iznini verin.");
      }
    })();
    return () => {
      if (stream) stream.getTracks().forEach((t) => t.stop());
      const el = videoRef.current;
      if (el) el.srcObject = null;
    };
  }, [open]);

  const capture = () => {
    const v = videoRef.current;
    if (!v?.videoWidth) return;
    const c = document.createElement("canvas");
    c.width = v.videoWidth;
    c.height = v.videoHeight;
    const ctx = c.getContext("2d");
    if (!ctx) return;
    ctx.drawImage(v, 0, 0);
    c.toBlob(
      (blob) => {
        if (!blob) return;
        const file = new File([blob], `webcam-${Date.now()}.jpg`, {
          type: "image/jpeg",
        });
        onPhoto(file);
        onClose();
      },
      "image/jpeg",
      0.92
    );
  };

  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-[120] flex items-center justify-center p-4 bg-black/70"
      role="dialog"
      aria-modal="true"
      aria-label="Web kamerası"
    >
      <div className="bg-white rounded-2xl shadow-xl max-w-lg w-full overflow-hidden border border-gray-200">
        <div className="flex items-center justify-between px-4 py-3 border-b border-gray-100">
          <span className="text-sm font-semibold text-gray-900">Bilgisayar kamerası</span>
          <button
            type="button"
            onClick={onClose}
            className="p-2 rounded-xl text-gray-500 hover:bg-gray-100"
            aria-label="Kapat"
          >
            <X className="w-5 h-5" />
          </button>
        </div>
        <div className="p-4 space-y-3">
          {err ? (
            <p className="text-sm text-red-600">{err}</p>
          ) : (
            <video
              ref={videoRef}
              className="w-full rounded-xl bg-black aspect-video object-cover"
              playsInline
              muted
            />
          )}
          <div className="flex gap-2">
            <button type="button" onClick={onClose} className="btn-secondary flex-1 text-sm">
              Vazgeç
            </button>
            <button
              type="button"
              onClick={capture}
              disabled={!!err}
              className="btn-primary flex-1 text-sm inline-flex items-center justify-center gap-2"
            >
              <Camera className="w-4 h-4" />
              Çek ve kullan
            </button>
          </div>
          <p className="text-[11px] text-gray-500 leading-relaxed">
            Canlı görüntü yalnızca cihazında işlenir; çekimden sonra önizlemede görürsün.
          </p>
        </div>
      </div>
    </div>
  );
}
