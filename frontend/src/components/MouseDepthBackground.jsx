import { useEffect, useRef } from "react";

const ORBS = [
  { nx: -0.42, ny: -0.34, z: 40, r: 168, speed: 0.55, phase: 0.4, amp: 18, inner: "rgba(255,255,255,0.95)", mid: "rgba(45,212,191,0.72)" },
  { nx: 0.46, ny: -0.28, z: 120, r: 190, speed: 0.42, phase: 1.6, amp: 20, inner: "rgba(255,255,255,0.92)", mid: "rgba(167,139,250,0.62)" },
  { nx: 0.08, ny: 0.08, z: 520, r: 240, speed: 0.28, phase: 2.4, amp: 16, inner: "rgba(255,255,255,0.7)", mid: "rgba(125,211,252,0.34)" },
  { nx: -0.58, ny: 0.22, z: 260, r: 150, speed: 0.48, phase: 3.1, amp: 14, inner: "rgba(255,255,255,0.9)", mid: "rgba(244,114,182,0.42)" },
  { nx: 0.62, ny: 0.3, z: -30, r: 110, speed: 0.86, phase: 0.8, amp: 12, inner: "rgba(255,255,255,0.96)", mid: "rgba(251,191,36,0.5)" },
  { nx: -0.12, ny: 0.42, z: 80, r: 96, speed: 0.74, phase: 4.2, amp: 11, inner: "rgba(255,255,255,0.94)", mid: "rgba(13,148,136,0.55)" },
  { nx: 0.22, ny: -0.48, z: -80, r: 64, speed: 1.05, phase: 1.1, amp: 9, inner: "rgba(255,255,255,1)", mid: "rgba(196,181,253,0.7)" },
  { nx: -0.72, ny: -0.08, z: 180, r: 72, speed: 0.9, phase: 5.1, amp: 10, inner: "rgba(255,255,255,0.95)", mid: "rgba(56,189,248,0.55)" },
  { nx: 0.34, ny: 0.12, z: -160, r: 42, speed: 1.2, phase: 2.8, amp: 8, inner: "rgba(255,255,255,1)", mid: "rgba(45,212,191,0.75)" },
];

function prefersReducedMotion() {
  try {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  } catch {
    return false;
  }
}

function project(x, y, z, rx, ry, w, h) {
  const cosX = Math.cos(rx);
  const sinX = Math.sin(rx);
  const y1 = y * cosX - z * sinX;
  const z1 = y * sinX + z * cosX;
  const cosY = Math.cos(ry);
  const sinY = Math.sin(ry);
  const x2 = x * cosY + z1 * sinY;
  const z2 = -x * sinY + z1 * cosY;
  const focal = Math.max(w, h) * 0.85;
  const depth = focal + z2;
  if (depth < 70) return null;
  const scale = focal / depth;
  return {
    sx: w * 0.5 + x2 * scale,
    sy: h * 0.42 + y1 * scale,
    scale,
    z: z2,
  };
}

