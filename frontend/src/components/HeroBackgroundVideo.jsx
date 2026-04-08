import { useEffect, useMemo, useState } from "react";

function prefersReducedMotion() {
  try {
    return window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  } catch {
    return false;
  }
}

/**
 * Full-bleed background video layer.
 *
 * Place inside a `relative` container and behind content.
 * If the assets are missing or user prefers reduced motion, it silently falls back (renders nothing).
 */
export default function HeroBackgroundVideo({
  webmSrc = "/landing/hero-bg.webm",
  mp4Src = "/landing/hero-bg.mp4",
  opacity = 0.18,
  className = "",
}) {
  const [enabled, setEnabled] = useState(true);
  const reduce = useMemo(() => prefersReducedMotion(), []);

  useEffect(() => {
    if (reduce) setEnabled(false);
  }, [reduce]);

  if (!enabled) return null;

  return (
    <div
      className={`absolute inset-0 -z-[1] overflow-hidden ${className}`.trim()}
      aria-hidden="true"
    >
      <video
        className="w-full h-full object-cover"
        autoPlay
        muted
        playsInline
        loop
        preload="metadata"
        style={{ opacity }}
        onError={() => setEnabled(false)}
      >
        {/* Prefer webm, fall back to mp4 */}
        <source src={webmSrc} type="video/webm" />
        <source src={mp4Src} type="video/mp4" />
      </video>
      {/* Soft overlays to blend with UI */}
      <div className="absolute inset-0 bg-gradient-to-b from-white/30 via-white/10 to-white/40" />
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,_rgba(20,184,166,0.18),_transparent_55%)]" />
    </div>
  );
}

