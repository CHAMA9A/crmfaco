import { Link } from "@tanstack/react-router";
import { AlertTriangle, ClipboardCheck, Plus, Scale, SlidersHorizontal } from "lucide-react";
import { useMemo, useState } from "react";

import { EmptyState, PageHeader } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useAuthenticatedUser } from "@/lib/auth/context";
import { useLanguage } from "@/lib/i18n/use-language";
import {
  stockCountStatuses,
  stockCountStatusLabels,
  type StockCountListRow,
} from "@/lib/stock-counts/types";
import { formatStockQuantity } from "@/lib/stock/types";
import type { StockCountStatus } from "@/types/database";

function CountStatus({ status }: { status: StockCountStatus }) {
  const { t } = useLanguage();
  const tone =
    status === "approved"
      ? "bg-success-soft text-success"
      : status === "submitted"
        ? "bg-warning-soft text-warning"
        : status === "rejected" || status === "cancelled"
          ? "bg-danger-soft text-danger"
          : "bg-info-soft text-info";
  return (
    <span className={`rounded-full px-2.5 py-1 text-xs font-bold ${tone}`}>
      {t(stockCountStatusLabels[status])}
    </span>
  );
}

export function StockCountList({
  rows,
  pendingAdjustments,
}: {
  rows: StockCountListRow[];
  pendingAdjustments: number;
}) {
  const { profile } = useAuthenticatedUser();
  const { language, t } = useLanguage();
  const locale = language === "fr" ? "fr-FR" : "en-GB";
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState<StockCountStatus | "all">("all");
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");
  const filtered = useMemo(() => {
    const term = search.trim().toLowerCase();
    return rows.filter(
      (row) =>
        (status === "all" || row.status === status) &&
        (!dateFrom || row.count_date >= dateFrom) &&
        (!dateTo || row.count_date <= dateTo) &&
        (!term ||
          `${row.count_number ?? "draft"} ${row.location_name} ${row.created_by_name}`
            .toLowerCase()
            .includes(term)),
    );
  }, [dateFrom, dateTo, rows, search, status]);
  const waiting = rows.filter((row) => row.status === "submitted").length;

  return (
    <>
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <PageHeader
          eyebrow="Stock"
          title="Physical stock counts"
          description="Record physical quantities, review differences, and post traceable ledger adjustments after approval."
        />
        <div className="flex flex-wrap gap-2">
          <Button asChild variant="outline">
            <Link to="/facolub/stock/adjustments">
              <SlidersHorizontal /> {t("Adjustments")}
              {pendingAdjustments > 0 && (
                <span className="rounded-full bg-warning px-2 text-[11px] text-warning-foreground">
                  {pendingAdjustments}
                </span>
              )}
            </Link>
          </Button>
          <Button asChild>
            <Link to="/facolub/stock/counts/new">
              <Plus /> {t("New count")}
            </Link>
          </Button>
        </div>
      </div>

      <section className="mb-5 grid gap-3 sm:grid-cols-3">
        <Summary label={t("Counts")} value={rows.length} icon={ClipboardCheck} />
        <Summary
          label={t("Pending approval")}
          value={waiting}
          icon={AlertTriangle}
          warning={waiting > 0}
        />
        <Summary
          label={t("Differences found")}
          value={rows.reduce((sum, row) => sum + Number(row.difference_count), 0)}
          icon={Scale}
        />
      </section>

      <div className="mb-5 grid gap-3 border bg-card p-4 sm:grid-cols-2 xl:grid-cols-[minmax(0,1fr)_170px_170px_190px]">
        <Input
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder={t("Search number, location or user")}
        />
        <Input
          type="date"
          value={dateFrom}
          onChange={(event) => setDateFrom(event.target.value)}
          aria-label={t("From")}
        />
        <Input
          type="date"
          value={dateTo}
          onChange={(event) => setDateTo(event.target.value)}
          aria-label={t("To")}
        />
        <select
          value={status}
          onChange={(event) => setStatus(event.target.value as StockCountStatus | "all")}
          className="h-9 rounded-md border bg-background px-3 text-sm"
        >
          <option value="all">{t("All statuses")}</option>
          {stockCountStatuses.map((value) => (
            <option key={value} value={value}>
              {t(stockCountStatusLabels[value])}
            </option>
          ))}
        </select>
      </div>

      {filtered.length ? (
        <div className="grid gap-3">
          {filtered.map((row) => (
            <Link
              key={row.id}
              to="/facolub/stock/counts/$countId"
              params={{ countId: row.id }}
              className="grid gap-3 border bg-card p-4 shadow-sm transition hover:border-primary sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center"
            >
              <div>
                <p className="text-xs font-black uppercase text-primary">
                  {row.count_number ?? t("Draft count")}
                </p>
                <h2 className="mt-1 font-black">{row.location_name}</h2>
                <p className="mt-1 text-sm text-muted-foreground">
                  {new Date(`${row.count_date}T00:00:00`).toLocaleDateString(locale)} ·{" "}
                  {row.item_count} {t("items")} · {row.created_by_name}
                </p>
                <p className="mt-2 text-xs font-semibold text-muted-foreground">
                  {row.difference_count} {t("differences")} · {t("Net")}{" "}
                  {formatStockQuantity(Number(row.net_difference), locale)}
                </p>
              </div>
              <CountStatus status={row.status} />
            </Link>
          ))}
        </div>
      ) : (
        <EmptyState
          title="No stock counts"
          description={
            profile.role === "factory"
              ? "Create your first physical count for the warehouse."
              : "No stock count matches these filters."
          }
          icon={ClipboardCheck}
        />
      )}
    </>
  );
}

function Summary({
  label,
  value,
  icon: Icon,
  warning = false,
}: {
  label: string;
  value: number;
  icon: typeof ClipboardCheck;
  warning?: boolean;
}) {
  return (
    <div
      className={`flex items-center gap-3 border-l-4 bg-card p-4 shadow-sm ${warning ? "border-warning" : "border-primary"}`}
    >
      <Icon className={warning ? "size-5 text-warning" : "size-5 text-primary"} />
      <div>
        <p className="text-[10px] font-bold uppercase text-muted-foreground">{label}</p>
        <p className="text-xl font-black tabular-nums">{value}</p>
      </div>
    </div>
  );
}

export { CountStatus };
