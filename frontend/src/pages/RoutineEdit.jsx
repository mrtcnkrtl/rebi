import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import {
  AlertCircle, ArrowLeft, CheckCircle, Info, ListChecks, Pencil, Plus, Trash2, WifiOff,
} from "lucide-react";
import { useAuth } from "../context/AuthContext";
import { useTheme } from "../context/ThemeContext";
import { useTranslation } from "react-i18next";
import ThemePatternOverlay from "../components/ThemePatternOverlay";
import { DEMO_USER_ID } from "../lib/demoUser";
import { getRoutineSnapshot, saveRoutineSnapshot } from "../lib/routineTracking";
import {
  MAX_USER_STEPS,
  MAX_USER_STEP_ACTION_CHARS,
  MAX_USER_STEP_DETAIL_CHARS,
  USER_STEP_TIMES,
  fetchRoutineWithSkipped,
  isSkippedByUser,
  isUserStep,
  routineStepKey,
  saveRoutineEdits,
} from "../lib/routineEdits";

/**
 * "Rutinimi düzenle" (`PUT /routine/active`) — mobildeki `routine_edit_screen.dart` ile aynı iş.
 *
 * Geri bildirim: "kendim de bir rutin yapabileyim, onun üstüne AI önerebilirsin ya da AI
 * önerdiğinin üzerinde değişiklikler yapabileyim". Rebi'nin ürettiği adımların metni burada
 * değişmez — kullanıcı yapmayacağı adımı plandan çıkarır (geri alınabilir) ve kendi adımlarını
 * ekler. Değişiklikler kaydedilene kadar sunucuya gitmez.
 */
