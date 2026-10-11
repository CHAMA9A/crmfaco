import { useServerFn } from "@tanstack/react-start";
import { CalendarDays, LoaderCircle, Save, ShieldCheck, TriangleAlert } from "lucide-react";
import { useEffect, useMemo, useState, type ReactNode } from "react";
import { PageHeader } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { calculateProductionRequirementsFn, saveProductionPlanFn } from "@/lib/planning/functions";
import type { PlanningEditorData, PlanningPreview } from "@/lib/planning/types";
import { formatStockQuantity } from "@/lib/stock/types";
import { cn } from "@/lib/utils";

export function PlanningForm({ data }: { data: PlanningEditorData }) {
  const calculate = useServerFn(calculateProductionRequirementsFn);
  const savePlan = useServerFn(saveProductionPlanFn);
  const existing = data.plan?.plan;
  const line = data.plan?.items[0]?.item;
  const initialFormat = data.productFormats.find((item) => item.id === line?.product_format_id);
  const [date, setDate] = useState(
    existing?.production_date ?? new Date().toISOString().slice(0, 10),
  );
  const [productId, setProductId] = useState(initialFormat?.product_id ?? "");
  const [productFormatId, setProductFormatId] = useState(line?.product_format_id ?? "");
  const [mode, setMode] = useState<"bottles" | "cartons">(line?.quantity_mode ?? "cartons");
  const [quantity, setQuantity] = useState(String(line?.entered_quantity ?? ""));
  const [locationId, setLocationId] = useState(
    existing?.location_id ?? data.locations[0]?.id ?? "",
  );
  const [priority, setPriority] = useState(String(existing?.priority ?? 3));
  const [assignedTo, setAssignedTo] = useState(existing?.assigned_to ?? "");
  const [comment, setComment] = useState(existing?.comment ?? "");
  const [preview, setPreview] = useState<PlanningPreview | null>(null);
  const [loading, setLoading] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const formats = useMemo(
    () => data.productFormats.filter((item) => item.product_id === productId),
    [data.productFormats, productId],
  );

  useEffect(() => {
    const numeric = Number(quantity);
    if (!productFormatId || !locationId || !Number.isInteger(numeric) || numeric <= 0) {
      setPreview(null);
      return;
    }
    let active = true;
    const timer = window.setTimeout(async () => {
      setLoading(true);
      setError("");
      try {
        const result = await calculate({
          data: { productFormatId, locationId, quantity: numeric, mode },
        });
        if (active) setPreview(result);
      } catch (caught) {
        if (active) {
          setPreview(null);
          setError(caught instanceof Error ? caught.message : "Unable to calculate requirements");
        }
      } finally {
        if (active) setLoading(false);
      }
    }, 250);
    return () => {
      active = false;
      window.clearTimeout(timer);
    };
  }, [calculate, locationId, mode, productFormatId, quantity]);

  const submit = async (validateAfterSave: boolean) => {
    if (pending || !preview) return;
    setPending(true);
    setError("");
    try {
      const result = await savePlan({
        data: {
          planId: existing?.id ?? null,
          planItemId: line?.id ?? null,
          productionDate: date,
          locationId,
          priority: Number(priority),
          assignedTo,
          comment,
          productFormatId,
          quantity: Number(quantity),
          mode,
          validateAfterSave,
        },
      });
      window.location.assign(`/facolub/planning/${result.id}`);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Unable to save production plan");
      setPending(false);
    }
  };

  return (
    <>
      <PageHeader
        eyebrow="Production planning"
        title={existing ? "Edit draft plan" : "New production plan"}
        description="Enter one production line. The server normalizes cartons and bottles and previews available stock."
      />
      <div className="mx-auto max-w-4xl space-y-5 pb-28 lg:pb-0">
        <section className="border bg-card p-5 shadow-sm">
          <h2 className="mb-4 flex items-center gap-2 border-b pb-3 font-black">
            <CalendarDays className="size-5 text-primary" /> Plan details
          </h2>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <Field label="Production date">
              <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
            </Field>
            <Field label="Priority">
              <select
                className="h-10 w-full rounded-md border bg-background px-3"
                value={priority}
                onChange={(e) => setPriority(e.target.value)}
              >
                {[1, 2, 3, 4, 5].map((item) => (
                  <option key={item}>{item}</option>
                ))}
              </select>
            </Field>
            <Field label="Assigned Factory user">
              <select
                className="h-10 w-full rounded-md border bg-background px-3"
                value={assignedTo}
                onChange={(e) => setAssignedTo(e.target.value)}
              >
                <option value="">All Factory</option>
                {data.factoryUsers.map((user) => (
                  <option key={user.id} value={user.id}>
                    {user.display_name}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="Location">
              <select
                className="h-10 w-full rounded-md border bg-background px-3"
                value={locationId}
                onChange={(e) => setLocationId(e.target.value)}
              >
                {data.locations.map((location) => (
                  <option key={location.id} value={location.id}>
                    {location.name}
                  </option>
                ))}
              </select>
            </Field>
          </div>
          <div className="mt-4">
            <Field label="Comment">
              <Textarea
                value={comment}
                onChange={(e) => setComment(e.target.value)}
                maxLength={2000}
              />
            </Field>
          </div>
        </section>
        <section className="border bg-card p-5 shadow-sm">
          <h2 className="mb-4 border-b pb-3 font-black">Production line</h2>
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Product">
              <select
                className="h-12 w-full rounded-md border bg-background px-3"
                value={productId}
                onChange={(e) => {
                  setProductId(e.target.value);
                  setProductFormatId("");
                }}
              >
                <option value="">Select product</option>
                {data.products.map((product) => (
                  <option key={product.id} value={product.id}>
                    {product.name}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="Format">
              <select
                className="h-12 w-full rounded-md border bg-background px-3"
                value={productFormatId}
                onChange={(e) => setProductFormatId(e.target.value)}
                disabled={!productId}
              >
                <option value="">Select format</option>
                {formats.map((format) => (
                  <option key={format.id} value={format.id}>
                    {format.format_name}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="Quantity">
              <Input
                className="h-14 text-2xl font-black"
                type="number"
                min="1"
                step="1"
                value={quantity}
                onChange={(e) => setQuantity(e.target.value)}
              />
            </Field>
            <Field label="Planning unit">
              <select
                className="h-14 w-full rounded-md border bg-background px-3 font-bold"
                value={mode}
                onChange={(e) => setMode(e.target.value as "bottles" | "cartons")}
              >
                <option value="cartons">Cartons</option>
                <option value="bottles">Bottles</option>
              </select>
            </Field>
          </div>
          {preview && (
            <div className="mt-5 grid grid-cols-3 gap-3 bg-secondary p-4 text-center">
              <Metric label="Bottles / carton" value={String(preview.bottles_per_carton)} />
              <Metric label="Total bottles" value={String(preview.planned_bottles)} />
              <Metric label="Total cartons" value={String(preview.planned_cartons)} />
            </div>
          )}
        </section>
        <section className="border bg-card p-5 shadow-sm">
          <h2 className="mb-4 font-black">Component requirements</h2>
          {loading && (
            <p className="flex gap-2 text-sm">
              <LoaderCircle className="size-4 animate-spin" /> Calculating…
            </p>
          )}
          {!preview && !loading && (
            <p className="text-sm text-muted-foreground">
              Select product, format, quantity, and unit.
            </p>
          )}
          {preview && (
            <div className="space-y-3">
              {preview.components.map((item) => (
                <article
                  key={item.stock_item_id}
                  className={cn(
                    "border p-4",
                    !item.sufficient
                      ? "border-danger/30 bg-danger-soft"
                      : item.below_minimum_after_plan
                        ? "border-warning/30 bg-warning-soft"
                        : "border-success/30 bg-success-soft",
                  )}
                >
                  <div className="flex justify-between gap-3">
                    <div>
                      <p className="font-black">{item.name}</p>
                      <p className="text-xs uppercase text-muted-foreground">
                        {item.role.replaceAll("_", " ")}
                      </p>
                    </div>
                    <strong className={item.sufficient ? "text-success" : "text-danger"}>
                      {item.sufficient
                        ? item.below_minimum_after_plan
                          ? "Warning"
                          : "Available"
                        : "Insufficient"}
                    </strong>
                  </div>
                  <dl className="mt-3 grid grid-cols-3 gap-2 sm:grid-cols-6">
                    {[
                      ["Physical", item.physical_quantity],
                      ["Reserved", item.reserved_quantity],
                      ["Available", item.available_quantity],
                      ["Required", item.required_quantity],
                      ["Missing", item.missing_quantity],
                      ["Projected", item.projected_available_after_plan],
                    ].map(([label, value]) => (
                      <Metric
                        key={String(label)}
                        label={String(label)}
                        value={formatStockQuantity(Number(value), "en-GB")}
                      />
                    ))}
                  </dl>
                </article>
              ))}
            </div>
          )}
        </section>
        <p className="flex gap-2 border border-info/30 bg-info-soft p-4 text-sm">
          <ShieldCheck className="size-5 shrink-0" /> Planning never consumes stock and never
          creates reservations. Insufficient plans may still be validated.
        </p>
        {error && (
          <p
            role="alert"
            className="flex gap-2 border border-danger/30 bg-danger-soft p-4 text-sm font-semibold text-danger"
          >
            <TriangleAlert className="size-5" />
            {error}
          </p>
        )}
        <div className="fixed inset-x-0 bottom-16 z-30 border-t bg-background/95 p-3 lg:static lg:border-0 lg:bg-transparent">
          <div className="mx-auto grid max-w-4xl grid-cols-2 gap-3 lg:flex lg:justify-end">
            <Button
              variant="outline"
              size="lg"
              disabled={pending || !preview}
              onClick={() => void submit(false)}
            >
              {pending ? <LoaderCircle className="animate-spin" /> : <Save />} Save draft
            </Button>
            <Button size="lg" disabled={pending || !preview} onClick={() => void submit(true)}>
              Validate plan
            </Button>
          </div>
        </div>
      </div>
    </>
  );
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="space-y-2">
      <Label>{label}</Label>
      {children}
    </label>
  );
}
function Metric({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-[11px] uppercase text-muted-foreground">{label}</dt>
      <dd className="mt-1 font-black tabular-nums">{value}</dd>
    </div>
  );
}
