import { Link } from "@tanstack/react-router";
import { Factory, Search } from "lucide-react";
import { useMemo, useState } from "react";
import { EmptyState, PageHeader, StatusBadge } from "@/components/app/facolub-ui";
import { Input } from "@/components/ui/input";
import { productionStatusLabels, type ProductionHistoryRow } from "@/lib/production/types";
import type { ProductionExecutionStatus } from "@/types/database";

export function ProductionHistory({ rows }: { rows: ProductionHistoryRow[] }) {
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState<ProductionExecutionStatus | "all">("all");
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");
  const [operator, setOperator] = useState("all");
  const operators = useMemo(
    () =>
      [
        ...new Set(
          rows.flatMap((row) => [row.started_by_name, row.completed_by_name]).filter(Boolean),
        ),
      ].sort() as string[],
    [rows],
  );
  const filtered = useMemo(() => {
    const term = search.trim().toLowerCase();
    return rows.filter(
      (row) =>
        (status === "all" || row.status === status) &&
        (!dateFrom || row.production_date >= dateFrom) &&
        (!dateTo || row.production_date <= dateTo) &&
        (operator === "all" ||
          row.started_by_name === operator ||
          row.completed_by_name === operator) &&
        (!term ||
          `${row.execution_number} ${row.plan_number} ${row.product_summary} ${row.started_by_name ?? ""} ${row.completed_by_name ?? ""}`
            .toLowerCase()
            .includes(term)),
    );
  }, [rows, search, status, dateFrom, dateTo, operator]);

  return (
    <>
      <PageHeader
        eyebrow="Production"
        title="Production history"
        description="Follow current runs, completed quantities, variances and reported problems."
      />
      <div className="mb-5 grid gap-3 border bg-card p-4 sm:grid-cols-2 xl:grid-cols-[minmax(0,1fr)_170px_170px_190px_180px]">
        <label className="relative">
          <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search execution, plan or product"
            className="pl-9"
          />
        </label>
        <Input
          type="date"
          value={dateFrom}
          onChange={(event) => setDateFrom(event.target.value)}
          aria-label="Production date from"
        />
        <Input
          type="date"
          value={dateTo}
          onChange={(event) => setDateTo(event.target.value)}
          aria-label="Production date to"
        />
        <select
          value={operator}
          onChange={(event) => setOperator(event.target.value)}
          className="h-9 rounded-md border border-input bg-background px-3 text-sm"
          aria-label="Production operator"
        >
          <option value="all">All operators</option>
          {operators.map((name) => (
            <option key={name} value={name}>
              {name}
            </option>
          ))}
        </select>
        <select
          value={status}
          onChange={(event) => setStatus(event.target.value as ProductionExecutionStatus | "all")}
          className="h-9 rounded-md border border-input bg-background px-3 text-sm"
          aria-label="Execution status"
        >
          <option value="all">All statuses</option>
          {Object.entries(productionStatusLabels).map(([value, label]) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>
      </div>
      {filtered.length ? (
        <div className="grid gap-3">
          {filtered.map((row) => (
            <Link
              key={row.execution_id}
              to="/facolub/production/$executionId"
              params={{ executionId: row.execution_id }}
              className="grid gap-3 border bg-card p-4 shadow-sm transition hover:border-primary sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center"
            >
              <div>
                <p className="text-xs font-black uppercase text-primary">{row.execution_number}</p>
                <h2 className="mt-1 font-black">{row.product_summary}</h2>
                <p className="mt-1 text-sm text-muted-foreground">
                  {new Date(`${row.production_date}T00:00:00`).toLocaleDateString()} · Planned{" "}
                  {row.planned_bottles} bottles
                  {row.actual_bottles !== null ? ` · Actual ${row.actual_bottles}` : ""}
                </p>
                <p className="mt-2 text-xs font-semibold text-muted-foreground">
                  Started by {row.started_by_name ?? "—"} · Completed by{" "}
                  {row.completed_by_name ?? "—"}
                  {row.variance_bottles !== null
                    ? ` · Variance ${row.variance_bottles} bottles`
                    : ""}
                </p>
              </div>
              <StatusBadge status={productionStatusLabels[row.status]} />
            </Link>
          ))}
        </div>
      ) : (
        <EmptyState
          title="No production executions"
          description="No execution matches these filters."
          icon={Factory}
        />
      )}
    </>
  );
}
