import { Link, useRouter } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import {
  AlertTriangle,
  Camera,
  CheckCircle2,
  ClipboardCheck,
  FileWarning,
  LoaderCircle,
  Scale,
  RotateCcw,
  ShieldCheck,
  XCircle,
} from "lucide-react";
import { useMemo, useState, type ChangeEvent } from "react";

import { EmptyState, PageHeader } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { useAuthenticatedUser } from "@/lib/auth/context";
import { useLanguage } from "@/lib/i18n/use-language";
import {
  approveStockAdjustmentFn,
  attachStockAdjustmentEvidenceFn,
  rejectStockAdjustmentFn,
  reportStockDamageFn,
  reportStockLossFn,
  requestOtherStockAdjustmentFn,
  requestStockCorrectionFn,
} from "@/lib/stock-counts/functions";
import {
  buildStockEvidencePath,
  stockAdjustmentStatusLabels,
  stockAdjustmentTypeLabels,
  validateStockEvidence,
  type StockAdjustmentListRow,
  type StockCountWorkspaceData,
} from "@/lib/stock-counts/types";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { formatStockQuantity, stockUnitLabels } from "@/lib/stock/types";
import type { StockAdjustmentType } from "@/types/database";

type RequestType = Exclude<StockAdjustmentType, "count_difference">;

