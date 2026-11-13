import { useState } from "react";
import RoutineStepChoices from "../components/RoutineStepChoices";
import { friendlyRoutineTitle } from "../lib/routineDisplay";
import { useTheme } from "../context/ThemeContext";
import samples from "./routineChoiceSamples.json";

function StepCard({ item, theme }) {
  const [chosenId, setChosenId] = useState(item.default_choice_id || null);
  const chosen = (item.choices || []).find((c) => c.id === chosenId);
  const title = friendlyRoutineTitle(chosen?.action || item.action);
  const hasOptions = Array.isArray(item.choices) && item.choices.length > 1;
  return (
    <div className="rounded-2xl bg-white border border-gray-100 px-3 py-3">
      <p className="text-[11px] font-semibold uppercase tracking-wide text-gray-400">{item.time}</p>
      <h3 className="mt-1 text-sm font-semibold text-gray-900 leading-snug">{title}</h3>
      {item.detail ? <p className="mt-1 text-[12px] text-gray-600">{item.detail}</p> : null}
      {hasOptions ? (
        <RoutineStepChoices
          item={item}
          userId="preview"
          theme={theme}
          selectedId={chosenId}
          onChange={setChosenId}
        />
      ) : null}
    </div>
  );
}

/** Yerel önizleme. Üretim derlemesine girmez. */
export default function RoutineChoicePreview() {
  const { theme } = useTheme();
  return (
    <div className="min-h-screen bg-teal-50/40 pb-16">
      <div className="max-w-lg mx-auto px-4 py-8 space-y-8">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Rutin</h1>
          <p className="mt-1 text-sm text-gray-600">
            Şartlar tek maddeyi seçerse rutin o adımı yazar. Birden fazla madde aynı soruna uyuyorsa ayrı adım değil, o adımın seçeneği olur. Adet kaynaklı sorunda luteal ve adet günlerinde dermokozmetik madde bekler; pencere geçince başlar. Menopoz ve gebelik bu beklemeye girmez.
          </p>
        </div>
        <section className="space-y-3">
          <h2 className="text-base font-bold text-gray-800">Göz altı, test cevabına göre tek adım</h2>
          <div className="rounded-2xl bg-white border border-gray-100 px-3 py-3">
            <p className="text-[11px] font-semibold uppercase tracking-wide text-gray-400">Sabah · mor / mavimsi</p>
            <h3 className="mt-1 text-sm font-semibold text-gray-900">Kafein</h3>
            <p className="mt-1 text-[12px] text-gray-600">Morluk veya belirgin şişlik. Başka seçenek yok.</p>
          </div>
          <div className="rounded-2xl bg-white border border-gray-100 px-3 py-3">
            <p className="text-[11px] font-semibold uppercase tracking-wide text-gray-400">Sabah · kahverengimsi</p>
            <h3 className="mt-1 text-sm font-semibold text-gray-900">C vitamini türevi</h3>
            <p className="mt-1 text-[12px] text-gray-600">Kahverengi koyuluk. Başka seçenek yok.</p>
          </div>
        </section>
        {samples.map((profile) => (
          <section key={profile.title} className="space-y-3">
            <h2 className="text-base font-bold text-gray-800">{profile.title}</h2>
            {profile.steps.map((step) => (
              <StepCard key={`${profile.title}-${step.action}`} item={step} theme={theme} />
            ))}
          </section>
        ))}
      </div>
    </div>
  );
}
