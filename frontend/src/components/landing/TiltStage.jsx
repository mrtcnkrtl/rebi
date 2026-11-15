import { useEffect, useRef } from "react";

/**
 * Fareye göre eğilen sahne. Kendi üstüne --rx / --ry (derece) yazar; içindeki `.scene-3d__tilt` öğeleri bu değerle döner.
 * Yalnız fare hareketini dinler (dokunmatikte `.sway-3d` salınımı yeter), hareket durunca kare döngüsü de durur ve
 * "hareketi azalt" ayarında hiç çalışmaz.
 */
export default function TiltStage({ children, className = "", max = 9 }) {
  const ref = useRef(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return undefined;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return undefined;

    let raf = 0;
    let targetX = 0;
    let targetY = 0;
    let x = 0;
    let y = 0;

    const tick = () => {
      x += (targetX - x) * 0.09;
      y += (targetY - y) * 0.09;
      el.style.setProperty("--ry", (x * max).toFixed(2));
      el.style.setProperty("--rx", (-y * max * 0.7).toFixed(2));
      const moving = Math.abs(targetX - x) > 0.002 || Math.abs(targetY - y) > 0.002;
      raf = moving ? requestAnimationFrame(tick) : 0;
    };
    const kick = () => {
      if (!raf) raf = requestAnimationFrame(tick);
    };
    const onMove = (e) => {
      if (e.pointerType !== "mouse") return;
      targetX = Math.max(-1, Math.min(1, (e.clientX / window.innerWidth) * 2 - 1));
      targetY = Math.max(-1, Math.min(1, (e.clientY / window.innerHeight) * 2 - 1));
      kick();
    };
    const onLeave = () => {
      targetX = 0;
      targetY = 0;
      kick();
    };

    window.addEventListener("pointermove", onMove, { passive: true });
    document.documentElement.addEventListener("pointerleave", onLeave);
    return () => {
      window.removeEventListener("pointermove", onMove);
      document.documentElement.removeEventListener("pointerleave", onLeave);
      if (raf) cancelAnimationFrame(raf);
    };
  }, [max]);

  return (
    <div ref={ref} className={className}>
      {children}
    </div>
  );
}
