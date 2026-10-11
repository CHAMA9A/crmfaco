import { Link } from "@tanstack/react-router";
import { CalendarDays, Plus } from "lucide-react";
import { useMemo, useState } from "react";
import { EmptyState, PageHeader } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import type { PlanningProduct } from "@/types/database";
import type { PlanningListRow } from "@/lib/planning/types";

export function PlanningHome({
  rows,
  products,
}: {
  rows: PlanningListRow[];
  products: PlanningProduct[];
}) {
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState("");
  const [sufficiency, setSufficiency] = useState("");
  const [reservationStatus, setReservationStatus] = useState("");
  const filtered = useMemo(
    () =>
      rows.filter(
        (row) =>
          (!status || row.status === status) &&
          (!sufficiency || row.sufficiency === sufficiency) &&
          (!reservationStatus || row.reservation_status === reservationStatus) &&
          (!search.trim() ||
            `${row.plan_number ?? ""} ${row.product_summary}`
              .toLowerCase()
              .includes(search.toLowerCase())),
      ),
    [reservationStatus, rows, search, status, sufficiency],
  );
  return (
    <>
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <PageHeader
          eyebrow="Production"
          title="Planning"
          description="Schedule production and preview exact material requirements without changing stock."
        />
        <Button asChild size="lg">
          <Link to="/facolub/planning/new">
            <Plus /> New production plan
          </Link>
        </Button>
      </div>
      <section className="mb-6 grid gap-3 border bg-card p-4 shadow-sm md:grid-cols-2 xl:grid-cols-[1fr_170px_180px_190px]">
        <Input
          placeholder="Plan number or product"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <select
          className="h-10 rounded-md border bg-background px-3"
          value={status}
          onChange={(e) => setStatus(e.target.value)}
        >
          <option value="">All statuses</option>
          <option value="draft">Draft</option>
          <option value="planned">Planned</option>
          <option value="validated">Validated</option>
          <option value="cancelled">Cancelled</option>
        </select>
        <select
          className="h-10 rounded-md border bg-background px-3"
          value={reservationStatus}
          onChange={(e) => setReservationStatus(e.target.value)}
        >
          <option value="">All reservation states</option>
          <option value="not_reserved">Not reserved</option>
          <option value="reserved">Reserved</option>
          <option value="released">Released</option>
        </select>
        <select
          className="h-10 rounded-md border bg-background px-3"
          value={sufficiency}
          onChange={(e) => setSufficiency(e.target.value)}
        >
          <option value="">All stock states</option>
          <option value="sufficient">Sufficient</option>
          <option value="warning">Below minimum</option>
          <option value="insufficient">Insufficient</option>
          <option value="not_calculated">Not calculated</option>
        </select>
      </section>
      {filtered.length ? (
        <div className="grid gap-3 lg:grid-cols-2">
          {filtered.map((row) => (
            <Link
              key={row.id}
              to="/facolub/planning/$planId"
              params={{ planId: row.id }}
              className="border bg-card p-5 shadow-sm transition hover:border-primary"
            >
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="text-xs font-black uppercase text-primary">
                    {row.plan_number ?? "Draft plan"}
                  </p>
                  <h2 className="mt-1 font-black">{row.product_summary || "No production line"}</h2>
                </div>
                <PlanStatus status={row.status} />
              </div>
              <dl className="mt-4 grid grid-cols-2 gap-3 border-t pt-4 text-sm">
                <Metric
                  label="Production date"
                  value={new Date(`${row.production_date}T00:00:00`).toLocaleDateString()}
                />
                <Metric label="Quantity" value={row.quantity_summary || "—"} />
                <div>
                  <dt className="text-xs uppercase text-muted-foreground">Reservation</dt>
                  <dd className="mt-1">
                    <ReservationStatus status={row.reservation_status} />
                  </dd>
                </div>
                <Metric label="Stock sufficiency" value={row.sufficiency.replace("_", " ")} />
                <Metric label="Assigned to" value={row.assigned_to_name ?? "All Factory"} />
              </dl>
            </Link>
          ))}
        </div>
      ) : (
        <EmptyState
          title="No production plans found"
          description={
            products.length
              ? "Create the next production plan."
              : "Ask an administrator to configure products and recipes first."
          }
          icon={CalendarDays}
        />
      )}
    </>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-xs uppercase text-muted-foreground">{label}</dt>
      <dd className="mt-1 font-bold capitalize">{value}</dd>
    </div>
  );
}
function ReservationStatus({ status }: { status: PlanningListRow["reservation_status"] }) {
  const tone =
    status === "consumed"
      ? "bg-success-soft text-success"
      : status === "reserved"
        ? "bg-info-soft text-info"
        : status === "released"
          ? "bg-success-soft text-success"
          : "bg-secondary text-secondary-foreground";
  return (
    <span className={`inline-flex rounded-full px-2.5 py-1 text-xs font-black uppercase ${tone}`}>
      {status.replace("_", " ")}
    </span>
  );
}
function PlanStatus({ status }: { status: PlanningListRow["status"] }) {
  return (
    <span className="rounded-full bg-secondary px-3 py-1 text-xs font-black uppercase">
      {status}
    </span>
  );
}
