import { useEffect, useMemo, useState } from "react";

function prefersReducedMotion() {
  try {
    return window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  } catch {
    return false;
  }
}

/**
 * Full-bleed background: looping video when assets exist, else animated mesh.
 * Place inside a `relative` container with defined min-height.
 */
export default function HeroBackgroundVideo({
  webmSrc = "/landing/hero-bg.webm",
  mp4Src = "/landing/hero-bg.mp4",
  videoOpacity = 0.42,
  className = "",
}) {
  const reduce = useMemo(() => prefersReducedMotion(), []);
  const [videoOk, setVideoOk] = useState(!reduce);

  useEffect(() => {
    if (reduce) setVideoOk(false);
  }, [reduce]);

  return (
    <div
      className={`pointer-events-none absolute inset-0 -z-[1] overflow-hidden ${className}`.trim()}
      aria-hidden="true"
    >
      {videoOk ? (
        <div className="absolute inset-0 hero-video-drift origin-center">
          <video
            className="h-full w-full min-h-full min-w-full object-cover"
            autoPlay
            muted
            playsInline
            loop
            preload="metadata"
            style={{ opacity: videoOpacity }}
            onError={() => setVideoOk(false)}
          >
            <source src={webmSrc} type="video/webm" />
            <source src={mp4Src} type="video/mp4" />
          </video>
        </div>
      ) : (
        <div className="absolute inset-0 hero-mesh-shift origin-center scale-110">
          <div
            className="absolute inset-0"
            style={{
              background:
                "radial-gradient(ellipse 80% 60% at 20% 20%, rgba(45,212,191,0.35), transparent 50%), radial-gradient(ellipse 70% 50% at 85% 30%, rgba(167,139,250,0.28), transparent 45%), radial-gradient(ellipse 90% 70% at 50% 100%, rgba(14,165,233,0.22), transparent 55%)",
            }}
          />
          <div
            className="absolute inset-0 mix-blend-overlay opacity-70"
            style={{
              background:
                "linear-gradient(125deg, rgba(255,255,255,0.15) 0%, transparent 40%, rgba(20,184,166,0.12) 60%, transparent 100%)",
            }}
          />
        </div>
      )}

      {/* Softer scrim so UI stays readable while video reads stronger */}
      <div className="absolute inset-0 bg-gradient-to-b from-white/55 via-white/25 to-teal-50/40" />
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_120%_80%_at_50%_-10%,rgba(20,184,166,0.2),transparent_50%)]" />
    </div>
  );
}
