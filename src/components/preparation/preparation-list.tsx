import { Link } from "@tanstack/react-router";
import { CalendarClock, PackageCheck, UserRound } from "lucide-react";

import { Button } from "@/components/ui/button";
import { useLanguage } from "@/lib/i18n/use-language";
import type { PreparationListRow } from "@/lib/preparation/types";
import { formatStockQuantity } from "@/lib/stock/types";
import { PreparationStatusBadge } from "./preparation-status";

export function PreparationCards({ rows }: { rows: PreparationListRow[] }) {
  const { language, t } = useLanguage();
  const locale = language === "fr" ? "fr-FR" : "en-GB";
  return (
    <div className="grid gap-3 lg:grid-cols-2">
      {rows.map((row) => (
        <article key={row.id} className="border bg-card p-4 shadow-sm sm:p-5">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <p className="truncate text-lg font-black">
                {row.preparation_number ?? t("Draft preparation")}
              </p>
              <p className="mt-1 font-semibold text-primary">
                {row.product_name} · {row.format_name}
              </p>
            </div>
            <PreparationStatusBadge status={row.status} />
          </div>
          <div className="mt-4 grid gap-3 text-sm sm:grid-cols-3">
            <span className="inline-flex items-center gap-2 text-muted-foreground">
              <CalendarClock className="size-4" />
              {new Date(row.created_at).toLocaleString(locale, {
                dateStyle: "short",
                timeStyle: "short",
              })}
            </span>
            <span className="inline-flex items-center gap-2 font-semibold">
              <PackageCheck className="size-4 text-primary" />
              {row.quantity == null ? "—" : formatStockQuantity(row.quantity, locale)}
            </span>
            <span className="inline-flex items-center gap-2 text-muted-foreground">
              <UserRound className="size-4" /> {row.created_by_name}
            </span>
          </div>
          <p className="mt-3 border-t pt-3 text-xs font-semibold text-muted-foreground">
            {row.output_stock_item_name}
          </p>
          <div className="mt-4 flex justify-end">
            <Button asChild variant="outline" size="sm">
              <Link to="/facolub/preparation/$preparationId" params={{ preparationId: row.id }}>
                {t("Open")}
              </Link>
            </Button>
          </div>
        </article>
      ))}
    </div>
  );
}
