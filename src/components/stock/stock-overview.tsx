import { Link } from "@tanstack/react-router";
import { AlertTriangle, Boxes, History, MapPin, Settings2 } from "lucide-react";
import { useMemo, useState } from "react";

import { EmptyState, PageHeader } from "@/components/app/facolub-ui";
import { StockStatusBadge } from "./stock-status";
import { Button } from "@/components/ui/button";
import { useAuthenticatedUser } from "@/lib/auth/context";
import { useLanguage } from "@/lib/i18n/use-language";
import {
  formatStockQuantity,
  getStockStatus,
  isLowStock,
  stockCategories,
  stockCategoryLabels,
  stockUnitLabels,
  type StockOverviewData,
  type StockOverviewRow,
} from "@/lib/stock/types";

function StockNumbers({ row }: { row: StockOverviewRow }) {
  const { language, t } = useLanguage();
  const locale = language === "fr" ? "fr-FR" : "en-US";
  const values = [
    ["Physical", row.physical_quantity],
    ["Reserved", row.reserved_quantity],
    ["Available", row.available_quantity],
  ] as const;
  return (
    <dl className="grid grid-cols-3 gap-2 border-y py-3">
      {values.map(([label, value]) => (
        <div key={label}>
          <dt className="text-[10px] font-bold uppercase text-muted-foreground">{t(label)}</dt>
          <dd className="mt-1 text-lg font-black tabular-nums">
            {formatStockQuantity(value, locale)}
          </dd>
        </div>
      ))}
    </dl>
  );
}

function MobileStockCard({ row }: { row: StockOverviewRow }) {
  const low = isLowStock(row.available_quantity, row.minimum_stock);
  const { language, t } = useLanguage();
  const locale = language === "fr" ? "fr-FR" : "en-US";
  return (
    <article className="border border-border bg-card p-4 shadow-sm md:hidden">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <h3 className="font-bold leading-5">{row.name}</h3>
          <p className="mt-1 text-xs text-muted-foreground">
            {row.code ? `${row.code} · ` : ""}
            {t(stockUnitLabels[row.unit])}
          </p>
        </div>
        <StockStatusBadge status={getStockStatus(row.available_quantity, row.reserved_quantity)} />
      </div>
      <div className="mt-4">
        <StockNumbers row={row} />
      </div>
      <div className="mt-3 flex items-center justify-between gap-3 text-xs">
        <span className="text-muted-foreground">
          {t("Minimum")}:{" "}
          {row.minimum_stock === null
            ? t("Not set")
            : formatStockQuantity(row.minimum_stock, locale)}
        </span>
        {low && (
          <span className="inline-flex items-center gap-1 font-bold text-danger">
            <AlertTriangle className="size-3.5" /> {t("Low stock")}
          </span>
        )}
      </div>
    </article>
  );
}

