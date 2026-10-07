import { useEffect, useMemo, useState, type ReactNode } from "react";

import { LanguageContext, type LanguageContextValue } from "./language-state";
import { translate, type AppLanguage } from "./translations";

const storageKey = "facolub-language";

export function LanguageProvider({ children }: { children: ReactNode }) {
  const [language, setLanguage] = useState<AppLanguage>("en");
  const [ready, setReady] = useState(false);

  useEffect(() => {
    let saved: string | null = null;
    try {
      saved = window.localStorage.getItem(storageKey);
    } catch {
      // Language selection still works when browser storage is unavailable.
    }
    const detected: AppLanguage =
      saved === "fr" || saved === "en"
        ? saved
        : window.navigator.language.toLowerCase().startsWith("fr")
          ? "fr"
          : "en";
    setLanguage(detected);
    setReady(true);
  }, []);

  useEffect(() => {
    if (!ready) return;
    document.documentElement.lang = language;
    try {
      window.localStorage.setItem(storageKey, language);
    } catch {
      // Keep the in-memory selection for this session.
    }
  }, [language, ready]);

  const value = useMemo<LanguageContextValue>(
    () => ({ language, setLanguage, t: (source) => translate(language, source) }),
    [language],
  );
  return <LanguageContext.Provider value={value}>{children}</LanguageContext.Provider>;
}
