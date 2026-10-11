import { Link, useRouter } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import {
  ArrowDownToLine,
  ArrowUpFromLine,
  CheckCircle2,
  Pencil,
  UserRound,
  XCircle,
} from "lucide-react";
import { useState } from "react";

import { PageHeader } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { useLanguage } from "@/lib/i18n/use-language";
import { cancelPreparationFn, confirmPreparationFn } from "@/lib/preparation/functions";
import type { PreparationDetail } from "@/lib/preparation/types";
import { formatStockQuantity } from "@/lib/stock/types";
import { PreparationStatusBadge } from "./preparation-status";

export function PreparationDetailView({ data }: { data: PreparationDetail }) {
  const router = useRouter();
  const confirm = useServerFn(confirmPreparationFn);
  const cancel = useServerFn(cancelPreparationFn);
  const { language, t } = useLanguage();
  const locale = language === "fr" ? "fr-FR" : "en-GB";
  const [pending, setPending] = useState<"confirm" | "cancel" | null>(null);
  const [error, setError] = useState("");
  const preparation = data.preparation;
  const isDraft = preparation.status === "draft";
  const doConfirm = async () => {
    if (pending) return;
    setPending("confirm");
    setError("");
    try {
      await confirm({ data: { preparationId: preparation.id } });
      await router.invalidate();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t("Unable to confirm preparation"));
      setPending(null);
    }
  };
  const doCancel = async () => {
    if (pending || !window.confirm(t("Cancel this preparation draft?"))) return;
    setPending("cancel");
    try {
      await cancel({ data: { preparationId: preparation.id } });
      window.location.assign("/facolub/preparation");
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t("Unable to cancel preparation"));
      setPending(null);
    }
  };
  return (
    <>
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <PageHeader
          eyebrow="Prepared bottles"
          title={preparation.preparation_number ?? "Draft preparation"}
          description={`${preparation.product_name_snapshot} · ${preparation.format_name_snapshot}`}
        />
        <div className="flex flex-wrap gap-2">
          <PreparationStatusBadge status={preparation.status} />
          {isDraft && (
            <Button asChild variant="outline">
              <Link to="/facolub/preparation/new" search={{ preparationId: preparation.id }}>
                <Pencil /> {t("Edit draft")}
              </Link>
            </Button>
          )}
        </div>
      </div>
      <div className="grid gap-5 xl:grid-cols-[minmax(0,1.5fr)_minmax(300px,.7fr)]">
        <div className="space-y-5">
          <section className="border bg-card p-5 shadow-sm">
            <h2 className="flex items-center gap-2 font-black">
              <ArrowUpFromLine className="size-5 text-danger" /> {t("Components consumed")}
            </h2>
            <div className="mt-4 space-y-3">
              {data.components.map((item) => (
                <div
                  key={item.id}
                  className="flex items-center justify-between gap-4 border bg-background p-4"
                >
                  <div>
                    <p className="font-bold">{item.name}</p>
                    <p className="text-xs text-muted-foreground">
                      × {formatStockQuantity(item.quantity_per_output, locale)} / {t("bottle")}
                    </p>
                  </div>
                  <p className="text-xl font-black text-danger">
                    {item.required_quantity == null
                      ? "—"
                      : `−${formatStockQuantity(item.required_quantity, locale)}`}
                  </p>
                </div>
              ))}
            </div>
          </section>
          <section className="border border-success/30 bg-success-soft p-5">
            <h2 className="flex items-center gap-2 font-black">
              <ArrowDownToLine className="size-5 text-success" /> {t("Prepared output")}
            </h2>
            <div className="mt-4 flex items-center justify-between gap-4">
              <p className="font-bold">{preparation.output_item_name_snapshot}</p>
              <p className="text-2xl font-black text-success">
                +
                {formatStockQuantity(
                  data.output_movement?.quantity ??
                    preparation.actual_quantity ??
                    preparation.planned_quantity ??
                    0,
                  locale,
                )}
              </p>
            </div>
          </section>
        </div>
        <aside className="space-y-5">
          <section className="border bg-card p-5 shadow-sm">
            <h2 className="font-black">{t("Traceability")}</h2>
            <dl className="mt-4 space-y-3 text-sm">
              <Info label={t("Location")} value={data.location_name} />
              <Info
                label={t("Recipe version")}
                value={String(preparation.recipe_version_snapshot)}
              />
              <Info label={t("Created by")} value={data.created_by_name} />
              <Info label={t("Confirmed by")} value={data.confirmed_by_name ?? "—"} />
              <Info
                label={t("Confirmed at")}
                value={
                  preparation.confirmed_at
                    ? new Date(preparation.confirmed_at).toLocaleString(locale)
                    : "—"
                }
              />
            </dl>
          </section>
          {isDraft && (
            <section className="space-y-3 border bg-card p-5 shadow-sm">
              <Button
                className="w-full"
                size="lg"
                disabled={Boolean(pending)}
                onClick={() => void doConfirm()}
              >
                <CheckCircle2 /> {t("Confirm preparation")}
              </Button>
              <Button
                className="w-full"
                variant="outline"
                disabled={Boolean(pending)}
                onClick={() => void doCancel()}
              >
                <XCircle /> {t("Cancel draft")}
              </Button>
            </section>
          )}
        </aside>
      </div>
      {error && (
        <p className="mt-5 border border-danger/30 bg-danger-soft p-4 text-sm font-semibold text-danger">
          {error}
        </p>
      )}
    </>
  );
}

function Info({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="flex items-center gap-2 text-xs font-bold uppercase text-muted-foreground">
        <UserRound className="size-3" />
        {label}
      </dt>
      <dd className="mt-1 font-semibold">{value}</dd>
    </div>
  );
}
