import { Link } from "@tanstack/react-router";
import {
  AlertTriangle,
  Boxes,
  ClipboardCheck,
  History,
  MapPin,
  Search,
  Settings2,
  SlidersHorizontal,
} from "lucide-react";
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
          <h3 className="font-bold leading-5">
            {row.display_oil ?? row.display_product ?? row.display_format ?? row.name}
          </h3>
          <p className="mt-1 text-xs text-muted-foreground">
            {row.code ? `${row.code} · ` : ""}
            {t(stockUnitLabels[row.unit])}
          </p>
          {row.category === "empty_bottle" && row.used_by_products.length > 0 && (
            <p className="mt-1 text-xs text-muted-foreground">
              {t("Used by")}: {row.used_by_products.join(", ")}
            </p>
          )}
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
  const category = rows[0]?.category;
  return (
    <div className="hidden overflow-x-auto border border-border bg-card md:block">
      <table className="w-full text-sm">
        <thead className="border-b bg-muted/50 text-left text-xs uppercase text-muted-foreground">
          <tr>
            {category === "finished_product" && <th className="px-4 py-3">{t("SKU")}</th>}
            <th className="px-4 py-3">
              {t(
                category === "bulk_lubricant"
                  ? "Oil"
                  : category === "empty_bottle"
                    ? "Format"
                    : category === "label" ||
                        category === "prepared_bottle" ||
                        category === "finished_product"
                      ? "Product"
                      : "Item",
              )}
            </th>
            {(category === "label" ||
              category === "prepared_bottle" ||
              category === "finished_product") && <th className="px-4 py-3">{t("Format")}</th>}
            {category === "empty_bottle" && <th className="px-4 py-3">{t("Used by")}</th>}
            <th className="px-4 py-3 text-right">{t("Physical")}</th>
            <th className="px-4 py-3 text-right">{t("Reserved")}</th>
            <th className="px-4 py-3 text-right">{t("Available")}</th>
            <th className="px-4 py-3">{t("Unit")}</th>
            <th className="px-4 py-3">{t("Status")}</th>
            <th className="px-4 py-3">{t("Threshold")}</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => {
            const low = isLowStock(row.available_quantity, row.minimum_stock);
            return (
              <tr key={`${row.id}:${row.location_id}`} className="border-b last:border-0">
                {category === "finished_product" && (
                  <td className="px-4 py-3 font-mono text-xs font-semibold">
                    {row.display_sku ?? row.code ?? "—"}
                  </td>
                )}
                <td className="px-4 py-3">
                  <p className="font-bold">
                    {category === "bulk_lubricant"
                      ? (row.display_oil ?? row.name)
                      : category === "empty_bottle"
                        ? (row.display_format ?? row.name)
                        : (row.display_product ?? row.name)}
                  </p>
                  {category !== "finished_product" && row.code && (
                    <p className="mt-0.5 text-xs text-muted-foreground">{row.code}</p>
                  )}
                </td>
                {(category === "label" ||
                  category === "prepared_bottle" ||
                  category === "finished_product") && (
                  <td className="px-4 py-3 font-semibold">{row.display_format ?? "—"}</td>
                )}
                {category === "empty_bottle" && (
                  <td className="max-w-xs px-4 py-3 text-xs text-muted-foreground">
                    {row.used_by_products.join(", ") || "—"}
                  </td>
                )}
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
  const [search, setSearch] = useState("");
  const locationRows = useMemo(
    () => data.rows.filter((row) => !locationId || row.location_id === locationId),
    [data.rows, locationId],
  );
  const rows = useMemo(() => {
    const query = search.trim().toLocaleLowerCase();
    if (!query) return locationRows;
    return locationRows.filter((row) =>
      [
        row.code,
        row.name,
        row.display_sku,
        row.display_product,
        row.display_format,
        row.display_oil,
      ]
        .filter(Boolean)
        .join(" ")
        .toLocaleLowerCase()
        .includes(query),
    );
  }, [locationRows, search]);
  const lowCount = locationRows.filter((row) =>
    isLowStock(row.available_quantity, row.minimum_stock),
  ).length;
  const reservedCount = locationRows.filter((row) => row.reserved_quantity > 0).length;

  return (
    <>
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <PageHeader
          title="Stock"
          description="Physical stock from confirmed movements, active reservations, and available quantity."
        />
        <div className="flex flex-wrap gap-2">
          <Button asChild>
            <Link to="/facolub/stock/counts">
              <ClipboardCheck /> {t("Physical counts")}
            </Link>
          </Button>
          <Button asChild variant="outline">
            <Link to="/facolub/stock/adjustments">
              <SlidersHorizontal /> {t("Adjustments")}
            </Link>
          </Button>
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
          <p className="mt-1 text-xl font-black tabular-nums">{locationRows.length}</p>
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

      <label className="relative mb-7 block max-w-xl">
        <span className="sr-only">{t("Search stock")}</span>
        <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
        <input
          type="search"
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder={t("Search SKU, product, format, or oil")}
          className="h-11 w-full rounded-md border bg-background pl-10 pr-3 text-sm"
        />
      </label>

      {rows.length === 0 ? (
        <EmptyState
          title={search ? "No matching stock items" : "No stock items configured"}
          description={
            search
              ? "Try another SKU, product, format, or oil."
              : "An Admin can create the first stock item in Stock item settings."
          }
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
