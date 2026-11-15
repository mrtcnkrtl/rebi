import { useTranslation } from "react-i18next";
import {
  Bell,
  Check,
  Droplets,
  House,
  LineChart,
  ListChecks,
  MessageCircle,
  Package,
  Sun,
  User,
} from "lucide-react";
import { Slab, Symbol3D } from "./Slab";

const PHONE_W = 270;
const PHONE_H = 556;

function Step({ done, children }) {
  return (
    <span className="flex items-center gap-2">
      <span
        className={`flex h-[18px] w-[18px] shrink-0 items-center justify-center rounded-full ${
          done ? "bg-teal-700 text-white" : "border-2 border-teal-700"
        }`}
      >
        {done ? <Check className="h-3 w-3" strokeWidth={3} /> : null}
      </span>
      <span className={`text-[12px] ${done ? "text-ink-soft" : "font-semibold text-ink"}`}>{children}</span>
    </span>
  );
}

/** Telefonun içindeki Bugün ekranı: uygulamadaki düzenin sadeleştirilmiş çizimi (orman sahnesi + yükselen krem panel). */
function TodayScreen() {
  const { t } = useTranslation();
  return (
    <span className="flex h-full w-full flex-col bg-ink text-left">
      <span className="flex items-end justify-between px-[18px] pb-7 pt-[46px] text-paper">
        <span className="flex flex-col">
          <span className="text-[10px] font-semibold uppercase tracking-[0.14em] opacity-70">{t("landing.mock.today")}</span>
          <span className="font-display text-[25px] font-medium leading-tight">{t("landing.mock.greeting")}</span>
        </span>
        <span
          className="h-9 w-9 rounded-full"
          style={{ background: "radial-gradient(circle at 35% 30%, #fbd9b5, #f1a56f)" }}
        />
      </span>

      <span className="-mt-3 flex flex-1 flex-col gap-2.5 rounded-t-[26px] bg-paper px-3 pb-3 pt-3.5">
        <span className="flex flex-col gap-2.5 rounded-2xl border border-rule bg-white p-3">
          <span className="flex items-center justify-between">
            <span className="text-[12px] font-semibold text-ink">{t("landing.mock.morning")}</span>
            <span className="text-[11px] font-medium text-ink-soft">2 / 3</span>
          </span>
          <span className="block h-1.5 overflow-hidden rounded-full bg-paper-deep">
            <span className="block h-full w-2/3 rounded-full bg-teal-700" />
          </span>
          <Step done>{t("landing.mock.step1")}</Step>
          <Step done>{t("landing.mock.step2")}</Step>
          <Step>{t("landing.mock.step3")}</Step>
        </span>

        <span className="flex items-center gap-2.5 rounded-2xl bg-honey-tint p-3">
          <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-white/70 text-honey">
            <Sun className="h-4 w-4" />
          </span>
          <span className="flex min-w-0 flex-col leading-snug">
            <span className="text-[11px] font-semibold text-honey">{t("landing.mock.uvTitle")}</span>
            <span className="text-[11px] text-ink">{t("landing.mock.uvDesc")}</span>
          </span>
        </span>

        <span className="flex items-center gap-2.5 rounded-2xl bg-water-tint p-3">
          <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-white/70 text-water">
            <Droplets className="h-4 w-4" />
          </span>
          <span className="flex min-w-0 flex-1 flex-col gap-1.5 leading-snug">
            <span className="text-[11px] font-semibold text-water">{t("landing.mock.water")}</span>
            <span className="flex gap-1">
              {Array.from({ length: 8 }, (_, i) => (
                <span key={i} className={`h-1.5 flex-1 rounded-full ${i < 5 ? "bg-water" : "bg-white/80"}`} />
              ))}
            </span>
          </span>
        </span>

        <span className="mt-auto flex items-center justify-between rounded-2xl border border-rule bg-white px-4 py-2.5 text-ink-soft">
          <House className="h-4 w-4 text-teal-700" />
          <ListChecks className="h-4 w-4" />
          <MessageCircle className="h-4 w-4" />
          <LineChart className="h-4 w-4" />
          <User className="h-4 w-4" />
        </span>
      </span>
    </span>
  );
}

