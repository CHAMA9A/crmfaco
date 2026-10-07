import { Link, useRouter } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import {
  ArrowDownToLine,
  Camera,
  CheckCircle2,
  FileText,
  MapPin,
  PackageCheck,
  Pencil,
  ShieldCheck,
  UserRound,
  XCircle,
} from "lucide-react";
import { useEffect, useState } from "react";

import { PageHeader } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { useLanguage } from "@/lib/i18n/use-language";
import { cancelReceiptFn, confirmReceiptFn } from "@/lib/receiving/functions";
import type { ReceiptConfirmation, ReceiptDetail } from "@/lib/receiving/types";
import { formatStockQuantity, stockUnitLabels } from "@/lib/stock/types";
import { ReceiptStatusBadge } from "./receipt-status";

function confirmationKey(receiptId: string) {
  return `facolub-receipt-confirmation:${receiptId}`;
}

export function ReceiptDetailView({ data }: { data: ReceiptDetail }) {
  const router = useRouter();
  const confirmReceipt = useServerFn(confirmReceiptFn);
  const cancelReceipt = useServerFn(cancelReceiptFn);
  const { language, t } = useLanguage();
  const locale = language === "fr" ? "fr-FR" : "en-GB";
  const [pending, setPending] = useState<"confirm" | "cancel" | null>(null);
  const [error, setError] = useState("");
  const [confirmation, setConfirmation] = useState<ReceiptConfirmation | null>(null);

  useEffect(() => {
    try {
      const stored = sessionStorage.getItem(confirmationKey(data.receipt.id));
      if (stored) {
        setConfirmation(JSON.parse(stored) as ReceiptConfirmation);
        sessionStorage.removeItem(confirmationKey(data.receipt.id));
      }
    } catch {
      // A blocked sessionStorage should not prevent receipt review.
    }
  }, [data.receipt.id]);

  const confirm = async () => {
    if (pending) return;
    setPending("confirm");
    setError("");
    try {
      const result = await confirmReceipt({ data: { receiptId: data.receipt.id } });
      setConfirmation(result);
      await router.invalidate();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t("Unable to confirm receipt"));
    } finally {
      setPending(null);
    }
  };

  const cancel = async () => {
    if (pending || !window.confirm(t("Cancel this draft receipt?"))) return;
    setPending("cancel");
    setError("");
    try {
      await cancelReceipt({ data: { receiptId: data.receipt.id } });
      window.location.assign("/facolub/receiving");
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t("Unable to cancel receipt"));
      setPending(null);
    }
  };

  const isDraft = data.receipt.status === "draft" && !confirmation;
  const effectiveStatus = confirmation ? "confirmed" : data.receipt.status;

  return (
    <>
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <PageHeader
          eyebrow="Receiving"
          title={confirmation?.receipt_number ?? data.receipt.receipt_number ?? "Draft receipt"}
          description="Physical receiving record, evidence, and linked stock movements."
        />
        <div className="flex flex-wrap items-center gap-2">
          <ReceiptStatusBadge status={effectiveStatus} />
          {isDraft && (
            <Button asChild variant="outline">
              <Link to="/facolub/receiving/new" search={{ receiptId: data.receipt.id }}>
                <Pencil /> {t("Edit draft")}
              </Link>
            </Button>
          )}
        </div>
      </div>

      {confirmation && <ConfirmationSummary result={confirmation} />}

      <div className="grid gap-5 xl:grid-cols-[minmax(0,1.5fr)_minmax(300px,0.7fr)]">
        <div className="space-y-5">
          <section className="border bg-card p-5 shadow-sm">
            <h2 className="flex items-center gap-2 font-black">
              <PackageCheck className="size-5 text-primary" /> {t("Received items")}
            </h2>
            <div className="mt-4 space-y-3">
              {data.items.map((item) => (
                <div
                  key={item.id}
                  className="flex items-center justify-between gap-4 border bg-background p-4"
                >
                  <div>
                    <p className="font-bold">{item.stock_item_name}</p>
                    <p className="mt-1 text-xs text-muted-foreground">
                      {t(stockUnitLabels[item.unit])}
                    </p>
                  </div>
                  <p className="text-xl font-black tabular-nums">
                    {formatStockQuantity(item.quantity, locale)}
                  </p>
                </div>
              ))}
              {!data.items.length && (
                <p className="text-sm text-muted-foreground">{t("No items added yet.")}</p>
              )}
            </div>
          </section>

          <section className="border bg-card p-5 shadow-sm">
            <h2 className="flex items-center gap-2 font-black">
              <Camera className="size-5 text-primary" /> {t("Receiving photos")}
            </h2>
            {data.attachments.length ? (
              <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-3">
                {data.attachments.map((attachment) =>
                  attachment.signed_url ? (
                    <a
                      key={attachment.id}
                      href={attachment.signed_url}
                      target="_blank"
                      rel="noreferrer"
                      className="group overflow-hidden border bg-muted"
                    >
                      <img
                        src={attachment.signed_url}
                        alt={attachment.file_name ?? t("Receiving photo")}
                        className="aspect-square w-full object-cover transition-transform group-hover:scale-105"
                      />
                      <p className="truncate px-2 py-2 text-xs font-semibold">
                        {attachment.file_name ?? t("Photo")}
                      </p>
                    </a>
                  ) : (
                    <div key={attachment.id} className="border bg-muted p-4 text-sm">
                      <Camera className="mb-2 size-6 text-muted-foreground" />
                      <p className="break-all font-semibold">
                        {attachment.file_name ?? t("Private photo")}
                      </p>
                      <p className="mt-1 text-xs text-danger">{t("Preview unavailable")}</p>
                    </div>
                  ),
                )}
              </div>
            ) : (
              <p className="mt-4 text-sm font-semibold text-warning">
                {t("A photo is required before confirmation.")}
              </p>
            )}
          </section>

          {effectiveStatus === "confirmed" && (
            <section className="border bg-card p-5 shadow-sm">
              <h2 className="flex items-center gap-2 font-black">
                <ArrowDownToLine className="size-5 text-success" /> {t("Related stock movements")}
              </h2>
              <div className="mt-4 space-y-2">
                {data.movements.map((movement) => {
                  const item = data.items.find(
                    (candidate) => candidate.stock_item_id === movement.stock_item_id,
                  );
                  return (
                    <div
                      key={movement.id}
                      className="flex flex-col gap-2 border bg-background p-3 sm:flex-row sm:items-center sm:justify-between"
                    >
                      <div>
                        <p className="font-bold">{item?.stock_item_name ?? t("Stock item")}</p>
                        <p className="text-xs text-muted-foreground">
                          {movement.id.slice(0, 8)}… ·{" "}
                          {new Date(movement.created_at).toLocaleString(locale)}
                        </p>
                      </div>
                      <span className="font-black text-success">
                        +{formatStockQuantity(movement.quantity, locale)}
                      </span>
                    </div>
                  );
                })}
                {!data.movements.length && confirmation && (
                  <p className="text-sm text-muted-foreground">{t("Refresh to view movements.")}</p>
                )}
              </div>
            </section>
          )}
        </div>

        <aside className="space-y-5">
          <section className="border bg-card p-5 shadow-sm">
            <h2 className="font-black">{t("Receipt details")}</h2>
            <dl className="mt-4 space-y-4 text-sm">
              <DetailRow
                icon={FileText}
                label={t("Reference")}
                value={data.receipt.reference ?? "—"}
              />
              <DetailRow icon={MapPin} label={t("Location")} value={data.location_name} />
              <DetailRow
                icon={UserRound}
                label={t("Supplier")}
                value={data.receipt.supplier_name_snapshot ?? t("No supplier")}
              />
              <DetailRow icon={UserRound} label={t("Created by")} value={data.created_by_name} />
              {data.confirmed_by_name && (
                <DetailRow
                  icon={ShieldCheck}
                  label={t("Confirmed by")}
                  value={data.confirmed_by_name}
                />
              )}
            </dl>
            <div className="mt-4 border-t pt-4 text-sm">
              <p className="text-xs font-bold uppercase text-muted-foreground">{t("Comment")}</p>
              <p className="mt-1 whitespace-pre-wrap">{data.receipt.comment ?? "—"}</p>
            </div>
          </section>

          {isDraft && (
            <section className="border border-warning/30 bg-warning-soft p-5">
              <h2 className="font-black">{t("Draft does not affect stock")}</h2>
              <p className="mt-2 text-sm">
                {t("Stock changes only after the secure confirmation succeeds.")}
              </p>
              {error && <p className="mt-3 text-sm font-semibold text-danger">{error}</p>}
              <div className="mt-4 grid gap-2">
                <Button
                  size="lg"
                  disabled={Boolean(pending) || !data.items.length || !data.attachments.length}
                  onClick={() => void confirm()}
                >
                  <CheckCircle2 />
                  {pending === "confirm" ? t("Confirming…") : t("Confirm receiving")}
                </Button>
                <Button variant="outline" disabled={Boolean(pending)} onClick={() => void cancel()}>
                  <XCircle /> {pending === "cancel" ? t("Cancelling…") : t("Cancel draft")}
                </Button>
              </div>
            </section>
          )}
        </aside>
      </div>
    </>
  );
}

