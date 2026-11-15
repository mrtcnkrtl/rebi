import { useEffect, useMemo } from "react";
import { Link, Navigate } from "react-router-dom";
import { useTranslation } from "react-i18next";
import StoreButton from "../components/landing/StoreButton";
import { STORES, detectPlatform, orderedStores } from "../lib/storeLinks";

/**
 * /indir: tek paylaşılabilir indirme adresi (ana sayfadaki karekod da buraya gelir). Telefonda ziyaretçiyi kendi
 * mağazasına gönderir; masaüstünde ana sayfanın indirme bölümüne iner. Yönlendirme takılırsa düğmeler ekranda kalır.
 */
export default function GetApp() {
  const { t } = useTranslation();
  const platform = useMemo(() => detectPlatform(), []);

  useEffect(() => {
    if (platform === "desktop") return;
    window.location.replace(STORES[platform].url);
  }, [platform]);

  if (platform === "desktop") return <Navigate to="/#indir" replace />;

  return (
    <main className="flex min-h-[80vh] flex-col items-center justify-center gap-6 bg-paper px-4 py-12 text-center text-ink">
      <p className="text-ink-soft">{t("landing.getAppRedirect")}</p>
      <div className="flex w-full max-w-sm flex-col gap-5">
        {orderedStores(platform).map((s) => (
          <StoreButton key={s.id} store={s} />
        ))}
      </div>
      <Link to="/" className="mt-2 text-sm font-semibold text-teal-700 underline underline-offset-4">
        {t("landing.getAppBack")}
      </Link>
    </main>
  );
}
