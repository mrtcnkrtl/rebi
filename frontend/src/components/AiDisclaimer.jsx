import { useTranslation } from "react-i18next";

/** Kalıcı, kutusuz beyan: Rebi bir yapay zekâdır ve hata payı vardır. */
export default function AiDisclaimer({ className = "", as: Tag = "p" }) {
  const { t } = useTranslation();
  const base = Tag === "p" ? "text-[11px] text-gray-500 leading-relaxed" : "";
  return <Tag className={`${base} ${className}`.trim()}>{t("common.aiDisclaimer")}</Tag>;
}
