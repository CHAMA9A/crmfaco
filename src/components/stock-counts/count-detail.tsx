import { Link, useRouter } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import {
  AlertTriangle,
  Camera,
  CheckCircle2,
  ClipboardCheck,
  FileText,
  LoaderCircle,
  MapPin,
  Save,
  ShieldCheck,
  UserRound,
  XCircle,
} from "lucide-react";
import { useMemo, useState, type ChangeEvent } from "react";

import { PageHeader } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { useAuthenticatedUser } from "@/lib/auth/context";
import { useLanguage } from "@/lib/i18n/use-language";
import {
  approveStockCountFn,
  attachStockCountEvidenceFn,
  cancelStockCountFn,
  rejectStockCountFn,
  submitStockCountFn,
  updateCountedQuantityFn,
} from "@/lib/stock-counts/functions";
import {
  buildStockEvidencePath,
  signedDifference,
  type StockCountDetail,
  validateStockEvidence,
} from "@/lib/stock-counts/types";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { formatStockQuantity, stockUnitLabels } from "@/lib/stock/types";
import { CountStatus } from "./count-list";

type DraftValue = { quantity: string; comment: string };

function token() {
  return typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random()}`;
}

export function StockCountDetailView({ data }: { data: StockCountDetail }) {
  const router = useRouter();
  const user = useAuthenticatedUser();
  const { language, t } = useLanguage();
  const locale = language === "fr" ? "fr-FR" : "en-GB";
  const updateQuantity = useServerFn(updateCountedQuantityFn);
  const submitCount = useServerFn(submitStockCountFn);
  const approveCount = useServerFn(approveStockCountFn);
  const rejectCount = useServerFn(rejectStockCountFn);
  const cancelCount = useServerFn(cancelStockCountFn);
  const attachEvidence = useServerFn(attachStockCountEvidenceFn);
  const [values, setValues] = useState<Record<string, DraftValue>>(() =>
    Object.fromEntries(
      data.items.map((line) => [
        line.item.id,
        {
          quantity: line.item.counted_quantity === null ? "" : String(line.item.counted_quantity),
          comment: line.item.comment ?? "",
        },
      ]),
    ),
  );
  const [pending, setPending] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [rejectReason, setRejectReason] = useState("");
  const isDraft = data.count.status === "draft";
  const canReview = user.profile.role === "admin" || user.profile.role === "management";
  const complete = data.items.every(
    (line) => values[line.item.id]?.quantity !== "" && Number(values[line.item.id]?.quantity) >= 0,
  );
  const differenceCount = useMemo(
    () =>
      data.items.filter(
        (line) =>
          line.item.difference_quantity !== null && Number(line.item.difference_quantity) !== 0,
      ).length,
    [data.items],
  );

  const refresh = async () => {
    await router.invalidate();
    setPending(null);
  };

  const save = async () => {
    if (pending || !complete) return;
    setPending("save");
    setError("");
    setNotice("");
    try {
      for (const line of data.items) {
        const value = values[line.item.id] ?? { quantity: "", comment: "" };
        await updateQuantity({
          data: { countItemId: line.item.id, quantity: value.quantity, comment: value.comment },
        });
      }
      setNotice(t("Counted quantities saved."));
      await refresh();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t("Unable to save count"));
      setPending(null);
    }
  };

  const submit = async () => {
    if (!complete || pending) return;
    setPending("submit");
    setError("");
    try {
      for (const line of data.items) {
        const value = values[line.item.id] ?? { quantity: "", comment: "" };
        await updateQuantity({
          data: { countItemId: line.item.id, quantity: value.quantity, comment: value.comment },
        });
      }
      await submitCount({ data: { countId: data.count.id } });
      await refresh();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t("Unable to submit count"));
      setPending(null);
    }
  };

  const approve = async () => {
    if (pending || !window.confirm(t("Approve this count and post all differences to stock?")))
      return;
    setPending("approve");
    setError("");
    try {
      await approveCount({ data: { countId: data.count.id } });
      await refresh();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t("Unable to approve count"));
      setPending(null);
    }
  };

  const reject = async () => {
    if (pending || !rejectReason.trim()) return;
    setPending("reject");
    setError("");
    try {
      await rejectCount({ data: { countId: data.count.id, reason: rejectReason } });
      await refresh();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t("Unable to reject count"));
      setPending(null);
    }
  };

  const cancel = async () => {
    if (pending || !window.confirm(t("Cancel this draft count?"))) return;
    setPending("cancel");
    setError("");
    try {
      await cancelCount({ data: { countId: data.count.id } });
      await refresh();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t("Unable to cancel count"));
      setPending(null);
    }
  };

  const upload = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file || pending) return;
    const invalid = validateStockEvidence(file);
    if (invalid) return setError(t(invalid));
    setPending("upload");
    setError("");
    const storagePath = buildStockEvidencePath(
      user.profile.id,
      "counts",
      data.count.id,
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
            countId: data.count.id,
            countItemId: null,
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
      await refresh();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t("Unable to upload evidence"));
      setPending(null);
    }
  };

  return (
    <>
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <PageHeader
          eyebrow="Physical counts"
          title={data.count.count_number ?? t("Draft stock count")}
          description="Physical snapshot, entered quantities, differences, evidence and approval trail."
        />
        <div className="flex items-center gap-2">
          <CountStatus status={data.count.status} />
          <Button asChild variant="outline">
            <Link to="/facolub/stock/counts">{t("All counts")}</Link>
          </Button>
        </div>
      </div>

      {error && (
        <div className="mb-4 flex gap-3 border border-danger/30 bg-danger-soft p-4 text-sm font-semibold text-danger">
          <AlertTriangle className="size-5 shrink-0" />
          <span>{error}</span>
        </div>
      )}
      {notice && (
        <div className="mb-4 border border-success/30 bg-success-soft p-4 text-sm font-semibold text-success">
          {notice}
        </div>
      )}

      <div className="grid gap-5 xl:grid-cols-[minmax(0,1.5fr)_340px]">
        <div className="space-y-5">
          <section className="border bg-card shadow-sm">
            <div className="flex items-center justify-between border-b p-4">
              <h2 className="flex items-center gap-2 font-black">
                <ClipboardCheck className="size-5 text-primary" /> {t("Count lines")}
              </h2>
              <span className="text-sm font-bold text-muted-foreground">
                {data.items.length} {t("items")}
              </span>
            </div>
            <div className="divide-y">
              {data.items.map((line) => {
                const draft = values[line.item.id] ?? { quantity: "", comment: "" };
                const entered = draft?.quantity === "" ? null : Number(draft.quantity);
                const difference =
                  entered === null ? null : entered - Number(line.item.expected_physical_quantity);
                return (
                  <article key={line.item.id} className="p-4">
                    <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_140px_140px_140px] lg:items-start">
                      <div>
                        <p className="font-black">{line.stock_item_name}</p>
                        <p className="mt-1 text-xs text-muted-foreground">
                          {t(stockUnitLabels[line.unit])} · {t("Snapshot")}{" "}
                          {new Date(line.item.snapshot_at).toLocaleString(locale)}
                        </p>
                      </div>
                      <Metric
                        label={t("Expected physical")}
                        value={formatStockQuantity(
                          Number(line.item.expected_physical_quantity),
                          locale,
                        )}
                      />
                      {isDraft ? (
                        <label className="text-xs font-bold text-muted-foreground">
                          {t("Counted physical")}
                          <Input
                            className="mt-1 text-right text-base font-black"
                            type="number"
                            min="0"
                            step="0.001"
                            value={draft.quantity}
                            onChange={(e) =>
                              setValues((current) => ({
                                ...current,
                                [line.item.id]: {
                                  ...(current[line.item.id] ?? { quantity: "", comment: "" }),
                                  quantity: e.target.value,
                                },
                              }))
                            }
                          />
                        </label>
                      ) : (
                        <Metric
                          label={t("Counted physical")}
                          value={formatStockQuantity(
                            Number(line.item.counted_quantity ?? 0),
                            locale,
                          )}
                        />
                      )}
                      <Metric
                        label={t("Difference")}
                        value={
                          difference === null
                            ? "—"
                            : signedDifference(Number(difference.toFixed(3)))
                        }
                        tone={
                          difference === null || difference === 0
                            ? "normal"
                            : difference > 0
                              ? "success"
                              : "danger"
                        }
                      />
                    </div>
                    {isDraft ? (
                      <Textarea
                        className="mt-3"
                        rows={2}
                        value={draft.comment}
                        onChange={(e) =>
                          setValues((current) => ({
                            ...current,
                            [line.item.id]: {
                              ...(current[line.item.id] ?? { quantity: "", comment: "" }),
                              comment: e.target.value,
                            },
                          }))
                        }
                        placeholder={t("Line note (optional)")}
                      />
                    ) : (
                      line.item.comment && (
                        <p className="mt-3 border-l-2 border-primary pl-3 text-sm text-muted-foreground">
                          {line.item.comment}
                        </p>
                      )
                    )}
                    {!isDraft && (
                      <div className="mt-3 grid grid-cols-3 gap-2 bg-muted/40 p-3 text-xs">
                        <Metric
                          label={t("Physical now")}
                          value={formatStockQuantity(
                            Number(line.current_balance.physical_quantity),
                            locale,
                          )}
                        />
                        <Metric
                          label={t("Reserved")}
                          value={formatStockQuantity(
                            Number(line.current_balance.reserved_quantity),
                            locale,
                          )}
                        />
                        <Metric
                          label={t("Available")}
                          value={formatStockQuantity(
                            Number(line.current_balance.available_quantity),
                            locale,
                          )}
                          tone={line.current_balance.reservation_shortage ? "danger" : "normal"}
                        />
                      </div>
                    )}
                  </article>
                );
              })}
            </div>
          </section>

          <section className="border bg-card p-5 shadow-sm">
            <h2 className="flex items-center gap-2 font-black">
              <Camera className="size-5 text-primary" /> {t("Evidence")}
            </h2>
            {data.attachments.length ? (
              <div className="mt-4 grid gap-3 sm:grid-cols-3">
                {data.attachments.map((file) => (
                  <a
                    key={file.id}
                    href={file.signed_url ?? undefined}
                    target="_blank"
                    rel="noreferrer"
                    className="border bg-muted p-3 text-sm font-semibold hover:border-primary"
                  >
                    <FileText className="mb-2 size-5" />
                    <span className="break-all">{file.file_name}</span>
                  </a>
                ))}
              </div>
            ) : (
              <p className="mt-3 text-sm text-muted-foreground">
                {t("No evidence attached. Photos and PDFs are optional.")}
              </p>
            )}
            {isDraft && (
              <label className="mt-4 inline-flex">
                <span className="inline-flex h-9 cursor-pointer items-center gap-2 rounded-md border bg-background px-4 text-sm font-medium hover:bg-accent">
                  <Camera className="size-4" />
                  {pending === "upload" ? t("Uploading…") : t("Add photo or PDF")}
                </span>
                <input
                  className="sr-only"
                  type="file"
                  accept="image/jpeg,image/png,image/webp,application/pdf"
                  disabled={Boolean(pending)}
                  onChange={(e) => void upload(e)}
                />
              </label>
            )}
          </section>
        </div>

        <aside className="space-y-5">
          <section className="border bg-card p-5 shadow-sm">
            <h2 className="font-black">{t("Count details")}</h2>
            <dl className="mt-4 space-y-4 text-sm">
              <Detail icon={MapPin} label={t("Location")} value={data.location_name} />
              <Detail icon={UserRound} label={t("Created by")} value={data.created_by_name} />
              <Detail
                icon={FileText}
                label={t("Date")}
                value={new Date(`${data.count.count_date}T00:00:00`).toLocaleDateString(locale)}
              />
              {data.approved_by_name && (
                <Detail icon={ShieldCheck} label={t("Approved by")} value={data.approved_by_name} />
              )}
            </dl>
            {data.count.comment && (
              <p className="mt-4 border-t pt-4 text-sm whitespace-pre-wrap">{data.count.comment}</p>
            )}
            {data.count.rejection_reason && (
              <p className="mt-4 border border-danger/30 bg-danger-soft p-3 text-sm text-danger">
                <strong>{t("Rejection")}:</strong> {data.count.rejection_reason}
              </p>
            )}
          </section>

          {isDraft && (
            <section className="border border-info/30 bg-info-soft p-5">
              <h2 className="font-black">{t("Draft does not affect stock")}</h2>
              <p className="mt-2 text-sm">
                {t("Complete every physical quantity, then submit for approval.")}
              </p>
              <div className="mt-4 grid gap-2">
                <Button disabled={Boolean(pending) || !complete} onClick={() => void save()}>
                  {pending === "save" ? <LoaderCircle className="animate-spin" /> : <Save />}{" "}
                  {t("Save quantities")}
                </Button>
                <Button disabled={Boolean(pending) || !complete} onClick={() => void submit()}>
                  <CheckCircle2 />{" "}
                  {pending === "submit" ? t("Submitting…") : t("Submit for approval")}
                </Button>
                <Button variant="outline" disabled={Boolean(pending)} onClick={() => void cancel()}>
                  <XCircle /> {t("Cancel draft")}
                </Button>
              </div>
            </section>
          )}

          {data.count.status === "submitted" && canReview && (
            <section className="border border-warning/30 bg-warning-soft p-5">
              <h2 className="font-black">{t("Management review")}</h2>
              <p className="mt-2 text-sm">
                {differenceCount}{" "}
                {t(
                  "differences will create immutable movements. A stale snapshot is rejected automatically.",
                )}
              </p>
              <Button
                className="mt-4 w-full"
                disabled={Boolean(pending)}
                onClick={() => void approve()}
              >
                <ShieldCheck /> {pending === "approve" ? t("Approving…") : t("Approve and post")}
              </Button>
              <Textarea
                className="mt-3 bg-background"
                value={rejectReason}
                onChange={(e) => setRejectReason(e.target.value)}
                placeholder={t("Rejection reason")}
              />
              <Button
                className="mt-2 w-full"
                variant="outline"
                disabled={Boolean(pending) || !rejectReason.trim()}
                onClick={() => void reject()}
              >
                <XCircle /> {pending === "reject" ? t("Rejecting…") : t("Reject count")}
              </Button>
            </section>
          )}
        </aside>
      </div>
    </>
  );
}

function Metric({
  label,
  value,
  tone = "normal",
}: {
  label: string;
  value: string;
  tone?: "normal" | "success" | "danger";
}) {
  return (
    <dl>
      <dt className="text-[10px] font-bold uppercase text-muted-foreground">{label}</dt>
      <dd
        className={`mt-1 font-black tabular-nums ${tone === "success" ? "text-success" : tone === "danger" ? "text-danger" : ""}`}
      >
        {value}
      </dd>
    </dl>
  );
}

function Detail({
  icon: Icon,
  label,
  value,
}: {
  icon: typeof MapPin;
  label: string;
  value: string;
}) {
  return (
    <div className="flex gap-3">
      <Icon className="mt-0.5 size-4 shrink-0 text-primary" />
      <div>
        <dt className="text-xs font-bold uppercase text-muted-foreground">{label}</dt>
        <dd className="mt-0.5 font-semibold">{value}</dd>
      </div>
    </div>
  );
}