function Chip({ icon, tint, fg, label, value, style }) {
  const Icon = icon;
  return (
    <span
      className="absolute flex items-center gap-2.5 rounded-2xl border border-rule bg-white py-2.5 pl-2.5 pr-4 shadow-[0_18px_30px_-14px_rgba(6,43,39,0.45)]"
      style={style}
    >
      <span className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-full ${tint} ${fg}`}>
        <Icon className="h-[18px] w-[18px]" />
      </span>
      <span className="flex flex-col whitespace-nowrap leading-tight">
        <span className="text-[11px] font-medium text-ink-soft">{label}</span>
        <span className="text-[13px] font-semibold text-ink">{value}</span>
      </span>
    </span>
  );
}

/**
 * Ana sayfanın üç boyutlu sahnesi: kalınlığı olan bir telefon, içinde Bugün ekranı; önünde farklı derinliklerde
 * hatırlatıcı, Rafım ve sohbet kartları ile iki simge. Tamamı süs; ekran okuyucuya kapalı. Üstte bir `TiltStage` varsa
 * fareyle birlikte döner.
 */
export default function PhoneScene({ className = "" }) {
  const { t } = useTranslation();
  return (
    <div className={`scene-3d ${className}`} aria-hidden="true">
      <span className="scene-3d__tilt">
        <span className="sway-3d">
          <span
            className="pose-3d relative"
            style={{ width: 460, height: 620, transform: "rotateY(-19deg) rotateX(9deg) rotateZ(1.5deg)" }}
          >
            {/* zemindeki gölge */}
            <span
              className="absolute rounded-[50%] bg-ink-deep/35 blur-2xl"
              style={{ left: 70, right: 40, bottom: -6, height: 70, transform: "translateZ(-90px)" }}
            />

            <Slab
              tone="ink"
              depth={18}
              radius={46}
              className="absolute"
              style={{ left: 95, top: 32, width: PHONE_W, height: PHONE_H }}
            >
              <span className="absolute inset-0 rounded-[46px] bg-[#071d1b]" />
              <span className="absolute inset-[8px] overflow-hidden rounded-[38px]">
                <TodayScreen />
              </span>
              <span className="absolute left-1/2 top-[18px] h-[20px] w-[78px] -translate-x-1/2 rounded-full bg-[#071d1b]" />
            </Slab>

            <Chip
              icon={Bell}
              tint="bg-lilac-tint"
              fg="text-lilac"
              label={t("landing.mock.reminderLabel")}
              value={t("landing.mock.reminderValue")}
              style={{ left: -30, top: 150, transform: "translateZ(96px)" }}
            />
            <Chip
              icon={Package}
              tint="bg-blush-tint"
              fg="text-blush"
              label={t("landing.mock.shelfLabel")}
              value={t("landing.mock.shelfValue")}
              style={{ left: -14, bottom: 96, transform: "translateZ(72px)" }}
            />

            <span
              className="absolute flex max-w-[190px] flex-col gap-1 rounded-2xl rounded-br-md bg-teal-700 px-3.5 py-2.5 text-paper shadow-[0_20px_32px_-14px_rgba(6,43,39,0.55)]"
              style={{ right: -58, top: 318, transform: "translateZ(128px)" }}
            >
              <span className="text-[10px] font-semibold uppercase tracking-[0.12em] opacity-75">
                {t("landing.mock.chatLabel")}
              </span>
              <span className="text-[13px] font-medium leading-snug">{t("landing.mock.chatValue")}</span>
            </span>

            <span className="pose-3d absolute" style={{ right: 26, top: 0, transform: "translateZ(60px)" }}>
              <Symbol3D icon={Sun} tone="honey" size={76} rotate="rotateY(-14deg) rotateX(18deg) rotateZ(8deg)" />
            </span>
            <span className="pose-3d absolute" style={{ right: 12, bottom: 44, transform: "translateZ(110px)" }}>
              <Symbol3D icon={Droplets} tone="water" size={66} rotate="rotateY(-26deg) rotateX(8deg) rotateZ(-6deg)" />
            </span>
          </span>
        </span>
      </span>
    </div>
  );
}
