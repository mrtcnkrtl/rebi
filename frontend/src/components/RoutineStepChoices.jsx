import { useTranslation } from "react-i18next";
import { persistStepChoice } from "../lib/routineStepChoices";
import { friendlyRoutineTitle } from "../lib/routineDisplay";

export default function RoutineStepChoices({ item, userId, theme, selectedId, onChange }) {
  const { t } = useTranslation();
  const choices = Array.isArray(item?.choices) ? item.choices.filter(Boolean).slice(0, 2) : [];
  if (choices.length < 2) return null;

  const onPick = (id) => {
    const next = selectedId === id ? null : id;
    persistStepChoice(userId, item, next);
    if (typeof onChange === "function") onChange(next);
  };

  return (
    <div className="mt-2">
      <p className="text-[11px] font-medium text-gray-500 mb-1.5">{t("dashboard.stepChoicesTitle")}</p>
      <div className="grid grid-cols-2 gap-1.5">
        {choices.map((ch) => {
          const on = selectedId === ch.id;
          return (
            <button
              type="button"
              key={ch.id}
              onClick={() => onPick(ch.id)}
              aria-pressed={on}
              className="text-left rounded-xl px-2.5 py-2 text-[12px] font-semibold leading-snug transition-colors"
              style={{
                border: `1.5px solid ${on ? theme.primary : "#e5e7eb"}`,
                backgroundColor: on ? `${theme.primary}18` : "#fff",
                color: on ? theme.primaryDark || "#0f766e" : "#111827",
              }}
            >
              {friendlyRoutineTitle(ch.label || ch.action, ch.id)}
            </button>
          );
        })}
      </div>
    </div>
  );
}