function DetailRow({
  icon: Icon,
  label,
  value,
}: {
  icon: typeof FileText;
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

function ConfirmationSummary({ result }: { result: ReceiptConfirmation }) {
  const { language, t } = useLanguage();
  const locale = language === "fr" ? "fr-FR" : "en-GB";
  return (
    <section className="mb-5 border border-success/30 bg-success-soft p-5" role="status">
      <div className="flex items-start gap-3">
        <CheckCircle2 className="mt-0.5 size-6 shrink-0 text-success" />
        <div>
          <h2 className="font-black text-success">{t("Receiving confirmed")}</h2>
          <p className="mt-1 text-sm">
            {result.receipt_number} · {t("Physical stock updated atomically")}
          </p>
        </div>
      </div>
      <div className="mt-4 grid gap-3 md:grid-cols-2">
        {result.balances.map((balance) => (
          <dl
            key={balance.receipt_item_id}
            className="grid grid-cols-3 gap-2 border bg-card p-3 text-sm"
          >
            <div>
              <dt className="text-xs text-muted-foreground">{t("Before")}</dt>
              <dd className="font-black">{formatStockQuantity(balance.physical_before, locale)}</dd>
            </div>
            <div>
              <dt className="text-xs text-muted-foreground">{t("Received")}</dt>
              <dd className="font-black text-success">
                +{formatStockQuantity(balance.quantity_received, locale)}
              </dd>
            </div>
            <div>
              <dt className="text-xs text-muted-foreground">{t("Available after")}</dt>
              <dd className="font-black">{formatStockQuantity(balance.available_after, locale)}</dd>
            </div>
          </dl>
        ))}
      </div>
    </section>
  );
}
