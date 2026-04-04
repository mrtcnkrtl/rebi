import { useState, useEffect } from "react";
import { Leaf, CloudSun, BookOpen, Brain, Sparkles } from "lucide-react";

const loadingSteps = [
  { icon: CloudSun, text: "Hava durumu inceleniyor...", color: "text-blue-500" },
  { icon: BookOpen, text: "Bilimsel literatür taranıyor...", color: "text-purple-500" },
  { icon: Brain, text: "Yapay zeka analiz ediyor...", color: "text-teal-500" },
  { icon: Sparkles, text: "Rutinin hazırlanıyor...", color: "text-amber-500" },
];

export default function LoadingScreen() {
  const [currentStep, setCurrentStep] = useState(0);

  useEffect(() => {
    const interval = setInterval(() => {
      setCurrentStep((prev) =>
        prev < loadingSteps.length - 1 ? prev + 1 : prev
      );
    }, 2500);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="fixed inset-0 bg-gradient-to-b from-teal-50 to-white z-50 flex flex-col items-center justify-center px-6">
      <div className="w-20 h-20 bg-gradient-to-br from-teal-500 to-teal-600 rounded-3xl flex items-center justify-center mb-8 animate-pulse shadow-2xl shadow-teal-500/30">
        <Leaf className="w-10 h-10 text-white" />
      </div>

      <h2 className="text-2xl font-bold text-gray-900 mb-2">
        Rebi Analiz Ediyor
      </h2>
      <p className="text-gray-500 mb-10 text-center">
        Sana özel bütüncül rutin hazırlanıyor
      </p>

      <div className="w-full max-w-sm space-y-4">
        {loadingSteps.map((step, index) => {
          const Icon = step.icon;
          const isActive = index === currentStep;
          const isDone = index < currentStep;

          return (
            <div
              key={index}
              className={`flex items-center gap-4 p-4 rounded-2xl transition-all duration-500 ${
                isActive
                  ? "bg-white shadow-lg shadow-gray-200/50 scale-[1.02]"
                  : isDone
                  ? "bg-teal-50/50 opacity-70"
                  : "opacity-30"
              }`}
            >
              <div
                className={`w-10 h-10 rounded-xl flex items-center justify-center transition-all duration-500 ${
                  isActive
                    ? "bg-teal-100"
                    : isDone
                    ? "bg-teal-500"
                    : "bg-gray-100"
                }`}
              >
                {isDone ? (
                  <svg className="w-5 h-5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M5 13l4 4L19 7" />
                  </svg>
                ) : (
                  <Icon
                    className={`w-5 h-5 ${isActive ? step.color : "text-gray-400"} ${
                      isActive ? "animate-bounce" : ""
                    }`}
                  />
                )}
              </div>
              <span
                className={`font-medium ${
                  isActive ? "text-gray-900" : isDone ? "text-teal-700" : "text-gray-400"
                }`}
              >
                {step.text}
              </span>
            </div>
          );
        })}
      </div>

      <div className="mt-10 w-full max-w-sm">
        <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
          <div
            className="h-full bg-gradient-to-r from-teal-400 to-teal-600 rounded-full transition-all duration-1000 ease-out"
            style={{
              width: `${((currentStep + 1) / loadingSteps.length) * 100}%`,
            }}
          />
        </div>
      </div>
    </div>
  );
}
