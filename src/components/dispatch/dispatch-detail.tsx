import { useServerFn } from "@tanstack/react-start";
import {
  Camera,
  CheckCircle2,
  FileImage,
  LoaderCircle,
  Package,
  Save,
  ShieldCheck,
  Truck,
} from "lucide-react";
import { useMemo, useState, type ChangeEvent } from "react";
import { PageHeader } from "@/components/app/facolub-ui";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  attachDispatchPhotoFn,
  confirmDispatchFn,
  prepareDispatchDocumentsFn,
  saveDispatchDraftFn,
} from "@/lib/dispatch/functions";
import {
  buildDispatchStoragePath,
  type DispatchAttachmentCategory,
  type DispatchDetail,
  validateLoadedQuantity,
} from "@/lib/dispatch/types";
import { prepareReceiptPhoto } from "@/lib/receiving/images";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { useAuthenticatedUser } from "@/lib/auth/context";

function Step({ n, title, children }: { n: number; title: string; children: React.ReactNode }) {
  return (
    <section className="border bg-card p-4 shadow-sm sm:p-5">
      <div className="mb-4 flex items-center gap-3 border-b pb-3">
        <span className="grid size-8 place-items-center rounded-full bg-primary text-sm font-black text-primary-foreground">
          {n}
        </span>
        <h2 className="font-black uppercase tracking-wide">{title}</h2>
      </div>
      {children}
    </section>
  );
}

