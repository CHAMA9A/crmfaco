import { Link } from "@tanstack/react-router";
import { CalendarClock, Camera, PackageCheck, UserRound } from "lucide-react";

import { Button } from "@/components/ui/button";
import { useLanguage } from "@/lib/i18n/use-language";
import type { ReceiptListRow } from "@/types/database";
import { ReceiptStatusBadge } from "./receipt-status";

export function ReceiptCards({ rows }: { rows: ReceiptListRow[] }) {
  const { language, t } = useLanguage();
  const locale = language === "fr" ? "fr-FR" : "en-GB";

  return (
    <div className="grid gap-3 lg:grid-cols-2">
      {rows.map((receipt) => (
        <article key={receipt.id} className="border bg-card p-4 shadow-sm sm:p-5">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <p className="truncate text-lg font-black">
                {receipt.receipt_number ?? t("Draft receipt")}
              </p>
              <p className="mt-1 truncate text-sm text-muted-foreground">
                {receipt.supplier_name ?? t("No supplier")}
              </p>
            </div>
            <ReceiptStatusBadge status={receipt.status} />
          </div>

          <div className="mt-4 grid grid-cols-2 gap-3 text-sm">
            <span className="inline-flex items-center gap-2 text-muted-foreground">
              <CalendarClock className="size-4" />
              {new Date(receipt.created_at).toLocaleString(locale, {
                dateStyle: "short",
                timeStyle: "short",
              })}
            </span>
            <span className="inline-flex items-center gap-2 text-muted-foreground">
              <UserRound className="size-4" /> {receipt.created_by_name}
            </span>
            <span className="inline-flex items-center gap-2 font-semibold">
              <PackageCheck className="size-4 text-primary" /> {receipt.item_count}{" "}
              {t(receipt.item_count === 1 ? "item" : "items")}
            </span>
            <span className="inline-flex items-center gap-2 font-semibold">
              <Camera className="size-4 text-primary" /> {receipt.photo_count}{" "}
              {t(receipt.photo_count === 1 ? "photo" : "photos")}
            </span>
          </div>

          {receipt.quantity_summary && (
            <p className="mt-3 border-t pt-3 text-xs font-semibold text-muted-foreground">
              {receipt.quantity_summary}
            </p>
          )}
          <div className="mt-4 flex justify-end">
            <Button asChild variant="outline" size="sm">
              <Link to="/facolub/receiving/$receiptId" params={{ receiptId: receipt.id }}>
                {t("Open")}
              </Link>
            </Button>
          </div>
        </article>
      ))}
    </div>
  );
}
