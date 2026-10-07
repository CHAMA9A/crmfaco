import { Languages } from "lucide-react";

import { useLanguage } from "@/lib/i18n/use-language";
import { cn } from "@/lib/utils";

export function LanguageToggle({ className }: { className?: string }) {
  const { language, setLanguage } = useLanguage();
  return (
    <div
      className={cn(
        "inline-flex h-9 items-center rounded-md border bg-background p-0.5",
        className,
      )}
      role="group"
      aria-label={language === "fr" ? "Choisir la langue" : "Choose language"}
    >
      <Languages
        className="mx-1.5 hidden size-4 text-muted-foreground sm:block"
        aria-hidden="true"
      />
      {(["fr", "en"] as const).map((value) => (
        <button
          key={value}
          type="button"
          aria-pressed={language === value}
          onClick={() => setLanguage(value)}
          className={cn(
            "grid h-7 min-w-8 place-items-center rounded px-1.5 text-[11px] font-black transition-colors",
            language === value
              ? "bg-primary text-primary-foreground shadow-sm"
              : "text-muted-foreground hover:bg-muted hover:text-foreground",
          )}
        >
          {value.toUpperCase()}
        </button>
      ))}
    </div>
  );
}
