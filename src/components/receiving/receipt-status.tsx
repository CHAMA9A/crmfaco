import { Badge } from "@/components/ui/badge";
import { useLanguage } from "@/lib/i18n/use-language";
import { receiptStatusLabels } from "@/lib/receiving/types";
import type { ReceiptStatus } from "@/types/database";
import { cn } from "@/lib/utils";

export function ReceiptStatusBadge({ status }: { status: ReceiptStatus }) {
  const { t } = useLanguage();
  return (
    <Badge
      variant="outline"
      className={cn(
        "rounded-full px-2.5 py-1 text-[11px] font-black uppercase tracking-wide",
        status === "confirmed" && "border-success/30 bg-success-soft text-success",
        status === "draft" && "border-warning/30 bg-warning-soft text-warning",
        status === "cancelled" && "border-danger/30 bg-danger-soft text-danger",
      )}
    >
      {t(receiptStatusLabels[status])}
    </Badge>
  );
}
