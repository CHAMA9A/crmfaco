import { Link, useRouter } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import {
  CheckCircle2,
  PackageCheck,
  Pencil,
  RotateCcw,
  TriangleAlert,
  XCircle,
} from "lucide-react";
import { useMemo, useState } from "react";
import { PageHeader } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import {
  cancelProductionPlanFn,
  markProductionPlanPlannedFn,
  releaseProductionPlanReservationsFn,
  reserveProductionPlanFn,
  validateProductionPlanFn,
} from "@/lib/planning/functions";
import type { PlanningDetail } from "@/lib/planning/types";
import { formatStockQuantity } from "@/lib/stock/types";

export function PlanningDetailView({ data }: { data: PlanningDetail }) {
  const router = useRouter();
  const validate = useServerFn(validateProductionPlanFn);
  const markPlanned = useServerFn(markProductionPlanPlannedFn);
  const cancel = useServerFn(cancelProductionPlanFn);
  const reserve = useServerFn(reserveProductionPlanFn);
  const release = useServerFn(releaseProductionPlanReservationsFn);
  const [pending, setPending] = useState("");
  const [error, setError] = useState("");
  const plan = data.plan;
  const currentReservations = useMemo(() => {
    const latest = new Map<string, (typeof data.reservation.reservations)[number]>();
    for (const reservation of data.reservation.reservations)
      latest.set(reservation.requirement_id, reservation);
    return [...latest.values()];
  }, [data]);
  const act = async (action: "planned" | "validated" | "cancelled" | "reserved" | "released") => {
    if (pending) return;
    if (
      action === "cancelled" &&
      !window.confirm(
        plan.reservation_status === "reserved"
          ? "Cancel this production plan and release all material reservations?"
          : "Cancel this production plan?",
      )
    )
      return;
    if (action === "released" && !window.confirm("Release all reservations for this plan?")) return;
    setPending(action);
    setError("");
    try {
      if (action === "planned") await markPlanned({ data: { planId: plan.id } });
      else if (action === "validated") await validate({ data: { planId: plan.id } });
      else if (action === "reserved") await reserve({ data: { planId: plan.id } });
      else if (action === "released") await release({ data: { planId: plan.id } });
      else await cancel({ data: { planId: plan.id } });
      await router.invalidate();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Unable to update production plan");
    } finally {
      setPending("");
    }
  };
  return (
    <>
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <PageHeader
          eyebrow="Production planning"
          title={plan.plan_number ?? "Draft plan"}
          description={`${new Date(`${plan.production_date}T00:00:00`).toLocaleDateString()} · ${data.location_name}`}
        />
        <div className="flex flex-wrap gap-2">
          <span className="rounded-full bg-secondary px-3 py-1 text-xs font-black uppercase">
            {plan.status}
          </span>
          <ReservationStatus status={plan.reservation_status} />
          {plan.status === "draft" && (
            <Button asChild variant="outline">
              <Link to="/facolub/planning/new" search={{ planId: plan.id }}>
                <Pencil /> Edit draft
              </Link>
            </Button>
          )}
        </div>
      </div>
      <div className="grid gap-5 xl:grid-cols-[minmax(0,1.5fr)_320px]">
        <main className="space-y-5">
          {plan.status === "validated" || plan.status === "cancelled" ? (
            <section className="border bg-card p-5 shadow-sm">
              <div className="flex flex-wrap items-start justify-between gap-3 border-b pb-4">
                <div>
                  <p className="text-xs font-black uppercase text-primary">Material reservations</p>
                  <h2 className="mt-1 text-xl font-black">
                    {plan.reservation_status === "reserved"
                      ? "Fully reserved"
                      : plan.reservation_status === "consumed"
                        ? "Consumed by production"
                        : plan.reservation_status === "released"
                          ? "Reservation released"
                          : "Not reserved"}
                  </h2>
                  <p className="mt-1 text-sm text-muted-foreground">
                    {plan.reservation_status === "consumed"
                      ? "The reserved materials were resolved by the completed production execution."
                      : "Physical stock remains unchanged. Available stock reflects active reservations."}
                  </p>
                </div>
                <ReservationStatus status={plan.reservation_status} />
              </div>
              {currentReservations.length ? (
                <div className="mt-4 overflow-x-auto">
                  <table className="w-full min-w-[720px] text-left text-sm">
                    <thead className="text-xs uppercase text-muted-foreground">
                      <tr>
                        {[
                          "Component",
                          "Required",
                          "Reserved",
                          "Physical",
                          "Available now",
                          "Status",
                        ].map((label) => (
                          <th key={label} className="px-3 py-2">
                            {label}
                          </th>
                        ))}
                      </tr>
                    </thead>
                    <tbody className="divide-y">
                      {currentReservations.map((reservation) => (
                        <tr key={reservation.requirement_id}>
                          <td className="px-3 py-3 font-bold">{reservation.stock_item_name}</td>
                          <Cell value={reservation.quantity} />
                          <Cell
                            value={reservation.status === "active" ? reservation.quantity : 0}
                          />
                          <Cell value={reservation.physical_quantity} />
                          <Cell value={reservation.available_quantity} />
                          <td className="px-3 py-3">
                            <strong
                              className={
                                reservation.status === "active"
                                  ? reservation.below_minimum
                                    ? "text-warning"
                                    : "text-info"
                                  : "text-success"
                              }
                            >
                              {reservation.status === "active"
                                ? reservation.below_minimum
                                  ? "Reserved · below minimum"
                                  : "Reserved"
                                : "Released"}
                            </strong>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              ) : (
                <p className="mt-4 border border-dashed p-4 text-sm text-muted-foreground">
                  No material reservation has been created for this validated plan.
                </p>
              )}
            </section>
          ) : null}
          {data.items.map(({ item, requirements }) => (
            <section key={item.id} className="border bg-card p-5 shadow-sm">
              <div className="flex flex-wrap items-end justify-between gap-3 border-b pb-4">
                <div>
                  <h2 className="text-xl font-black">
                    {item.product_name_snapshot} · {item.format_name_snapshot}
                  </h2>
                  <p className="mt-1 text-sm text-muted-foreground">
                    Recipe snapshot · {item.bottles_per_carton} bottles/carton
                  </p>
                </div>
                <div className="text-right">
                  <p className="text-2xl font-black">{item.planned_bottles} bottles</p>
                  <p className="text-sm text-muted-foreground">{item.planned_cartons} cartons</p>
                </div>
              </div>
              <div className="mt-4 overflow-x-auto">
                <table className="w-full min-w-[760px] text-left text-sm">
                  <thead className="text-xs uppercase text-muted-foreground">
                    <tr>
                      {[
                        "Component",
                        "Required",
                        "Physical",
                        "Reserved",
                        "Available",
                        "Missing",
                        "Projected",
                        "Status",
                      ].map((label) => (
                        <th key={label} className="px-3 py-2">
                          {label}
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody className="divide-y">
                    {requirements.map((requirement) => (
                      <tr key={requirement.id}>
                        <td className="px-3 py-3 font-bold">
                          {requirement.component_name_snapshot}
                        </td>
                        <Cell value={requirement.quantity_required} />
                        <Cell value={requirement.physical_quantity_snapshot} />
                        <Cell value={requirement.reserved_quantity_snapshot} />
                        <Cell value={requirement.available_quantity_snapshot} />
                        <Cell value={requirement.missing_quantity_snapshot} />
                        <Cell value={requirement.projected_available_after_plan} />
                        <td className="px-3 py-3">
                          <strong
                            className={
                              !requirement.sufficient
                                ? "text-danger"
                                : requirement.below_minimum_after_plan
                                  ? "text-warning"
                                  : "text-success"
                            }
                          >
                            {!requirement.sufficient
                              ? "Insufficient"
                              : requirement.below_minimum_after_plan
                                ? "Below minimum"
                                : "Available"}
                          </strong>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                {requirements.length === 0 && (
                  <p className="py-6 text-sm text-muted-foreground">
                    Requirements will be snapshotted when the plan is planned or validated.
                  </p>
                )}
              </div>
            </section>
          ))}
        </main>
        <aside className="space-y-4">
          <section className="border bg-card p-5 shadow-sm">
            <h2 className="font-black">Plan information</h2>
            <dl className="mt-4 space-y-3 text-sm">
              <Info label="Created by" value={data.created_by_name} />
              <Info label="Assigned to" value={data.assigned_to_name ?? "All Factory"} />
              <Info label="Priority" value={String(plan.priority ?? "—")} />
              <Info label="Validated by" value={data.validated_by_name ?? "—"} />
              <Info label="Reservation" value={plan.reservation_status.replace("_", " ")} />
              <Info
                label="Reserved at"
                value={plan.reserved_at ? new Date(plan.reserved_at).toLocaleString() : "—"}
              />
              <Info label="Comment" value={plan.comment ?? "—"} />
            </dl>
          </section>
          {plan.status !== "cancelled" && (
            <section className="space-y-2 border bg-card p-5 shadow-sm">
              {plan.status === "draft" && (
                <Button
                  className="w-full"
                  variant="outline"
                  onClick={() => void act("planned")}
                  disabled={Boolean(pending)}
                >
                  Mark planned
                </Button>
              )}
              {["draft", "planned"].includes(plan.status) && (
                <Button
                  className="w-full"
                  onClick={() => void act("validated")}
                  disabled={Boolean(pending)}
                >
                  <CheckCircle2 /> Validate plan
                </Button>
              )}
              {plan.status === "validated" && plan.reservation_status !== "reserved" && (
                <Button
                  className="w-full"
                  onClick={() => void act("reserved")}
                  disabled={Boolean(pending)}
                >
                  <PackageCheck /> Reserve materials
                </Button>
              )}
              {plan.status === "validated" && plan.reservation_status === "reserved" && (
                <Button
                  className="w-full"
                  variant="outline"
                  onClick={() => void act("released")}
                  disabled={Boolean(pending)}
                >
                  <RotateCcw /> Release reservation
                </Button>
              )}
              <Button
                className="w-full"
                variant="outline"
                onClick={() => void act("cancelled")}
                disabled={Boolean(pending)}
              >
                <XCircle /> Cancel plan
              </Button>
            </section>
          )}
        </aside>
      </div>
      {error && (
        <p className="mt-5 flex gap-2 border border-danger/30 bg-danger-soft p-4 text-danger">
          <TriangleAlert />
          {error}
        </p>
      )}
    </>
  );
}
function ReservationStatus({ status }: { status: PlanningDetail["plan"]["reservation_status"] }) {
  const tone =
    status === "consumed"
      ? "bg-success-soft text-success"
      : status === "reserved"
        ? "bg-info-soft text-info"
        : status === "released"
          ? "bg-success-soft text-success"
          : "bg-secondary text-secondary-foreground";
  return (
    <span className={"rounded-full px-3 py-1 text-xs font-black uppercase " + tone}>
      {status.replace("_", " ")}
    </span>
  );
}
function Cell({ value }: { value: number }) {
  return <td className="px-3 py-3 tabular-nums">{formatStockQuantity(value, "en-GB")}</td>;
}
function Info({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-xs uppercase text-muted-foreground">{label}</dt>
      <dd className="mt-1 font-semibold">{value}</dd>
    </div>
  );
}
