import { ArrowDown, ArrowUp, RotateCcw } from "lucide-react";
import { useMemo, useState } from "react";

import { EmptyState, PageHeader } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { useLanguage } from "@/lib/i18n/use-language";
import {
  formatStockQuantity,
  stockCategoryLabels,
  stockMovementLabels,
  stockMovementTypes,
  type StockHistoryData,
} from "@/lib/stock/types";

const anyValue = "__all__";

function localDateKey(value: string) {
  const date = new Date(value);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function StockHistory({ data }: { data: StockHistoryData }) {
  const { language, t } = useLanguage();
  const locale = language === "fr" ? "fr-FR" : "en-GB";
  const [item, setItem] = useState(anyValue);
  const [category, setCategory] = useState(anyValue);
  const [movementType, setMovementType] = useState(anyValue);
  const [user, setUser] = useState(anyValue);
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");

  const itemOptions = useMemo(
    () => [...new Map(data.rows.map((row) => [row.stock_item_id, row.stock_item_name])).entries()],
    [data.rows],
  );
  const userOptions = useMemo(
    () => [...new Map(data.rows.map((row) => [row.created_by, row.created_by_name])).entries()],
    [data.rows],
  );
  const rows = data.rows.filter((row) => {
    const date = localDateKey(row.created_at);
    return (
      (item === anyValue || row.stock_item_id === item) &&
      (category === anyValue || row.category === category) &&
      (movementType === anyValue || row.movement_type === movementType) &&
      (user === anyValue || row.created_by === user) &&
      (!dateFrom || date >= dateFrom) &&
      (!dateTo || date <= dateTo)
    );
  });
  const clear = () => {
    setItem(anyValue);
    setCategory(anyValue);
    setMovementType(anyValue);
    setUser(anyValue);
    setDateFrom("");
    setDateTo("");
  };

  return (
    <>
      <PageHeader
        title="Stock movement history"
        description="Immutable physical stock entries. Errors remain visible and are reversed by linked corrections."
      />

      <section className="mb-6 border border-border bg-card p-4 shadow-sm">
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <Filter label={t("Item")} value={item} onChange={setItem}>
            <option value={anyValue}>{t("All items")}</option>
            {itemOptions.map(([id, name]) => (
              <option key={id} value={id}>
                {name}
              </option>
            ))}
          </Filter>
          <Filter label={t("Category")} value={category} onChange={setCategory}>
            <option value={anyValue}>{t("All categories")}</option>
            {Object.entries(stockCategoryLabels).map(([value, label]) => (
              <option key={value} value={value}>
                {t(label)}
              </option>
            ))}
          </Filter>
          <Filter label={t("Movement type")} value={movementType} onChange={setMovementType}>
            <option value={anyValue}>{t("All movement types")}</option>
            {stockMovementTypes.map((value) => (
              <option key={value} value={value}>
                {t(stockMovementLabels[value])}
              </option>
            ))}
          </Filter>
          <Filter label={t("User")} value={user} onChange={setUser}>
            <option value={anyValue}>{t("All users")}</option>
            {userOptions.map(([id, name]) => (
              <option key={id} value={id}>
                {name}
              </option>
            ))}
          </Filter>
          <DateFilter label={t("From")} value={dateFrom} onChange={setDateFrom} />
          <DateFilter label={t("To")} value={dateTo} onChange={setDateTo} />
          <div className="flex items-end sm:col-span-2">
            <Button type="button" variant="outline" onClick={clear}>
              <RotateCcw /> {t("Clear filters")}
            </Button>
          </div>
        </div>
      </section>

      <p className="mb-3 text-sm font-semibold text-muted-foreground">
        {rows.length} {t(rows.length === 1 ? "movement" : "movements")}
      </p>
      {rows.length === 0 ? (
        <EmptyState
          title="No movements found"
          description="No immutable ledger entries match the selected filters."
          icon={RotateCcw}
        />
      ) : (
        <>
          <div className="space-y-3 md:hidden">
            {rows.map((row) => (
              <article key={row.id} className="border bg-card p-4 shadow-sm">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="font-bold">{row.stock_item_name}</p>
                    <p className="mt-1 text-xs text-muted-foreground">
                      {new Date(row.created_at).toLocaleString(locale)} · {row.location_name}
                    </p>
                  </div>
                  <Direction direction={row.direction} quantity={row.quantity} />
                </div>
                <dl className="mt-4 grid grid-cols-2 gap-3 border-t pt-3 text-sm">
                  <div>
                    <dt className="text-xs text-muted-foreground">{t("Type")}</dt>
                    <dd className="font-semibold">{t(stockMovementLabels[row.movement_type])}</dd>
                  </div>
                  <div>
                    <dt className="text-xs text-muted-foreground">{t("User")}</dt>
                    <dd className="font-semibold">{row.created_by_name}</dd>
                  </div>
                  <div className="col-span-2">
                    <dt className="text-xs text-muted-foreground">{t("Reason / reference")}</dt>
                    <dd>{row.reason ?? row.reference_type ?? "—"}</dd>
                  </div>
                </dl>
              </article>
            ))}
          </div>
          <div className="hidden overflow-x-auto border bg-card md:block">
            <table className="w-full text-sm">
              <thead className="border-b bg-muted/50 text-left text-xs uppercase text-muted-foreground">
                <tr>
                  <th className="px-3 py-3">{t("Date / time")}</th>
                  <th className="px-3 py-3">{t("Stock items")}</th>
                  <th className="px-3 py-3">{t("Movement type")}</th>
                  <th className="px-3 py-3">{t("Direction / quantity")}</th>
                  <th className="px-3 py-3">{t("User")}</th>
                  <th className="px-3 py-3">{t("Reason")}</th>
                  <th className="px-3 py-3">{t("Reference")}</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((row) => (
                  <tr key={row.id} className="border-b last:border-0">
                    <td className="whitespace-nowrap px-3 py-3">
                      {new Date(row.created_at).toLocaleString(locale)}
                    </td>
                    <td className="px-3 py-3">
                      <p className="font-bold">{row.stock_item_name}</p>
                      <p className="text-xs text-muted-foreground">
                        {t(stockCategoryLabels[row.category])} · {row.location_name}
                      </p>
                    </td>
                    <td className="px-3 py-3">{t(stockMovementLabels[row.movement_type])}</td>
                    <td className="px-3 py-3">
                      <Direction direction={row.direction} quantity={row.quantity} />
                    </td>
                    <td className="px-3 py-3">{row.created_by_name}</td>
                    <td className="max-w-52 px-3 py-3">{row.reason ?? "—"}</td>
                    <td className="max-w-44 px-3 py-3 text-xs text-muted-foreground">
                      {row.reference_type
                        ? `${row.reference_type}${row.reference_id ? ` · ${row.reference_id.slice(0, 8)}…` : ""}`
                        : "—"}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </>
  );
}

function Filter({
  label,
  value,
  onChange,
  children,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  children: React.ReactNode;
}) {
  return (
    <label className="text-sm font-bold">
      {label}
      <select
        className="mt-1.5 h-10 w-full rounded-md border bg-background px-3 font-normal"
        value={value}
        onChange={(event) => onChange(event.target.value)}
      >
        {children}
      </select>
    </label>
  );
}

function DateFilter({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <label className="text-sm font-bold">
      {label}
      <input
        type="date"
        className="mt-1.5 h-10 w-full rounded-md border bg-background px-3 font-normal"
        value={value}
        onChange={(event) => onChange(event.target.value)}
      />
    </label>
  );
}

function Direction({ direction, quantity }: { direction: "in" | "out"; quantity: number }) {
  const Icon = direction === "in" ? ArrowDown : ArrowUp;
  const { language, t } = useLanguage();
  const locale = language === "fr" ? "fr-FR" : "en-US";
  return (
    <span
      className={
        direction === "in"
          ? "inline-flex items-center gap-1 font-black text-success"
          : "inline-flex items-center gap-1 font-black text-danger"
      }
    >
      <Icon className="size-4" />
      {t(direction.toUpperCase())} {formatStockQuantity(quantity, locale)}
    </span>
  );
}