export function DispatchDetailView({ data }: { data: DispatchDetail }) {
  const { profile } = useAuthenticatedUser();
  const saveFn = useServerFn(saveDispatchDraftFn);
  const attachFn = useServerFn(attachDispatchPhotoFn);
  const confirmFn = useServerFn(confirmDispatchFn);
  const docsFn = useServerFn(prepareDispatchDocumentsFn);
  const d = data.dispatch;
  const existingByOrder = useMemo(
    () => new Map(data.items.map((x) => [x.order_item_id, x.quantity_loaded])),
    [data.items],
  );
  const [quantities, setQuantities] = useState<Record<string, string>>(() =>
    Object.fromEntries(
      data.remaining.map((x) => [
        x.order_item_id,
        existingByOrder.get(x.order_item_id)?.toString() ?? "",
      ]),
    ),
  );
  const [vehicle, setVehicle] = useState(d.vehicle_description ?? "");
  const [plate, setPlate] = useState(d.vehicle_registration ?? "");
  const [driver, setDriver] = useState(d.driver_name ?? "");
  const [phone, setPhone] = useState(d.driver_phone ?? "");
  const [company, setCompany] = useState(d.transport_company ?? "");
  const [notes, setNotes] = useState(d.notes ?? "");
  const [attachments, setAttachments] = useState(data.attachments);
  const [pending, setPending] = useState("");
  const [error, setError] = useState("");
  const draft = d.status === "draft";
  async function save(confirm = false) {
    setError("");
    const items = data.remaining
      .filter((x) => quantities[x.order_item_id] !== "")
      .map((x) => ({
        order_item_id: x.order_item_id,
        quantity_loaded: Number(quantities[x.order_item_id]),
      }));
    for (const line of items) {
      const r = data.remaining.find((x) => x.order_item_id === line.order_item_id)!;
      const issue = validateLoadedQuantity(line.quantity_loaded, Number(r.remaining));
      if (issue) {
        setError(`${r.sku}: ${issue}`);
        return;
      }
    }
    if (!items.length) {
      setError("Enter at least one real loaded quantity.");
      return;
    }
    setPending(confirm ? "confirm" : "save");
    try {
      await saveFn({
        data: {
          dispatchId: d.id,
          vehicleDescription: vehicle,
          vehicleRegistration: plate,
          driverName: driver,
          driverPhone: phone,
          transportCompany: company,
          notes,
          items,
        },
      });
      if (confirm) {
        await confirmFn({ data: { dispatchId: d.id } });
      }
      window.location.reload();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Action failed");
      setPending("");
    }
  }
  async function upload(
    category: DispatchAttachmentCategory,
    event: ChangeEvent<HTMLInputElement>,
  ) {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    setPending(`photo-${category}`);
    setError("");
    try {
      const prepared = await prepareReceiptPhoto(file);
      const path = buildDispatchStoragePath(d.id, prepared.name);
      const supabase = getSupabaseBrowserClient();
      const upload = await supabase.storage
        .from("facolub-dispatch")
        .upload(path, prepared, { contentType: prepared.type, upsert: false });
      if (upload.error) throw upload.error;
      const row = await attachFn({
        data: {
          dispatchId: d.id,
          category,
          storagePath: path,
          fileName: prepared.name,
          mimeType: prepared.type,
          fileSize: prepared.size,
        },
      });
      setAttachments((x) => [...x, row as never]);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Photo upload failed");
    } finally {
      setPending("");
    }
  }
  if (!draft)
    return (
      <>
        <div className="flex flex-col gap-4 sm:flex-row sm:justify-between">
          <PageHeader
            eyebrow="Confirmed dispatch"
            title={d.dispatch_number ?? "Dispatch"}
            description={`${d.destination_name} · ${d.confirmed_at ? new Date(d.confirmed_at).toLocaleString() : d.dispatch_date}`}
          />
          <div className="flex gap-2">
            <Badge>Confirmed</Badge>
            {profile.role !== "factory" && d.order_id && (
              <Button
                onClick={async () => {
                  setPending("docs");
                  try {
                    await docsFn({ data: { dispatchId: d.id } });
                    window.location.reload();
                  } catch (e) {
                    setError(e instanceof Error ? e.message : "Unable to prepare documents");
                    setPending("");
                  }
                }}
                disabled={pending === "docs"}
              >
                <FileImage />
                Prepare BL / BT
              </Button>
            )}
          </div>
        </div>
        {error && <p className="mb-4 text-danger">{error}</p>}
        <section className="grid gap-4 border bg-card p-5 sm:grid-cols-3">
          <div>
            <p className="text-xs uppercase text-muted-foreground">Driver</p>
            <p className="font-bold">{d.driver_name}</p>
          </div>
          <div>
            <p className="text-xs uppercase text-muted-foreground">Vehicle</p>
            <p className="font-bold">{d.vehicle_description || "—"}</p>
          </div>
          <div>
            <p className="text-xs uppercase text-muted-foreground">Registration</p>
            <p className="font-bold">{d.vehicle_registration}</p>
          </div>
        </section>
        <section className="mt-6 border bg-card">
          <div className="border-b p-4 font-black">Actual loaded quantities</div>
          {data.items.map((i) => (
            <div key={i.id} className="flex justify-between border-b p-4 last:border-0">
              <span>
                {i.sku_snapshot} · {i.description_snapshot}
              </span>
              <strong>{i.quantity_loaded}</strong>
            </div>
          ))}
        </section>
        <section className="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
          {attachments.map((a) => (
            <div key={a.id} className="border bg-card p-2">
              {a.signed_url && (
                <img
                  src={a.signed_url}
                  className="aspect-square w-full object-cover"
                  alt={`${a.category} evidence`}
                />
              )}
              <p className="mt-2 text-xs font-bold uppercase">{a.category}</p>
            </div>
          ))}
        </section>
      </>
    );
  return (
    <>
      <PageHeader
        eyebrow="Physical loading"
        title={d.destination_name}
        description="Enter only what is physically on the vehicle. Confirmation creates the stock OUT."
      />
      <div className="space-y-5 pb-28 lg:pb-0">
        <Step n={1} title="Products">
          {data.remaining.map((line) => (
            <div key={line.order_item_id} className="mb-3 border bg-background p-4 last:mb-0">
              <div className="flex justify-between gap-4">
                <div>
                  <p className="font-black">{line.sku}</p>
                  <p className="text-sm text-muted-foreground">{line.description}</p>
                </div>
                <Package className="size-5 text-primary" />
              </div>
              <dl className="mt-3 grid grid-cols-3 gap-2 text-sm">
                <div>
                  <dt className="text-xs text-muted-foreground">Ordered</dt>
                  <dd className="font-bold">{line.ordered}</dd>
                </div>
                <div>
                  <dt className="text-xs text-muted-foreground">Dispatched</dt>
                  <dd className="font-bold">{line.dispatched}</dd>
                </div>
                <div>
                  <dt className="text-xs text-muted-foreground">Remaining</dt>
                  <dd className="font-black text-primary">{line.remaining}</dd>
                </div>
              </dl>
              <Label className="mt-4 block">Loaded now</Label>
              <Input
                className="mt-2 h-12 text-lg font-black"
                inputMode="decimal"
                type="number"
                min="0.001"
                max={line.remaining}
                step="0.001"
                value={quantities[line.order_item_id] ?? ""}
                onChange={(e) =>
                  setQuantities((q) => ({ ...q, [line.order_item_id]: e.target.value }))
                }
                placeholder="Enter real quantity"
              />
            </div>
          ))}
        </Step>
        <Step n={2} title="Vehicle">
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <Label>Driver *</Label>
              <Input
                className="mt-2 h-11"
                value={driver}
                onChange={(e) => setDriver(e.target.value)}
              />
            </div>
            <div>
              <Label>Registration plate *</Label>
              <Input
                className="mt-2 h-11"
                value={plate}
                onChange={(e) => setPlate(e.target.value)}
              />
            </div>
            <div>
              <Label>Vehicle description</Label>
              <Input
                className="mt-2 h-11"
                value={vehicle}
                onChange={(e) => setVehicle(e.target.value)}
              />
            </div>
            <div>
              <Label>Driver phone</Label>
              <Input
                className="mt-2 h-11"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
              />
            </div>
            <div>
              <Label>Transport company</Label>
              <Input
                className="mt-2 h-11"
                value={company}
                onChange={(e) => setCompany(e.target.value)}
              />
            </div>
            <div>
              <Label>Notes</Label>
              <Textarea className="mt-2" value={notes} onChange={(e) => setNotes(e.target.value)} />
            </div>
          </div>
        </Step>
        <Step n={3} title="Photo evidence">
          <p className="mb-4 text-sm text-muted-foreground">
            At least one goods photo and one vehicle or registration photo are required.
          </p>
          <div className="grid grid-cols-2 gap-3">
            <Button asChild variant="outline" size="lg">
              <label className="cursor-pointer">
                <Camera />
                Goods photo
                <input
                  className="sr-only"
                  type="file"
                  accept="image/*"
                  capture="environment"
                  onChange={(e) => void upload("goods", e)}
                />
              </label>
            </Button>
            <Button asChild variant="outline" size="lg">
              <label className="cursor-pointer">
                <Truck />
                Vehicle / plate
                <input
                  className="sr-only"
                  type="file"
                  accept="image/*"
                  capture="environment"
                  onChange={(e) => void upload("registration", e)}
                />
              </label>
            </Button>
          </div>
          <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
            {attachments.map((a) => (
              <div key={a.id} className="border p-2">
                {a.signed_url ? (
                  <img
                    src={a.signed_url}
                    className="aspect-square w-full object-cover"
                    alt={a.category}
                  />
                ) : (
                  <ShieldCheck className="mx-auto my-8" />
                )}
                <p className="mt-2 text-xs font-black uppercase">{a.category}</p>
              </div>
            ))}
          </div>
        </Step>
        <Step n={4} title="Review">
          <p className="flex gap-2 border border-warning/30 bg-warning-soft p-3 text-sm">
            <ShieldCheck className="size-5 shrink-0" />
            Confirmation is atomic and permanent. It reduces finished-product stock only.
          </p>
        </Step>
        {error && (
          <p
            role="alert"
            className="border border-danger/30 bg-danger-soft p-4 text-sm font-semibold text-danger"
          >
            {error}
          </p>
        )}
        <div className="fixed inset-x-0 bottom-16 z-30 grid grid-cols-2 gap-3 border-t bg-background/95 p-3 backdrop-blur lg:static lg:flex lg:justify-end lg:border-0">
          <Button variant="outline" size="lg" disabled={!!pending} onClick={() => void save(false)}>
            {pending === "save" ? <LoaderCircle className="animate-spin" /> : <Save />}Save draft
          </Button>
          <Button size="lg" disabled={!!pending} onClick={() => void save(true)}>
            {pending === "confirm" ? <LoaderCircle className="animate-spin" /> : <CheckCircle2 />}
            Confirm loading
          </Button>
        </div>
      </div>
    </>
  );
}
