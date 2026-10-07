import { useServerFn } from "@tanstack/react-start";
import { RotateCcw, Search } from "lucide-react";
import { useState, type FormEvent } from "react";

import { EmptyState, PageHeader } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useLanguage } from "@/lib/i18n/use-language";
import { searchReceiptsFn } from "@/lib/receiving/functions";
import type { ReceivingHistoryData } from "@/lib/receiving/types";
import type { ReceiptListRow, ReceiptStatus } from "@/types/database";
import { ReceiptCards } from "./receipt-list";

export function ReceivingHistory({ data }: { data: ReceivingHistoryData }) {
  const { t } = useLanguage();
  const searchReceipts = useServerFn(searchReceiptsFn);
  const [rows, setRows] = useState<ReceiptListRow[]>(data.rows);
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState("");
  const [supplierId, setSupplierId] = useState("");
  const [stockItemId, setStockItemId] = useState("");
  const [createdBy, setCreatedBy] = useState("");
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");

  const submit = async (event?: FormEvent) => {
    event?.preventDefault();
    setPending(true);
    setError("");
    try {
      setRows(
        await searchReceipts({
          data: {
            search: search.trim() || null,
            status: (status || null) as ReceiptStatus | null,
            supplierId: supplierId || null,
            stockItemId: stockItemId || null,
            createdBy: createdBy || null,
            dateFrom: dateFrom || null,
            dateTo: dateTo || null,
            limit: 500,
          },
        }),
      );
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t("Unable to load receipts"));
    } finally {
      setPending(false);
    }
  };

  const clear = () => {
    setSearch("");
    setStatus("");
    setSupplierId("");
    setStockItemId("");
    setCreatedBy("");
    setDateFrom("");
    setDateTo("");
    setRows(data.rows);
    setError("");
  };

  return (
    <>
      <PageHeader
        eyebrow="Receiving"
        title="Receiving history"
        description="Search confirmed, draft, and cancelled receiving operations."
      />
      <form onSubmit={submit} className="mb-6 border bg-card p-4 shadow-sm">
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <label className="text-sm font-bold sm:col-span-2">
            {t("Search")}
            <span className="relative mt-1.5 block">
              <Search className="pointer-events-none absolute left-3 top-3 size-4 text-muted-foreground" />
              <Input
                className="h-10 pl-9"
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                placeholder={t("Receipt number, supplier, or reference")}
              />
            </span>
          </label>
          <HistorySelect label={t("Status")} value={status} onChange={setStatus}>
            <option value="">{t("All statuses")}</option>
            <option value="draft">{t("Draft")}</option>
            <option value="confirmed">{t("Confirmed")}</option>
            <option value="cancelled">{t("Cancelled")}</option>
          </HistorySelect>
          <HistorySelect label={t("Supplier")} value={supplierId} onChange={setSupplierId}>
            <option value="">{t("All suppliers")}</option>
            {data.suppliers.map((supplier) => (
              <option key={supplier.id} value={supplier.id}>
                {supplier.name}
              </option>
            ))}
          </HistorySelect>
          <HistorySelect label={t("Item")} value={stockItemId} onChange={setStockItemId}>
            <option value="">{t("All items")}</option>
            {data.stockItems.map((item) => (
              <option key={item.id} value={item.id}>
                {item.name}
              </option>
            ))}
          </HistorySelect>
          <HistorySelect label={t("User")} value={createdBy} onChange={setCreatedBy}>
            <option value="">{t("All users")}</option>
            {data.users.map((user) => (
              <option key={user.id} value={user.id}>
                {user.display_name}
              </option>
            ))}
          </HistorySelect>
          <HistoryDate label={t("From")} value={dateFrom} onChange={setDateFrom} />
          <HistoryDate label={t("To")} value={dateTo} onChange={setDateTo} />
        </div>
        {error && <p className="mt-3 text-sm font-semibold text-danger">{error}</p>}
        <div className="mt-4 flex flex-wrap gap-2">
          <Button disabled={pending}>{pending ? t("Loading…") : t("Apply filters")}</Button>
          <Button type="button" variant="outline" onClick={clear}>
            <RotateCcw /> {t("Clear filters")}
          </Button>
        </div>
      </form>

      <p className="mb-3 text-sm font-semibold text-muted-foreground">
        {rows.length} {t(rows.length === 1 ? "receipt" : "receipts")}
      </p>
      {rows.length ? (
        <ReceiptCards rows={rows} />
      ) : (
        <EmptyState
          title="No receipts found"
          description="No receiving operation matches the selected filters."
          icon={RotateCcw}
        />
      )}
    </>
  );
}

function HistorySelect({
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

function HistoryDate({
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
      <Input
        className="mt-1.5 h-10 font-normal"
        type="date"
        value={value}
        onChange={(event) => onChange(event.target.value)}
      />
    </label>
  );
}
