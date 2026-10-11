import { useServerFn } from "@tanstack/react-start";
import { RotateCcw } from "lucide-react";
import { useState, type FormEvent } from "react";

import { EmptyState, PageHeader } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useLanguage } from "@/lib/i18n/use-language";
import { searchPreparationsFn } from "@/lib/preparation/functions";
import type { PreparationHistoryData, PreparationListRow } from "@/lib/preparation/types";
import type { PreparationStatus } from "@/types/database";
import { PreparationCards } from "./preparation-list";

export function PreparationHistory({ data }: { data: PreparationHistoryData }) {
  const { t } = useLanguage();
  const searchFn = useServerFn(searchPreparationsFn);
  const [rows, setRows] = useState<PreparationListRow[]>(data.rows);
  const [filters, setFilters] = useState({
    dateFrom: "",
    dateTo: "",
    productName: "",
    formatName: "",
    createdBy: "",
    status: "",
  });
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const set = (key: keyof typeof filters, value: string) =>
    setFilters((current) => ({ ...current, [key]: value }));
  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setPending(true);
    setError("");
    try {
      setRows(
        await searchFn({
          data: {
            dateFrom: filters.dateFrom || null,
            dateTo: filters.dateTo || null,
            productName: filters.productName || null,
            formatName: filters.formatName || null,
            createdBy: filters.createdBy || null,
            status: (filters.status || null) as PreparationStatus | null,
            limit: 500,
          },
        }),
      );
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t("Unable to load preparations"));
    } finally {
      setPending(false);
    }
  };
  const clear = () => {
    setFilters({
      dateFrom: "",
      dateTo: "",
      productName: "",
      formatName: "",
      createdBy: "",
      status: "",
    });
    setRows(data.rows);
    setError("");
  };
  return (
    <>
      <PageHeader
        eyebrow="Prepared bottles"
        title="Preparation history"
        description="Inspect component usage, output, status, date, and operator."
      />
      <form onSubmit={submit} className="mb-6 border bg-card p-4 shadow-sm">
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <Filter
            label={t("Product")}
            value={filters.productName}
            onChange={(v) => set("productName", v)}
            options={data.products}
          />
          <Filter
            label={t("Format")}
            value={filters.formatName}
            onChange={(v) => set("formatName", v)}
            options={data.formats}
          />
          <label className="text-sm font-bold">
            {t("Status")}
            <select
              className="mt-1.5 h-10 w-full rounded-md border bg-background px-3 font-normal"
              value={filters.status}
              onChange={(e) => set("status", e.target.value)}
            >
              <option value="">{t("All statuses")}</option>
              <option value="draft">{t("Draft")}</option>
              <option value="confirmed">{t("Confirmed")}</option>
              <option value="cancelled">{t("Cancelled")}</option>
            </select>
          </label>
          <label className="text-sm font-bold">
            {t("User")}
            <select
              className="mt-1.5 h-10 w-full rounded-md border bg-background px-3 font-normal"
              value={filters.createdBy}
              onChange={(e) => set("createdBy", e.target.value)}
            >
              <option value="">{t("All users")}</option>
              {data.users.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.display_name}
                </option>
              ))}
            </select>
          </label>
          <label className="text-sm font-bold">
            {t("From")}
            <Input
              className="mt-1.5"
              type="date"
              value={filters.dateFrom}
              onChange={(e) => set("dateFrom", e.target.value)}
            />
          </label>
          <label className="text-sm font-bold">
            {t("To")}
            <Input
              className="mt-1.5"
              type="date"
              value={filters.dateTo}
              onChange={(e) => set("dateTo", e.target.value)}
            />
          </label>
        </div>
        {error && <p className="mt-3 text-sm font-semibold text-danger">{error}</p>}
        <div className="mt-4 flex gap-2">
          <Button disabled={pending}>{pending ? t("Loading…") : t("Apply filters")}</Button>
          <Button type="button" variant="outline" onClick={clear}>
            <RotateCcw /> {t("Clear filters")}
          </Button>
        </div>
      </form>
      {rows.length ? (
        <PreparationCards rows={rows} />
      ) : (
        <EmptyState
          title="No preparations found"
          description="No preparation matches the selected filters."
          icon={RotateCcw}
        />
      )}
    </>
  );
}

function Filter({
  label,
  value,
  onChange,
  options,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  options: string[];
}) {
  const { t } = useLanguage();
  return (
    <label className="text-sm font-bold">
      {label}
      <select
        className="mt-1.5 h-10 w-full rounded-md border bg-background px-3 font-normal"
        value={value}
        onChange={(e) => onChange(e.target.value)}
      >
        <option value="">{t("All")}</option>
        {options.map((option) => (
          <option key={option}>{option}</option>
        ))}
      </select>
    </label>
  );
}
