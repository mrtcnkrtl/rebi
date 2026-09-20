import { useTranslation } from "react-i18next";

/** Kalıcı, kutusuz beyan: Rebi bir yapay zekâdır ve hata payı vardır. */
export default function AiDisclaimer({ className = "" }) {
  const { t } = useTranslation();
  return (
    <p className={`text-[11px] text-gray-500 leading-relaxed ${className}`}>
      {t("common.aiDisclaimer")}
    </p>
  );
}
