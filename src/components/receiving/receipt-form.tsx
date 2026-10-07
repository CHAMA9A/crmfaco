import { useServerFn } from "@tanstack/react-start";
import {
  Camera,
  CheckCircle2,
  FileImage,
  LoaderCircle,
  MapPin,
  PackagePlus,
  Plus,
  Save,
  ShieldCheck,
  Trash2,
  Truck,
  WifiOff,
} from "lucide-react";
import { useEffect, useMemo, useState, type ChangeEvent } from "react";

import { PageHeader } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { useLanguage } from "@/lib/i18n/use-language";
import {
  addReceiptItemFn,
  attachReceiptPhotoFn,
  confirmReceiptFn,
  createReceiptDraftFn,
  detachReceiptPhotoFn,
  removeReceiptItemFn,
  updateReceiptDraftFn,
} from "@/lib/receiving/functions";
import { prepareReceiptPhoto } from "@/lib/receiving/images";
import {
  buildReceiptStoragePath,
  receivingDraftStorageKey,
  type LocalReceiptDraft,
  type ReceiptDetailAttachment,
  type ReceiptDraftLine,
  type ReceiptEditorData,
  validateReceiptLines,
  validateReceiptPhoto,
} from "@/lib/receiving/types";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { formatStockQuantity, stockUnitLabels } from "@/lib/stock/types";

