import { CircleCheck, CircleDot, CircleX } from "lucide-react";

import { cn } from "@/lib/utils";
import { useLanguage } from "@/lib/i18n/use-language";
import type { StockStatus } from "@/lib/stock/types";

const statusDetails = {
  available: {
    label: "Available",
    icon: CircleCheck,
    className: "border-success/25 bg-success-soft text-success",
  },
  reserved: {
    label: "Reserved",
    icon: CircleDot,
    className: "border-warning/25 bg-warning-soft text-warning",
  },
  unavailable: {
    label: "Unavailable",
    icon: CircleX,
    className: "border-danger/25 bg-danger-soft text-danger",
  },
} satisfies Record<StockStatus, { label: string; icon: typeof CircleCheck; className: string }>;

export function StockStatusBadge({ status }: { status: StockStatus }) {
  const detail = statusDetails[status];
  const { t } = useLanguage();
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-bold",
        detail.className,
      )}
    >
      <detail.icon className="size-3.5" aria-hidden="true" />
      {t(detail.label)}
    </span>
  );
}