export default function RoutineEdit() {
  const { user } = useAuth();
  const { theme } = useTheme();
  const { t } = useTranslation();

  const uid = user?.id || null;
  const real = Boolean(uid) && uid !== DEMO_USER_ID;

  const [engineSteps, setEngineSteps] = useState([]);
  const [userSteps, setUserSteps] = useState([]);
  const [hidden, setHidden] = useState(() => new Set());
  const [savedHidden, setSavedHidden] = useState(() => new Set());
  const [savedUserSteps, setSavedUserSteps] = useState([]);

  const [loading, setLoading] = useState(true);
  const [failed, setFailed] = useState(false);
  const [saving, setSaving] = useState(false);
  const [showSaved, setShowSaved] = useState(false);
  const [error, setError] = useState("");

  /** Açık form: null = kapalı, {index} = düzenleme, {index: null} = yeni adım. */
  const [form, setForm] = useState(null);

  const apply = (items) => {
    const engine = items.filter((i) => !isUserStep(i));
    const own = items.filter(isUserStep).map((i) => ({
      action: String(i.action ?? ""),
      time: USER_STEP_TIMES.includes(i.time) ? i.time : "Sabah",
      detail: String(i.detail ?? ""),
    }));
    const dropped = new Set(engine.filter(isSkippedByUser).map(routineStepKey));
    setEngineSteps(engine);
    setUserSteps(own);
    setHidden(dropped);
    setSavedHidden(new Set(dropped));
    setSavedUserSteps(own);
  };

  /** Sunucudaki rutin + çıkarılanlar; ağ yoksa tarayıcıdaki kopya gösterilir. */
  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      setFailed(false);
      let loaded = null;
      if (real) {
        try {
          loaded = await fetchRoutineWithSkipped(uid);
        } catch {
          loaded = null;
        }
      }
      if (cancelled) return;
      const snapshot = getRoutineSnapshot(uid)?.routine;
      const items = loaded
        ? [...loaded.routine, ...loaded.skipped]
        : (Array.isArray(snapshot) ? snapshot : []);
      apply(items);
      setFailed(!loaded);
      setLoading(false);
    })();
    return () => {
      cancelled = true;
    };
  }, [uid, real]);

  const sameSet = (a, b) => a.size === b.size && [...a].every((x) => b.has(x));
  const dirty = useMemo(() => {
    if (!sameSet(hidden, savedHidden)) return true;
    if (userSteps.length !== savedUserSteps.length) return true;
    return userSteps.some((s, i) => {
      const o = savedUserSteps[i];
      return s.action !== o.action || s.time !== o.time || s.detail !== o.detail;
    });
  }, [hidden, savedHidden, userSteps, savedUserSteps]);

  /** Yürürlükte kalan adım sayısı (hepsi çıkarılamaz: plan boşalırsa ekranın anlamı kalmaz). */
  const keptCount = engineSteps.length - hidden.size + userSteps.length;

  const change = (fn) => {
    fn();
    setError("");
    setShowSaved(false);
  };

  const toggleStep = (key, keep) =>
    change(() =>
      setHidden((prev) => {
        const next = new Set(prev);
        if (keep) next.delete(key);
        else next.add(key);
        return next;
      })
    );

  const save = async () => {
    if (!real || saving || !dirty) return;
    setSaving(true);
    setError("");
    const res = await saveRoutineEdits(uid, { hidden, added: userSteps });
    if (res.error || !res.result) {
      setSaving(false);
      setError(res.error || t("routineEdit.saveFailed"));
      return;
    }
    // Tarayıcıdaki kopya da güncellenir: panel ağ olmadan da düzenlenmiş planı gösterir.
    saveRoutineSnapshot(uid, { routine: res.result.routine });
    apply([...res.result.routine, ...res.result.skipped]);
    setSaving(false);
    setShowSaved(true);
  };

  const submitForm = (step) => {
    const action = step.action.trim();
    if (!action) return;
    change(() => {
      setUserSteps((prev) => {
        const next = [...prev];
        const entry = { action, time: step.time, detail: step.detail.trim() };
        if (form?.index == null) next.push(entry);
        else next[form.index] = entry;
        return next;
      });
      setForm(null);
    });
  };

  const notice = (text, Icon, tone) => (
    <div className={`flex items-start gap-3 rounded-2xl border px-4 py-3 text-sm ${tone}`}>
      <Icon className="w-5 h-5 shrink-0 mt-0.5" />
      <p className="min-w-0 flex-1 leading-relaxed">{text}</p>
    </div>
  );

  return (
    <div className={`min-h-screen ${theme.bg} pb-32 relative`}>
      <ThemePatternOverlay pattern={theme.pattern} />
      <div className="max-w-lg mx-auto px-4 py-8 relative z-[1] space-y-4">
        <Link to="/dashboard" className="inline-flex items-center gap-1.5 text-sm font-semibold text-gray-500 hover:text-gray-700">
          <ArrowLeft className="w-4 h-4" />
          {t("common.back")}
        </Link>

        <div>
          <h2 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
            <ListChecks className="w-6 h-6" style={{ color: theme.primary }} />
            {t("routineEdit.title")}
          </h2>
          <p className="text-gray-500 text-sm mt-1 leading-relaxed">{t("routineEdit.subtitle")}</p>
        </div>

        {loading ? (
          <p className="py-12 text-center text-sm text-gray-500">{t("common.loading")}</p>
        ) : !real ? (
          notice(t("routineEdit.notSynced"), Info, "border-amber-200 bg-amber-50/90 text-amber-900")
        ) : !engineSteps.length && !userSteps.length ? (
          notice(t("routineEdit.noRoutine"), Info, "border-amber-200 bg-amber-50/90 text-amber-900")
        ) : (
          <>
            {failed && notice(t("routineEdit.offline"), WifiOff, "border-amber-200 bg-amber-50/90 text-amber-900")}
            {notice(t("routineEdit.hint"), Info, "border-gray-200 bg-white/80 text-gray-600")}

            {/* Rebi'nin adımları: kapatılan plandan çıkar, metni değişmez. */}
            <div className="card space-y-1 !p-5">
              <h3 className="text-sm font-bold text-gray-800">{t("routineEdit.rebiSteps")}</h3>
              <p className="text-xs text-gray-500 leading-relaxed">{t("routineEdit.rebiStepsHint")}</p>
              <ul className="divide-y divide-gray-100 pt-2">
                {engineSteps.map((item) => {
                  const key = routineStepKey(item);
                  const kept = !hidden.has(key);
                  const canDrop = !kept || keptCount > 1;
                  return (
                    <li key={key} className="flex items-center gap-3 py-3">
                      <div className="min-w-0 flex-1">
                        <p className={`text-sm font-semibold ${kept ? "text-gray-900" : "text-gray-400 line-through"}`}>
                          {item.action}
                        </p>
                        <p className="text-xs text-gray-500 mt-0.5">
                          {kept ? item.time : `${item.time} · ${t("routineEdit.dropped")}`}
                        </p>
                      </div>
                      <label className="shrink-0 inline-flex items-center cursor-pointer">
                        <span className="sr-only">{item.action}</span>
                        <input
                          type="checkbox"
                          className="sr-only peer"
                          checked={kept}
                          disabled={!canDrop}
                          onChange={(e) => toggleStep(key, e.target.checked)}
                        />
                        <span
                          className="w-11 h-6 rounded-full bg-gray-200 peer-checked:bg-[var(--on)] transition-colors relative after:content-[''] after:absolute after:top-0.5 after:left-0.5 after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-transform peer-checked:after:translate-x-5 peer-disabled:opacity-50"
                          style={{ "--on": theme.primary }}
                        />
                      </label>
                    </li>
                  );
                })}
              </ul>
            </div>

            {/* Kullanıcının kendi adımları: Rebi'nin önerisi olarak gösterilmez. */}
            <div className="card space-y-1 !p-5">
              <h3 className="text-sm font-bold text-gray-800">{t("routineEdit.mySteps")}</h3>
              <p className="text-xs text-gray-500 leading-relaxed">{t("routineEdit.myStepsHint")}</p>
              {userSteps.length === 0 ? (
                <p className="pt-2 text-xs text-gray-500">{t("routineEdit.myStepsEmpty")}</p>
              ) : (
                <ul className="divide-y divide-gray-100 pt-2">
                  {userSteps.map((step, i) => (
                    <li key={`${step.action}-${i}`} className="flex items-center gap-2 py-3">
                      <div className="min-w-0 flex-1">
                        <p className="text-sm font-semibold text-gray-900">{step.action}</p>
                        <p className="text-xs text-gray-500 mt-0.5">
                          {[t(`routineEdit.time.${step.time}`, { defaultValue: step.time }), step.detail]
                            .filter(Boolean)
                            .join(" · ")}
                        </p>
                      </div>
                      <button
                        type="button"
                        aria-label={t("routineEdit.editTitle")}
                        onClick={() => setForm({ index: i, ...step })}
                        className="shrink-0 p-2 text-gray-500 hover:text-gray-800"
                      >
                        <Pencil className="w-4 h-4" />
                      </button>
                      <button
                        type="button"
                        aria-label={t("routineEdit.removeStep")}
                        onClick={() => change(() => setUserSteps((prev) => prev.filter((_, j) => j !== i)))}
                        className="shrink-0 p-2 text-red-600 hover:text-red-700"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </li>
                  ))}
                </ul>
              )}

              {form ? (
                <UserStepForm
                  initial={form}
                  theme={theme}
                  t={t}
                  onCancel={() => setForm(null)}
                  onSubmit={submitForm}
                />
              ) : (
                <div className="pt-3">
                  <button
                    type="button"
                    onClick={() => setForm({ index: null, action: "", time: "Sabah", detail: "" })}
                    disabled={userSteps.length >= MAX_USER_STEPS}
                    className="btn-secondary w-full justify-center text-sm disabled:opacity-50"
                    style={{ borderColor: theme.primaryLight, color: theme.primary }}
                  >
                    <Plus className="w-4 h-4" />
                    {t("routineEdit.addStep")}
                  </button>
                  {userSteps.length >= MAX_USER_STEPS && (
                    <p className="mt-2 text-xs text-gray-500">{t("routineEdit.myStepsFull", { n: MAX_USER_STEPS })}</p>
                  )}
                </div>
              )}
            </div>

            {error && notice(error, AlertCircle, "border-red-200 bg-red-50/90 text-red-900")}
            {showSaved && notice(t("routineEdit.saved"), CheckCircle, "border-green-200 bg-green-50/90 text-green-900")}

            <button
              type="button"
              onClick={save}
              disabled={!dirty || saving}
              className="btn-primary w-full justify-center disabled:opacity-50"
              style={{ backgroundColor: theme.primary }}
            >
              {saving ? t("common.loading") : t("routineEdit.save")}
            </button>
          </>
        )}
      </div>
    </div>
  );
}