function token() {
  return typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random()}`;
}

export function AdjustmentCenter({
  data,
}: {
  data: Pick<StockCountWorkspaceData, "adjustments" | "locations" | "items">;
}) {
  const router = useRouter();
  const user = useAuthenticatedUser();
  const { language, t } = useLanguage();
  const locale = language === "fr" ? "fr-FR" : "en-GB";
  const loss = useServerFn(reportStockLossFn);
  const damage = useServerFn(reportStockDamageFn);
  const other = useServerFn(requestOtherStockAdjustmentFn);
  const correction = useServerFn(requestStockCorrectionFn);
  const approve = useServerFn(approveStockAdjustmentFn);
  const reject = useServerFn(rejectStockAdjustmentFn);
  const attachEvidence = useServerFn(attachStockAdjustmentEvidenceFn);
  const [type, setType] = useState<RequestType>("loss");
  const [locationId, setLocationId] = useState(data.locations[0]?.id ?? "");
  const [stockItemId, setStockItemId] = useState("");
  const [movementId, setMovementId] = useState("");
  const [quantity, setQuantity] = useState("");
  const [reason, setReason] = useState("");
  const [status, setStatus] = useState("all");
  const [search, setSearch] = useState("");
  const [pending, setPending] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const canReview = user.profile.role === "admin" || user.profile.role === "management";
  const locationItems = useMemo(
    () => data.items.filter((item) => item.location_id === locationId),
    [data.items, locationId],
  );
  const filtered = useMemo(() => {
    const term = search.trim().toLowerCase();
    return data.adjustments.filter(
      (row) =>
        (status === "all" || row.status === status) &&
        (!term ||
          `${row.stock_item_name} ${row.requested_by_name} ${row.reason}`
            .toLowerCase()
            .includes(term)),
    );
  }, [data.adjustments, search, status]);

  const create = async () => {
    if (pending) return;
    const parsed = Number(quantity);
    if (!reason.trim() || !Number.isFinite(parsed) || parsed === 0)
      return setError(t("Quantity and reason are required."));
    if (type !== "correction" && (!stockItemId || !locationId))
      return setError(t("Stock item and location are required."));
    if (type === "correction" && !movementId)
      return setError(t("Original movement ID is required."));
    setPending("create");
    setError("");
    setNotice("");
    try {
      if (type === "loss")
        await loss({ data: { stockItemId, locationId, quantity: Math.abs(parsed), reason } });
      else if (type === "damage")
        await damage({ data: { stockItemId, locationId, quantity: Math.abs(parsed), reason } });
      else if (type === "correction")
        await correction({ data: { movementId, quantity: Math.abs(parsed), reason } });
      else await other({ data: { stockItemId, locationId, quantity: parsed, reason } });
      setQuantity("");
      setReason("");
      setMovementId("");
      setNotice(t("Adjustment request created for Management approval."));
      await router.invalidate();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t("Unable to create adjustment request"));
    } finally {
      setPending(null);
    }
  };

  const review = async (row: StockAdjustmentListRow, action: "approve" | "reject") => {
    if (pending) return;
    let rejection = "";
    if (
      action === "approve" &&
      !window.confirm(t("Approve and post this adjustment to the immutable stock ledger?"))
    )
      return;
    if (action === "reject") {
      rejection = window.prompt(t("Rejection reason"))?.trim() ?? "";
      if (!rejection) return;
    }
    setPending(`${action}:${row.id}`);
    setError("");
    setNotice("");
    try {
      const result =
        action === "approve"
          ? await approve({ data: { adjustmentId: row.id } })
          : await reject({ data: { adjustmentId: row.id, reason: rejection } });
      const payload = result as { reservation_shortage?: boolean } | null;
      setNotice(
        payload?.reservation_shortage
          ? t("Adjustment posted. Warning: reserved stock now exceeds physical stock.")
          : t(action === "approve" ? "Adjustment posted." : "Adjustment rejected."),
      );
      await router.invalidate();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t("Adjustment review failed"));
    } finally {
      setPending(null);
    }
  };

  const upload = async (row: StockAdjustmentListRow, event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file || pending) return;
    const invalid = validateStockEvidence(file);
    if (invalid) return setError(t(invalid));
    setPending(`upload:${row.id}`);
    setError("");
    const storagePath = buildStockEvidencePath(
      user.profile.id,
      "adjustments",
      row.id,
      file.name,
      token(),
    );
    const storage = getSupabaseBrowserClient().storage.from("facolub-stock-evidence");
    try {
      const uploaded = await storage.upload(storagePath, file, {
        contentType: file.type,
        upsert: false,
      });
      if (uploaded.error) throw uploaded.error;
      try {
        await attachEvidence({
          data: {
            adjustmentId: row.id,
            storagePath,
            fileName: file.name,
            mimeType: file.type as "image/jpeg",
            fileSize: file.size,
          },
        });
      } catch (caught) {
        await storage.remove([storagePath]);
        throw caught;
      }
      setNotice(t("Evidence attached."));
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t("Unable to upload evidence"));
    } finally {
      setPending(null);
    }
  };

  return (
    <>
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <PageHeader
          eyebrow="Stock"
          title="Stock adjustments"
          description="Report losses, damage and corrections. Every request requires approval before an immutable stock movement is posted."
        />
        <Button asChild variant="outline">
          <Link to="/facolub/stock/counts">
            <ClipboardCheck /> {t("Physical counts")}
          </Link>
        </Button>
      </div>
      {error && (
        <div className="mb-4 flex gap-3 border border-danger/30 bg-danger-soft p-4 text-sm font-semibold text-danger">
          <AlertTriangle className="size-5" /> {error}
        </div>
      )}
      {notice && (
        <div className="mb-4 border border-success/30 bg-success-soft p-4 text-sm font-semibold text-success">
          {notice}
        </div>
      )}

      <div className="grid gap-5 xl:grid-cols-[380px_minmax(0,1fr)]">
        <section className="h-fit border bg-card p-5 shadow-sm">
          <h2 className="flex items-center gap-2 font-black">
            <Scale className="size-5 text-primary" /> {t("New request")}
          </h2>
          <div className="mt-4 space-y-4">
            <div className="space-y-2">
              <Label>{t("Type")}</Label>
              <select
                className="h-10 w-full rounded-md border bg-background px-3"
                value={type}
                onChange={(e) => setType(e.target.value as RequestType)}
              >
                <option value="loss">{t("Loss")}</option>
                <option value="damage">{t("Damage")}</option>
                <option value="other">{t("Other signed adjustment")}</option>
                <option value="correction">{t("Reverse a movement")}</option>
              </select>
            </div>
            {type === "correction" ? (
              <div className="space-y-2">
                <Label>{t("Original movement ID")}</Label>
                <Input
                  value={movementId}
                  onChange={(e) => setMovementId(e.target.value)}
                  placeholder="UUID"
                />
              </div>
            ) : (
              <>
                <div className="space-y-2">
                  <Label>{t("Location")}</Label>
                  <select
                    className="h-10 w-full rounded-md border bg-background px-3"
                    value={locationId}
                    onChange={(e) => {
                      setLocationId(e.target.value);
                      setStockItemId("");
                    }}
                  >
                    <option value="">{t("Select location")}</option>
                    {data.locations.map((location) => (
                      <option key={location.id} value={location.id}>
                        {location.name}
                      </option>
                    ))}
                  </select>
                </div>
                <div className="space-y-2">
                  <Label>{t("Stock item")}</Label>
                  <select
                    className="h-10 w-full rounded-md border bg-background px-3"
                    value={stockItemId}
                    onChange={(e) => setStockItemId(e.target.value)}
                  >
                    <option value="">{t("Select item")}</option>
                    {locationItems.map((item) => (
                      <option key={item.id} value={item.id}>
                        {item.name} · {formatStockQuantity(item.physical_quantity, locale)}{" "}
                        {t(stockUnitLabels[item.unit])}
                      </option>
                    ))}
                  </select>
                </div>
              </>
            )}
            <div className="space-y-2">
              <Label>{type === "other" ? t("Signed quantity (+ / −)") : t("Quantity")}</Label>
              <Input
                type="number"
                step="0.001"
                value={quantity}
                onChange={(e) => setQuantity(e.target.value)}
                placeholder={type === "other" ? "+5 or -5" : "0"}
              />
            </div>
            <div className="space-y-2">
              <Label>{t("Reason")}</Label>
              <Textarea
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                maxLength={2000}
                placeholder={t("Describe what happened and why stock must change")}
              />
            </div>
            <Button className="w-full" disabled={Boolean(pending)} onClick={() => void create()}>
              {pending === "create" ? <LoaderCircle className="animate-spin" /> : <FileWarning />}{" "}
              {t("Submit request")}
            </Button>
          </div>
        </section>

        <section>
          <div className="mb-4 grid gap-3 border bg-card p-4 sm:grid-cols-[minmax(0,1fr)_190px]">
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder={t("Search item, requester or reason")}
            />
            <select
              className="h-9 rounded-md border bg-background px-3 text-sm"
              value={status}
              onChange={(e) => setStatus(e.target.value)}
            >
              <option value="all">{t("All statuses")}</option>
              <option value="pending">{t("Pending Approval")}</option>
              <option value="posted">{t("Posted")}</option>
              <option value="rejected">{t("Rejected")}</option>
            </select>
          </div>
          {filtered.length ? (
            <div className="space-y-3">
              {filtered.map((row) => (
                <article key={row.id} className="border bg-card p-4 shadow-sm">
                  <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                    <div>
                      <p className="text-xs font-black uppercase text-primary">
                        {t(stockAdjustmentTypeLabels[row.adjustment_type])}
                      </p>
                      <h3 className="mt-1 font-black">{row.stock_item_name}</h3>
                      <p className="mt-1 text-sm text-muted-foreground">
                        {row.location_name} · {row.requested_by_name} ·{" "}
                        {new Date(row.created_at).toLocaleString(locale)}
                      </p>
                    </div>
                    <div className="text-right">
                      <p
                        className={`text-xl font-black tabular-nums ${Number(row.difference_quantity) > 0 ? "text-success" : "text-danger"}`}
                      >
                        {Number(row.difference_quantity) > 0 ? "+" : ""}
                        {formatStockQuantity(Number(row.difference_quantity), locale)}
                      </p>
                      <span className="text-xs font-bold uppercase text-muted-foreground">
                        {t(stockAdjustmentStatusLabels[row.status])}
                      </span>
                    </div>
                  </div>
                  <p className="mt-3 border-l-2 border-primary pl-3 text-sm">{row.reason}</p>
                  {row.original_movement_id && (
                    <p className="mt-2 text-xs text-muted-foreground">
                      {t("Original movement")}: {row.original_movement_id}
                    </p>
                  )}
                  {row.status === "pending" && (
                    <div className="mt-4 flex flex-wrap gap-2 border-t pt-3">
                      <label className="inline-flex">
                        <span className="inline-flex h-9 cursor-pointer items-center gap-2 rounded-md border px-3 text-sm font-medium hover:bg-accent">
                          <Camera className="size-4" /> {t("Evidence")}
                        </span>
                        <input
                          className="sr-only"
                          type="file"
                          accept="image/jpeg,image/png,image/webp,application/pdf"
                          disabled={Boolean(pending)}
                          onChange={(e) => void upload(row, e)}
                        />
                      </label>
                      {canReview && (
                        <>
                          <Button
                            size="sm"
                            disabled={Boolean(pending)}
                            onClick={() => void review(row, "approve")}
                          >
                            <ShieldCheck />{" "}
                            {pending === `approve:${row.id}` ? t("Posting…") : t("Approve")}
                          </Button>
                          <Button
                            size="sm"
                            variant="outline"
                            disabled={Boolean(pending)}
                            onClick={() => void review(row, "reject")}
                          >
                            <XCircle /> {t("Reject")}
                          </Button>
                        </>
                      )}
                    </div>
                  )}
                  {row.status === "posted" && (
                    <p className="mt-3 flex items-center gap-2 text-sm font-bold text-success">
                      <CheckCircle2 className="size-4" /> {t("Posted to immutable ledger")}
                    </p>
                  )}
                </article>
              ))}
            </div>
          ) : (
            <EmptyState
              title="No adjustments"
              description="No adjustment request matches these filters."
              icon={RotateCcw}
            />
          )}
        </section>
      </div>
    </>
  );
}