function makeLineKey() {
  return typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random()}`;
}

function confirmationKey(receiptId: string) {
  return `facolub-receipt-confirmation:${receiptId}`;
}

export function ReceiptForm({ data }: { data: ReceiptEditorData }) {
  const existing = data.receipt;
  const createDraft = useServerFn(createReceiptDraftFn);
  const updateDraft = useServerFn(updateReceiptDraftFn);
  const addItem = useServerFn(addReceiptItemFn);
  const removeItem = useServerFn(removeReceiptItemFn);
  const attachPhoto = useServerFn(attachReceiptPhotoFn);
  const detachPhoto = useServerFn(detachReceiptPhotoFn);
  const confirmReceipt = useServerFn(confirmReceiptFn);
  const { language, t } = useLanguage();
  const locale = language === "fr" ? "fr-FR" : "en-GB";

  const [receiptId, setReceiptId] = useState<string | null>(existing?.receipt.id ?? null);
  const storageKey = receiptId
    ? `${receivingDraftStorageKey}:${receiptId}`
    : receivingDraftStorageKey;
  const [receiptDate, setReceiptDate] = useState(existing?.receipt.receipt_date ?? data.today);
  const [locationId, setLocationId] = useState(
    existing?.receipt.location_id ?? data.locations[0]?.id ?? "",
  );
  const [supplierId, setSupplierId] = useState(existing?.receipt.supplier_id ?? "");
  const [supplierName, setSupplierName] = useState(
    existing?.receipt.supplier_id ? "" : (existing?.receipt.supplier_name_snapshot ?? ""),
  );
  const [reference, setReference] = useState(existing?.receipt.reference ?? "");
  const [comment, setComment] = useState(existing?.receipt.comment ?? "");
  const [lines, setLines] = useState<ReceiptDraftLine[]>(
    existing?.items.length
      ? existing.items.map((item) => ({
          key: item.id,
          id: item.id,
          stockItemId: item.stock_item_id,
          quantity: String(item.quantity),
        }))
      : [{ key: "initial-line", id: null, stockItemId: "", quantity: "" }],
  );
  const [attachments, setAttachments] = useState(existing?.attachments ?? []);
  const [photos, setPhotos] = useState<File[]>([]);
  const [hydrated, setHydrated] = useState(false);
  const [pending, setPending] = useState<"save" | "confirm" | "remove-photo" | null>(null);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  useEffect(() => {
    try {
      const raw = localStorage.getItem(storageKey);
      if (raw) {
        const saved = JSON.parse(raw) as LocalReceiptDraft;
        if (!existing || !saved.receiptId || saved.receiptId === existing.receipt.id) {
          setReceiptId(saved.receiptId ?? existing?.receipt.id ?? null);
          setReceiptDate(saved.receiptDate || data.today);
          setLocationId(saved.locationId || data.locations[0]?.id || "");
          setSupplierId(saved.supplierId || "");
          setSupplierName(saved.supplierName || "");
          setReference(saved.reference || "");
          setComment(saved.comment || "");
          if (saved.lines?.length) setLines(saved.lines);
          setNotice("Unsaved form data was restored on this device.");
        }
      }
    } catch {
      // Local persistence is best-effort; the server remains authoritative.
    } finally {
      setHydrated(true);
    }
  }, [data.locations, data.today, existing, storageKey]);

  const localDraft = useMemo<LocalReceiptDraft>(
    () => ({
      receiptId,
      receiptDate,
      locationId,
      supplierId,
      supplierName,
      reference,
      comment,
      lines,
    }),
    [comment, lines, locationId, receiptDate, receiptId, reference, supplierId, supplierName],
  );

  useEffect(() => {
    if (!hydrated) return;
    try {
      localStorage.setItem(storageKey, JSON.stringify(localDraft));
      if (receiptId) localStorage.removeItem(receivingDraftStorageKey);
    } catch {
      // The form stays in React state even when localStorage is unavailable.
    }
  }, [hydrated, localDraft, receiptId, storageKey]);

  const locationItems = useMemo(
    () => data.stockItems.filter((item) => item.location_id === locationId),
    [data.stockItems, locationId],
  );
  const itemById = useMemo(
    () => new Map(locationItems.map((item) => [item.id, item])),
    [locationItems],
  );

  const updateLine = (key: string, field: "stockItemId" | "quantity", value: string) => {
    setLines((current) =>
      current.map((line) => (line.key === key ? { ...line, [field]: value } : line)),
    );
  };

  const addLine = () => {
    setLines((current) => [
      ...current,
      { key: makeLineKey(), id: null, stockItemId: "", quantity: "" },
    ]);
  };

  const removeLine = (key: string) => {
    setLines((current) => current.filter((line) => line.key !== key));
  };

  const addPhotos = (event: ChangeEvent<HTMLInputElement>) => {
    const next = [...(event.target.files ?? [])];
    event.target.value = "";
    const invalid = next.map(validateReceiptPhoto).find(Boolean);
    if (invalid) {
      setError(t(invalid));
      return;
    }
    setError("");
    setPhotos((current) => [...current, ...next].slice(0, 10));
  };

  const removeExistingPhoto = async (attachmentId: string) => {
    if (pending) return;
    setPending("remove-photo");
    setError("");
    try {
      const { storagePath } = await detachPhoto({ data: { attachmentId } });
      const { error: storageError } = await getSupabaseBrowserClient()
        .storage.from("facolub-receipts")
        .remove([storagePath]);
      if (storageError) throw storageError;
      setAttachments((current) => current.filter((item) => item.id !== attachmentId));
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t("Unable to remove photo"));
    } finally {
      setPending(null);
    }
  };

  const uploadPhotos = async (targetReceiptId: string) => {
    const uploaded: ReceiptDetailAttachment[] = [];
    for (const rawFile of photos) {
      const file = await prepareReceiptPhoto(rawFile);
      const token = makeLineKey();
      const storagePath = buildReceiptStoragePath(targetReceiptId, file.name, token);
      const storage = getSupabaseBrowserClient().storage.from("facolub-receipts");
      const { error: uploadError } = await storage.upload(storagePath, file, {
        contentType: file.type,
        upsert: false,
      });
      if (uploadError) throw new Error(uploadError.message || t("Unable to upload photo"));
      try {
        const attachment = await attachPhoto({
          data: {
            receiptId: targetReceiptId,
            storagePath,
            fileName: file.name,
            mimeType: file.type as "image/jpeg",
            fileSize: file.size,
          },
        });
        uploaded.push({ ...attachment, signed_url: null });
      } catch (caught) {
        await storage.remove([storagePath]);
        throw caught;
      }
    }
    setAttachments((current) => [...current, ...uploaded]);
    setPhotos([]);
    return uploaded.length;
  };

  const save = async (confirmAfterSave: boolean) => {
    if (pending) return;
    const lineError = validateReceiptLines(lines);
    if (lineError) {
      setError(t(lineError));
      return;
    }
    if (!receiptDate || !locationId) {
      setError(t("Receipt date and location are required."));
      return;
    }
    if (confirmAfterSave && attachments.length + photos.length === 0) {
      setError(t("At least one receiving photo is required."));
      return;
    }

    setPending(confirmAfterSave ? "confirm" : "save");
    setError("");
    setNotice("");
    let targetReceiptId = receiptId;
    try {
      const header = {
        receiptDate,
        locationId,
        supplierId,
        supplierName,
        reference,
        comment,
      };
      if (targetReceiptId) {
        await updateDraft({ data: { ...header, receiptId: targetReceiptId } });
      } else {
        const created = await createDraft({ data: header });
        targetReceiptId = created.id;
        setReceiptId(created.id);
        window.history.replaceState(
          null,
          "",
          `/facolub/receiving/new?receiptId=${encodeURIComponent(created.id)}`,
        );
      }

      const selectedItemIds = new Set(lines.map((line) => line.stockItemId));
      for (const original of existing?.items ?? []) {
        if (!selectedItemIds.has(original.stock_item_id)) {
          await removeItem({ data: { receiptItemId: original.id } });
        }
      }
      for (const [index, line] of lines.entries()) {
        await addItem({
          data: {
            receiptId: targetReceiptId,
            stockItemId: line.stockItemId,
            quantity: line.quantity,
            position: index + 1,
          },
        });
      }
      await uploadPhotos(targetReceiptId);

      try {
        localStorage.removeItem(storageKey);
        localStorage.removeItem(receivingDraftStorageKey);
      } catch {
        // Saving succeeded even if local cleanup is blocked.
      }

      if (confirmAfterSave) {
        const result = await confirmReceipt({ data: { receiptId: targetReceiptId } });
        try {
          sessionStorage.setItem(confirmationKey(targetReceiptId), JSON.stringify(result));
        } catch {
          // Detail still reloads from the authoritative receipt record.
        }
      }
      window.location.assign(`/facolub/receiving/${targetReceiptId}`);
    } catch (caught) {
      if (targetReceiptId) {
        try {
          localStorage.setItem(
            storageKey,
            JSON.stringify({ ...localDraft, receiptId: targetReceiptId }),
          );
        } catch {
          // React state still retains all entered values and selected File objects.
        }
      }
      setError(
        caught instanceof Error
          ? caught.message
          : t("The receiving operation failed. Your form is still available."),
      );
      setPending(null);
    }
  };

  return (
    <>
      <PageHeader
        eyebrow="Receiving"
        title={existing ? "Edit receipt draft" : "New receiving"}
        description="Select goods, quantity, supplier, and photo evidence before confirmation."
      />

      <div className="mb-5 flex items-start gap-3 border border-info/30 bg-info-soft p-4 text-sm">
        <WifiOff className="mt-0.5 size-5 shrink-0 text-info" />
        <div>
          <p className="font-bold">{t("Resilient draft")}</p>
          <p>{t("Entered fields stay on this device during temporary connection problems.")}</p>
          <p className="mt-1 text-xs text-muted-foreground">
            {t("For security, photos must be selected again after a full page reload.")}
          </p>
        </div>
      </div>

      {notice && <p className="mb-4 border border-info/30 bg-info-soft p-3 text-sm">{t(notice)}</p>}

      <div className="space-y-5 pb-28 lg:pb-0">
        <Step number="1" icon={PackagePlus} title={t("Select item")}>
          <div className="space-y-3">
            {lines.map((line, index) => {
              const selected = itemById.get(line.stockItemId);
              return (
                <div key={line.key} className="border bg-background p-4">
                  <div className="mb-3 flex items-center justify-between gap-3">
                    <p className="text-sm font-black">
                      {t("Item")} {index + 1}
                    </p>
                    <Button
                      type="button"
                      variant="ghost"
                      size="icon"
                      disabled={lines.length === 1}
                      onClick={() => removeLine(line.key)}
                      aria-label={t("Remove item")}
                    >
                      <Trash2 />
                    </Button>
                  </div>
                  <div className="grid gap-4 sm:grid-cols-[1fr_180px]">
                    <div className="space-y-2">
                      <Label>{t("Stock item")}</Label>
                      <select
                        required
                        className="h-11 w-full rounded-md border bg-card px-3"
                        value={line.stockItemId}
                        onChange={(event) =>
                          updateLine(line.key, "stockItemId", event.target.value)
                        }
                      >
                        <option value="">{t("Select an active item")}</option>
                        {locationItems.map((item) => (
                          <option
                            key={item.id}
                            value={item.id}
                            disabled={lines.some(
                              (candidate) =>
                                candidate.key !== line.key && candidate.stockItemId === item.id,
                            )}
                          >
                            {item.name} · {t(stockUnitLabels[item.unit])}
                          </option>
                        ))}
                      </select>
                    </div>
                    <div className="space-y-2">
                      <Label>{t("Quantity")}</Label>
                      <div className="relative">
                        <Input
                          className="h-11 pr-20 text-lg font-black"
                          inputMode="decimal"
                          type="number"
                          min="0.001"
                          step="0.001"
                          required
                          value={line.quantity}
                          onChange={(event) => updateLine(line.key, "quantity", event.target.value)}
                        />
                        {selected && (
                          <span className="absolute right-3 top-3 text-xs font-bold text-muted-foreground">
                            {t(stockUnitLabels[selected.unit])}
                          </span>
                        )}
                      </div>
                    </div>
                  </div>
                  {selected && (
                    <dl className="mt-3 grid grid-cols-2 gap-3 border-t pt-3 text-xs">
                      <div>
                        <dt className="text-muted-foreground">{t("Physical now")}</dt>
                        <dd className="mt-1 font-black">
                          {formatStockQuantity(selected.physical_quantity, locale)}
                        </dd>
                      </div>
                      <div>
                        <dt className="text-muted-foreground">{t("Available now")}</dt>
                        <dd className="mt-1 font-black">
                          {formatStockQuantity(selected.available_quantity, locale)}
                        </dd>
                      </div>
                    </dl>
                  )}
                </div>
              );
            })}
            <Button type="button" variant="outline" onClick={addLine}>
              <Plus /> {t("Add another item")}
            </Button>
          </div>
        </Step>

        <Step number="2" icon={MapPin} title={t("Date and location")}>
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-2">
              <Label>{t("Receipt date")}</Label>
              <Input
                className="h-11"
                type="date"
                required
                value={receiptDate}
                onChange={(event) => setReceiptDate(event.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label>{t("Location")}</Label>
              <select
                className="h-11 w-full rounded-md border bg-background px-3"
                required
                value={locationId}
                onChange={(event) => setLocationId(event.target.value)}
              >
                {data.locations.map((location) => (
                  <option key={location.id} value={location.id}>
                    {location.name}
                  </option>
                ))}
              </select>
            </div>
          </div>
        </Step>

        <Step number="3" icon={Truck} title={t("Supplier")}>
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-2">
              <Label>{t("Known supplier")}</Label>
              <select
                className="h-11 w-full rounded-md border bg-background px-3"
                value={supplierId}
                onChange={(event) => {
                  setSupplierId(event.target.value);
                  if (event.target.value) setSupplierName("");
                }}
              >
                <option value="">{t("No supplier selected")}</option>
                {data.suppliers.map((supplier) => (
                  <option key={supplier.id} value={supplier.id}>
                    {supplier.name}
                  </option>
                ))}
              </select>
            </div>
            <div className="space-y-2">
              <Label>{t("Or supplier name")}</Label>
              <Input
                className="h-11"
                maxLength={200}
                disabled={Boolean(supplierId)}
                value={supplierName}
                onChange={(event) => setSupplierName(event.target.value)}
                placeholder={t("Optional supplier name")}
              />
            </div>
          </div>
        </Step>

        <Step number="4" icon={Camera} title={t("Photo evidence")}>
          <p className="mb-4 text-sm text-muted-foreground">
            {t("At least one photo is required to confirm. Up to 8 MiB per image.")}
          </p>
          <div className="grid grid-cols-2 gap-3 sm:flex sm:flex-wrap">
            <Button asChild variant="outline" size="lg">
              <label className="cursor-pointer">
                <Camera /> {t("Take photo")}
                <input
                  className="sr-only"
                  type="file"
                  accept="image/*"
                  capture="environment"
                  onChange={addPhotos}
                />
              </label>
            </Button>
            <Button asChild variant="outline" size="lg">
              <label className="cursor-pointer">
                <FileImage /> {t("Choose photos")}
                <input
                  className="sr-only"
                  type="file"
                  accept="image/*"
                  multiple
                  onChange={addPhotos}
                />
              </label>
            </Button>
          </div>

          {(attachments.length > 0 || photos.length > 0) && (
            <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
              {attachments.map((attachment) => (
                <div key={attachment.id} className="relative border bg-muted">
                  {attachment.signed_url ? (
                    <img
                      src={attachment.signed_url}
                      alt={attachment.file_name ?? t("Receipt photo")}
                      className="aspect-square w-full object-cover"
                    />
                  ) : (
                    <div className="grid aspect-square place-items-center">
                      <ShieldCheck className="size-8 text-success" />
                    </div>
                  )}
                  <p className="truncate p-2 text-xs font-semibold">
                    {attachment.file_name ?? t("Private photo")}
                  </p>
                  <button
                    type="button"
                    disabled={Boolean(pending)}
                    onClick={() => void removeExistingPhoto(attachment.id)}
                    className="absolute right-1 top-1 grid size-8 place-items-center rounded-full bg-background/90 text-danger shadow"
                    aria-label={t("Remove photo")}
                  >
                    <Trash2 className="size-4" />
                  </button>
                </div>
              ))}
              {photos.map((file, index) => (
                <PhotoPreview
                  key={`${file.name}:${file.lastModified}:${index}`}
                  file={file}
                  onRemove={() => setPhotos((current) => current.filter((_, i) => i !== index))}
                />
              ))}
            </div>
          )}
        </Step>

        <Step number="5" icon={FileImage} title={t("Reference and comment")}>
          <div className="space-y-4">
            <div className="space-y-2">
              <Label>{t("Supplier document / reference")}</Label>
              <Input
                className="h-11"
                maxLength={200}
                value={reference}
                onChange={(event) => setReference(event.target.value)}
                placeholder={t("Delivery note, invoice, or supplier reference")}
              />
            </div>
            <div className="space-y-2">
              <Label>{t("Comment")}</Label>
              <Textarea
                className="min-h-24"
                maxLength={2000}
                value={comment}
                onChange={(event) => setComment(event.target.value)}
                placeholder={t("Optional receiving notes")}
              />
            </div>
          </div>
        </Step>

        <Step number="6" icon={CheckCircle2} title={t("Review")}>
          <div className="grid gap-3 text-sm sm:grid-cols-2">
            <Review
              label={t("Items")}
              value={String(lines.filter((line) => line.stockItemId).length)}
            />
            <Review label={t("Photos")} value={String(attachments.length + photos.length)} />
            <Review
              label={t("Supplier")}
              value={
                data.suppliers.find((supplier) => supplier.id === supplierId)?.name ||
                supplierName ||
                t("No supplier")
              }
            />
            <Review
              label={t("Location")}
              value={data.locations.find((location) => location.id === locationId)?.name ?? "—"}
            />
          </div>
          <p className="mt-4 flex items-start gap-2 border border-warning/30 bg-warning-soft p-3 text-sm">
            <ShieldCheck className="mt-0.5 size-4 shrink-0" />
            {t("Confirmation is atomic and cannot be edited or deleted afterward.")}
          </p>
        </Step>

        {error && (
          <p
            role="alert"
            className="border border-danger/30 bg-danger-soft p-4 text-sm font-semibold text-danger"
          >
            {t(error)}
          </p>
        )}

        <div className="fixed inset-x-0 bottom-16 z-30 border-t bg-background/95 p-3 backdrop-blur lg:static lg:border-0 lg:bg-transparent lg:p-0">
          <div className="mx-auto grid max-w-3xl grid-cols-2 gap-3 lg:flex lg:justify-end">
            <Button
              type="button"
              variant="outline"
              size="lg"
              disabled={Boolean(pending)}
              onClick={() => void save(false)}
            >
              {pending === "save" ? <LoaderCircle className="animate-spin" /> : <Save />}
              {pending === "save" ? t("Saving…") : t("Save draft")}
            </Button>
            <Button
              type="button"
              size="lg"
              disabled={Boolean(pending)}
              onClick={() => void save(true)}
            >
              {pending === "confirm" ? <LoaderCircle className="animate-spin" /> : <CheckCircle2 />}
              {pending === "confirm" ? t("Confirming…") : t("Confirm receiving")}
            </Button>
          </div>
        </div>
      </div>
    </>
  );
}

function Step({
  number,
  icon: Icon,
  title,
  children,
}: {
  number: string;
  icon: typeof Camera;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <section className="border bg-card p-4 shadow-sm sm:p-5">
      <div className="mb-4 flex items-center gap-3 border-b pb-3">
        <span className="grid size-8 place-items-center rounded-full bg-primary text-sm font-black text-primary-foreground">
          {number}
        </span>
        <Icon className="size-5 text-primary" />
        <h2 className="font-black uppercase tracking-wide">{title}</h2>
      </div>
      {children}
    </section>
  );
}

function Review({ label, value }: { label: string; value: string }) {
  return (
    <div className="border bg-background p-3">
      <p className="text-xs font-bold uppercase text-muted-foreground">{label}</p>
      <p className="mt-1 font-black">{value}</p>
    </div>
  );
}

function PhotoPreview({ file, onRemove }: { file: File; onRemove: () => void }) {
  const { t } = useLanguage();
  const [url, setUrl] = useState("");
  useEffect(() => {
    const nextUrl = URL.createObjectURL(file);
    setUrl(nextUrl);
    return () => URL.revokeObjectURL(nextUrl);
  }, [file]);
  return (
    <div className="relative border bg-muted">
      {url && <img src={url} alt={file.name} className="aspect-square w-full object-cover" />}
      <p className="truncate p-2 text-xs font-semibold">{file.name}</p>
      <button
        type="button"
        onClick={onRemove}
        className="absolute right-1 top-1 grid size-8 place-items-center rounded-full bg-background/90 text-danger shadow"
        aria-label={t("Remove photo")}
      >
        <Trash2 className="size-4" />
      </button>
    </div>
  );
}