/** Kendi adımının formu: ad, zaman ve kısa not. Boş ad kaydedilmez. */
function UserStepForm({ initial, theme, t, onCancel, onSubmit }) {
  const [action, setAction] = useState(initial.action || "");
  const [time, setTime] = useState(USER_STEP_TIMES.includes(initial.time) ? initial.time : "Sabah");
  const [detail, setDetail] = useState(initial.detail || "");

  return (
    <div className="mt-3 space-y-3 rounded-2xl border border-gray-200 bg-white/80 p-4">
      <p className="text-xs text-gray-500 leading-relaxed">{t("routineEdit.addBody")}</p>
      <label className="block">
        <span className="text-xs font-semibold text-gray-700">{t("routineEdit.actionLabel")}</span>
        <input
          type="text"
          value={action}
          maxLength={MAX_USER_STEP_ACTION_CHARS}
          placeholder={t("routineEdit.actionHint")}
          onChange={(e) => setAction(e.target.value)}
          className="mt-1 w-full rounded-xl border border-gray-200 px-3 py-2 text-sm"
        />
      </label>
      <div className="flex flex-wrap gap-2">
        {USER_STEP_TIMES.map((id) => (
          <button
            key={id}
            type="button"
            onClick={() => setTime(id)}
            className="rounded-xl border-2 px-3 py-1.5 text-xs font-semibold"
            style={{
              borderColor: time === id ? theme.primary : "#e5e7eb",
              color: time === id ? theme.primary : "#6b7280",
            }}
          >
            {t(`routineEdit.time.${id}`, { defaultValue: id })}
          </button>
        ))}
      </div>
      <label className="block">
        <span className="text-xs font-semibold text-gray-700">{t("routineEdit.detailLabel")}</span>
        <input
          type="text"
          value={detail}
          maxLength={MAX_USER_STEP_DETAIL_CHARS}
          placeholder={t("routineEdit.detailHint")}
          onChange={(e) => setDetail(e.target.value)}
          className="mt-1 w-full rounded-xl border border-gray-200 px-3 py-2 text-sm"
        />
      </label>
      <div className="flex gap-2">
        <button
          type="button"
          onClick={() => onSubmit({ action, time, detail })}
          disabled={!action.trim()}
          className="btn-primary flex-1 justify-center text-sm disabled:opacity-50"
          style={{ backgroundColor: theme.primary }}
        >
          {t("routineEdit.addSave")}
        </button>
        <button
          type="button"
          onClick={onCancel}
          className="btn-secondary flex-1 justify-center text-sm"
          style={{ borderColor: theme.primaryLight, color: theme.primary }}
        >
          {t("common.cancel")}
        </button>
      </div>
    </div>
  );
}