export default function MouseDepthBackground() {
  const canvasRef = useRef(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext("2d", { alpha: true });
    if (!canvas || !ctx) return undefined;

    const reduce = prefersReducedMotion();
    const mouse = { x: 0, y: 0 };
    const tilt = { x: 0, y: 0 };
    let raf = 0;
    let running = true;
    let width = 1;
    let height = 1;

    const resize = () => {
      width = window.innerWidth || 1;
      height = window.innerHeight || 1;
      const dpr = Math.min(window.devicePixelRatio || 1, 1.75);
      canvas.width = Math.floor(width * dpr);
      canvas.height = Math.floor(height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };

    const onMove = (event) => {
      if (event.pointerType && event.pointerType !== "mouse") return;
      mouse.x = (event.clientX / width - 0.5) * 2;
      mouse.y = (event.clientY / height - 0.5) * 2;
    };

    const onLeave = (event) => {
      if (event.relatedTarget) return;
      mouse.x = 0;
      mouse.y = 0;
    };

    const drawRing = (rx, ry, radius, squash, color) => {
      ctx.save();
      ctx.translate(width * 0.5, height * 0.42);
      ctx.rotate(ry * 0.35);
      ctx.scale(1, squash + rx * 0.22);
      ctx.strokeStyle = color;
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.ellipse(0, 0, radius, radius, 0, 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();
    };

    const draw = (now) => {
      if (!running) return;
      const time = reduce ? 0 : now * 0.001;
      const follow = reduce ? 1 : 0.08;
      tilt.x += (mouse.x - tilt.x) * follow;
      tilt.y += (mouse.y - tilt.y) * follow;
      const idle = reduce ? 0 : Math.sin(time * 0.28) * 0.08;
      const ry = tilt.x * 0.62 + idle;
      const rx = tilt.y * 0.38 + (reduce ? 0 : Math.cos(time * 0.22) * 0.04);

      ctx.clearRect(0, 0, width, height);
      const unit = Math.min(width, height);
      drawRing(rx, ry, unit * 0.46, 0.22, "rgba(13,148,136,0.22)");
      drawRing(rx, ry + 0.6, unit * 0.3, 0.16, "rgba(139,92,246,0.18)");

      const painted = [];
      for (const orb of ORBS) {
        const bob = reduce ? 0 : Math.sin(time * orb.speed + orb.phase) * orb.amp;
        const drift = reduce ? 0 : Math.cos(time * orb.speed * 0.65 + orb.phase) * orb.amp * 0.45;
        const p = project(
          orb.nx * width * 0.62,
          orb.ny * height * 0.5 + bob,
          orb.z + drift,
          rx,
          ry,
          width,
          height,
        );
        if (!p) continue;
        painted.push({
          ...p,
          r: orb.r * (unit / 820) * p.scale,
          inner: orb.inner,
          mid: orb.mid,
        });
      }
      painted.sort((a, b) => b.z - a.z);

      for (const orb of painted) {
        if (orb.r < 2) continue;
        ctx.fillStyle = "rgba(15,118,110,0.08)";
        ctx.beginPath();
        ctx.ellipse(orb.sx + tilt.x * 10, orb.sy + orb.r * 0.82, orb.r * 0.72, orb.r * 0.18, 0, 0, Math.PI * 2);
        ctx.fill();

        const lightX = orb.sx - orb.r * (0.32 + tilt.x * 0.22);
        const lightY = orb.sy - orb.r * (0.36 + tilt.y * 0.16);
        const glow = ctx.createRadialGradient(lightX, lightY, orb.r * 0.02, orb.sx, orb.sy, orb.r);
        glow.addColorStop(0, orb.inner);
        glow.addColorStop(0.38, orb.mid);
        glow.addColorStop(1, "rgba(255,255,255,0)");
        ctx.fillStyle = glow;
        ctx.beginPath();
        ctx.arc(orb.sx, orb.sy, orb.r, 0, Math.PI * 2);
        ctx.fill();
      }

      if (!reduce) raf = window.requestAnimationFrame(draw);
    };

    const onVisibility = () => {
      if (document.hidden) {
        running = false;
        window.cancelAnimationFrame(raf);
        return;
      }
      if (reduce) return;
      running = true;
      raf = window.requestAnimationFrame(draw);
    };

    resize();
    window.addEventListener("resize", resize);
    window.addEventListener("pointermove", onMove, { passive: true });
    window.addEventListener("pointerout", onLeave);
    document.addEventListener("visibilitychange", onVisibility);
    raf = window.requestAnimationFrame(draw);

    return () => {
      running = false;
      window.cancelAnimationFrame(raf);
      window.removeEventListener("resize", resize);
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerout", onLeave);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, []);

  return (
    <div className="pointer-events-none fixed inset-0 z-0" aria-hidden="true">
      <div className="absolute inset-0 bg-gradient-to-b from-warm-50 via-white to-teal-50/60" />
      <canvas ref={canvasRef} className="absolute inset-0 h-full w-full" />
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_62%_42%_at_50%_18%,rgba(253,248,240,0.88),rgba(253,248,240,0.2)_58%,transparent_76%)]" />
    </div>
  );
}