function DesktopStockTable({ rows }: { rows: StockOverviewRow[] }) {
  const { language, t } = useLanguage();
  const locale = language === "fr" ? "fr-FR" : "en-US";
  return (
    <div className="hidden overflow-x-auto border border-border bg-card md:block">
      <table className="w-full text-sm">
        <thead className="border-b bg-muted/50 text-left text-xs uppercase text-muted-foreground">
          <tr>
            <th className="px-4 py-3">{t("Item")}</th>
            <th className="px-4 py-3 text-right">{t("Physical")}</th>
            <th className="px-4 py-3 text-right">{t("Reserved")}</th>
            <th className="px-4 py-3 text-right">{t("Available")}</th>
            <th className="px-4 py-3">{t("Unit")}</th>
            <th className="px-4 py-3">{t("State")}</th>
            <th className="px-4 py-3">{t("Threshold")}</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => {
            const low = isLowStock(row.available_quantity, row.minimum_stock);
            return (
              <tr key={`${row.id}:${row.location_id}`} className="border-b last:border-0">
                <td className="px-4 py-3">
                  <p className="font-bold">{row.name}</p>
                  {row.code && <p className="mt-0.5 text-xs text-muted-foreground">{row.code}</p>}
                </td>
                <td className="px-4 py-3 text-right font-semibold tabular-nums">
                  {formatStockQuantity(row.physical_quantity, locale)}
                </td>
                <td className="px-4 py-3 text-right font-semibold tabular-nums">
                  {formatStockQuantity(row.reserved_quantity, locale)}
                </td>
                <td className="px-4 py-3 text-right text-base font-black tabular-nums">
                  {formatStockQuantity(row.available_quantity, locale)}
                </td>
                <td className="px-4 py-3">{t(stockUnitLabels[row.unit])}</td>
                <td className="px-4 py-3">
                  <StockStatusBadge
                    status={getStockStatus(row.available_quantity, row.reserved_quantity)}
                  />
                </td>
                <td className="px-4 py-3">
                  {low ? (
                    <span className="inline-flex items-center gap-1 font-bold text-danger">
                      <AlertTriangle className="size-4" /> {t("Low")}
                    </span>
                  ) : row.minimum_stock === null ? (
                    <span className="text-muted-foreground">{t("Not set")}</span>
                  ) : (
                    <span className="tabular-nums">
                      ≥ {formatStockQuantity(row.minimum_stock, locale)}
                    </span>
                  )}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

export function StockOverview({ data }: { data: StockOverviewData }) {
  const { profile } = useAuthenticatedUser();
  const { t } = useLanguage();
  const [locationId, setLocationId] = useState(data.locations[0]?.id ?? "");
  const rows = useMemo(
    () => data.rows.filter((row) => !locationId || row.location_id === locationId),
    [data.rows, locationId],
  );
  const lowCount = rows.filter((row) =>
    isLowStock(row.available_quantity, row.minimum_stock),
  ).length;
  const reservedCount = rows.filter((row) => row.reserved_quantity > 0).length;

  return (
    <>
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <PageHeader
          title="Stock"
          description="Physical stock from confirmed movements, active reservations, and available quantity."
        />
        <div className="flex flex-wrap gap-2">
          <Button asChild variant="outline">
            <Link to="/facolub/stock/history">
              <History /> {t("Movement history")}
            </Link>
          </Button>
          {profile.role === "admin" && (
            <Button asChild>
              <Link to="/facolub/settings/stock-items">
                <Settings2 /> {t("Configure items")}
              </Link>
            </Button>
          )}
        </div>
      </div>

      <section className="mb-7 grid grid-cols-3 gap-3" aria-label="Stock summary">
        <div className="border-l-4 border-info bg-card p-4 shadow-sm">
          <p className="text-[10px] font-bold uppercase text-muted-foreground">
            {t("Active items")}
          </p>
          <p className="mt-1 text-xl font-black tabular-nums">{rows.length}</p>
        </div>
        <div className="border-l-4 border-warning bg-card p-4 shadow-sm">
          <p className="text-[10px] font-bold uppercase text-muted-foreground">{t("Reserved")}</p>
          <p className="mt-1 text-xl font-black tabular-nums">{reservedCount}</p>
        </div>
        <div className="border-l-4 border-danger bg-card p-4 shadow-sm">
          <p className="text-[10px] font-bold uppercase text-muted-foreground">{t("Low stock")}</p>
          <p className="mt-1 text-xl font-black tabular-nums">{lowCount}</p>
        </div>
      </section>

      {data.locations.length > 1 && (
        <label className="mb-7 block max-w-sm text-sm font-bold">
          <span className="mb-2 flex items-center gap-2">
            <MapPin className="size-4" /> {t("Location")}
          </span>
          <select
            className="h-10 w-full rounded-md border bg-background px-3 font-normal"
            value={locationId}
            onChange={(event) => setLocationId(event.target.value)}
          >
            {data.locations.map((location) => (
              <option key={location.id} value={location.id}>
                {location.name}
              </option>
            ))}
          </select>
        </label>
      )}

      {rows.length === 0 ? (
        <EmptyState
          title="No stock items configured"
          description="An Admin can create the first stock item in Stock item settings."
          icon={Boxes}
        />
      ) : (
        <div className="space-y-8">
          {stockCategories.map((category) => {
            const categoryRows = rows.filter((row) => row.category === category);
            return (
              <section key={category} aria-labelledby={`stock-${category}`}>
                <div className="mb-3 flex items-center justify-between gap-3">
                  <h2 id={`stock-${category}`} className="text-lg font-bold">
                    {t(stockCategoryLabels[category])}
                  </h2>
                  <span className="text-xs font-semibold text-muted-foreground">
                    {categoryRows.length} {t(categoryRows.length === 1 ? "item" : "items")}
                  </span>
                </div>
                {categoryRows.length ? (
                  <>
                    <div className="space-y-3 md:hidden">
                      {categoryRows.map((row) => (
                        <MobileStockCard key={`${row.id}:${row.location_id}`} row={row} />
                      ))}
                    </div>
                    <DesktopStockTable rows={categoryRows} />
                  </>
                ) : (
                  <div className="border border-dashed bg-card px-4 py-5 text-sm text-muted-foreground">
                    {t("No active items in this category.")}
                  </div>
                )}
              </section>
            );
          })}
        </div>
      )}
    </>
  );
}
