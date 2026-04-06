/**
 * Concern-specific clinical severity questionnaire (copy from locale packs).
 */
import { useState, useMemo } from "react";
import { useSeverityTestsPack } from "../lib/localePacks";
import { interpolate } from "../lib/interpolate";

function calculateScore(answers, maxPossible) {
  const total = Object.values(answers).reduce((sum, val) => sum + val, 0);
  const normalized = Math.round((total / maxPossible) * 9) + 1;
  return Math.min(10, Math.max(1, normalized));
}

function getSeverityLabel(score, ui) {
  if (score <= 3) return { text: ui.mild, color: "text-green-600", bg: "bg-green-100" };
  if (score <= 6) return { text: ui.moderate, color: "text-amber-600", bg: "bg-amber-100" };
  return { text: ui.severe, color: "text-red-600", bg: "bg-red-100" };
}

export default function SeverityTest({ concern, onScoreChange }) {
  const pack = useSeverityTestsPack();
  const ui = pack.ui || {};
  const [answers, setAnswers] = useState({});
  const test = pack[concern];

  const maxPossible = useMemo(() => {
    if (!test?.questions?.length) return 0;
    return test.questions.reduce(
      (sum, q) => sum + Math.max(...q.options.map((o) => o.score)),
      0
    );
  }, [test]);

  if (!test) return null;

  const answeredCount = Object.keys(answers).length;
  const totalCount = test.questions.length;
  const isComplete = answeredCount === totalCount;
  const score = isComplete ? calculateScore(answers, maxPossible) : null;
  const severity = score != null ? getSeverityLabel(score, ui) : null;

  const handleSelect = (qId, optScore) => {
    const newAnswers = { ...answers, [qId]: optScore };
    setAnswers(newAnswers);

    if (Object.keys(newAnswers).length === totalCount) {
      const s = calculateScore(newAnswers, maxPossible);
      onScoreChange(s);
    }
  };

  return (
    <div className="card space-y-5 border-teal-100 bg-teal-50/20">
      <div className="flex items-center gap-2">
        <span className="text-2xl">{test.icon}</span>
        <div>
          <h3 className="font-bold text-gray-900 text-sm">{test.title}</h3>
          <p className="text-xs text-gray-500">{test.subtitle}</p>
        </div>
      </div>

      <div className="text-xs text-gray-400 text-right">
        {interpolate(ui.answeredProgress || "", {
          answered: answeredCount,
          total: totalCount,
        })}
      </div>

      {test.questions.map((q) => (
        <div key={q.id} className="space-y-2">
          <p className="text-sm font-medium text-gray-700">{q.text}</p>
          <div className="grid grid-cols-1 gap-1.5">
            {q.options.map((opt, oi) => {
              const isSelected = answers[q.id] === opt.score && answers[q.id] !== undefined;
              const isQuestionAnswered = q.id in answers;
              return (
                <button
                  key={oi}
                  type="button"
                  onClick={() => handleSelect(q.id, opt.score)}
                  className={`text-left px-3 py-2.5 rounded-xl text-sm transition-all border ${
                    isSelected
                      ? "border-teal-500 bg-teal-50 text-teal-800 font-medium"
                      : isQuestionAnswered
                        ? "border-gray-100 bg-gray-50 text-gray-400"
                        : "border-gray-200 bg-white text-gray-700 hover:border-teal-300 hover:bg-teal-50/30"
                  }`}
                >
                  <span className="flex items-center gap-2">
                    <span
                      className={`w-4 h-4 rounded-full border-2 flex items-center justify-center shrink-0 ${
                        isSelected ? "border-teal-500" : "border-gray-300"
                      }`}
                    >
                      {isSelected && <span className="w-2 h-2 rounded-full bg-teal-500" />}
                    </span>
                    {opt.label}
                  </span>
                </button>
              );
            })}
          </div>
        </div>
      ))}

      {isComplete && severity && (
        <div className={`rounded-2xl p-4 text-center ${severity.bg}`}>
          <p className="text-xs text-gray-500 mb-1">{ui.computedScoreLabel}</p>
          <div className="flex items-center justify-center gap-3">
            <span className={`text-3xl font-bold ${severity.color}`}>{score}/10</span>
            <span className={`text-sm font-semibold px-3 py-1 rounded-full ${severity.bg} ${severity.color}`}>
              {severity.text}
            </span>
          </div>
        </div>
      )}

      {!isComplete && (
        <p className="text-xs text-center text-gray-400">{ui.answerAllHint}</p>
      )}
    </div>
  );
}
