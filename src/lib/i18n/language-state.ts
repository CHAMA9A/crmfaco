import { createContext } from "react";

import type { AppLanguage } from "./translations";

export type LanguageContextValue = {
  language: AppLanguage;
  setLanguage: (language: AppLanguage) => void;
  t: (source: string) => string;
};

export const LanguageContext = createContext<LanguageContextValue | null>(null);
