import { useServerFn } from "@tanstack/react-start";
import {
  CheckCircle2,
  LoaderCircle,
  PackageCheck,
  Save,
  ShieldCheck,
  TriangleAlert,
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";

import { PageHeader } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { useLanguage } from "@/lib/i18n/use-language";
import {
  calculatePreparationRequirementsFn,
  confirmPreparationFn,
  createPreparationDraftFn,
  updatePreparationDraftFn,
} from "@/lib/preparation/functions";
import {
  preparationAvailability,
  type PreparationEditorData,
  type PreparationPreview,
} from "@/lib/preparation/types";
import { formatStockQuantity } from "@/lib/stock/types";
import { cn } from "@/lib/utils";

export function PreparationForm({ data }: { data: PreparationEditorData }) {
  const { language, t } = useLanguage();
  const locale = language === "fr" ? "fr-FR" : "en-GB";
  const existing = data.preparation?.preparation;
  const calculate = useServerFn(calculatePreparationRequirementsFn);
  const createDraft = useServerFn(createPreparationDraftFn);
  const updateDraft = useServerFn(updatePreparationDraftFn);
  const confirm = useServerFn(confirmPreparationFn);
  const initialRecipe = data.recipes.find((recipe) => recipe.id === existing?.recipe_id);
  const [product, setProduct] = useState(initialRecipe?.product_name ?? "");
  const [recipeId, setRecipeId] = useState(existing?.recipe_id ?? "");
  const [locationId, setLocationId] = useState(
    existing?.location_id ?? data.locations[0]?.id ?? "",
  );
  const [quantity, setQuantity] = useState(
    String(existing?.actual_quantity ?? existing?.planned_quantity ?? ""),
  );
  const [comment, setComment] = useState(existing?.comment ?? "");
  const [preview, setPreview] = useState<PreparationPreview | null>(null);
  const [loadingPreview, setLoadingPreview] = useState(false);
  const [pending, setPending] = useState<"save" | "confirm" | null>(null);
  const [error, setError] = useState("");
  const products = useMemo(
    () => [...new Set(data.recipes.map((recipe) => recipe.product_name))].sort(),
    [data.recipes],
  );
  const productRecipes = data.recipes.filter((recipe) => recipe.product_name === product);

  useEffect(() => {
    const numericQuantity = Number(quantity);
    if (!recipeId || !locationId || !Number.isFinite(numericQuantity) || numericQuantity <= 0) {
      setPreview(null);
      return;
    }
    let active = true;
    const timer = window.setTimeout(async () => {
      setLoadingPreview(true);
      setError("");
      try {
        const result = await calculate({
          data: { recipeId, locationId, quantity: numericQuantity },
        });
        if (active) setPreview(result);
      } catch (caught) {
        if (active) {
          setPreview(null);
          setError(
            caught instanceof Error ? caught.message : t("Unable to calculate requirements"),
          );
        }
      } finally {
        if (active) setLoadingPreview(false);
      }
    }, 250);
    return () => {
      active = false;
      window.clearTimeout(timer);
    };
  }, [calculate, locationId, quantity, recipeId, t]);

  const availability = preparationAvailability(preview?.components ?? []);
  const save = async (confirmAfter: boolean) => {
    if (pending || !recipeId || !locationId || Number(quantity) <= 0) return;
    if (confirmAfter && !availability.sufficient) return;
    setPending(confirmAfter ? "confirm" : "save");
    setError("");
    try {
      const payload = { recipeId, locationId, plannedQuantity: Number(quantity), comment };
      const draft = existing
        ? await updateDraft({
            data: { ...payload, preparationId: existing.id, actualQuantity: Number(quantity) },
          })
        : await createDraft({ data: payload });
      if (confirmAfter) await confirm({ data: { preparationId: draft.id } });
      window.location.assign(`/facolub/preparation/${draft.id}`);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t("Preparation operation failed"));
      setPending(null);
    }
  };

  return (
    <>
      <PageHeader
        eyebrow="Prepared bottles"
        title={existing ? "Edit preparation draft" : "Prepare bottles"}
        description="Select product, format, and quantity. The server calculates and validates every component."
      />
      <div className="mx-auto max-w-3xl space-y-5 pb-28 lg:pb-0">
        <section className="border bg-card p-4 shadow-sm sm:p-5">
          <h2 className="mb-4 flex items-center gap-2 border-b pb-3 font-black uppercase">
            <PackageCheck className="size-5 text-primary" /> {t("Preparation")}
          </h2>
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-2">
              <Label>{t("Product")}</Label>
              <select
                required
                className="h-12 w-full rounded-md border bg-background px-3 text-base font-semibold"
                value={product}
                onChange={(e) => {
                  setProduct(e.target.value);
                  setRecipeId("");
                }}
              >
                <option value="">{t("Select product")}</option>
                {products.map((item) => (
                  <option key={item}>{item}</option>
                ))}
              </select>
            </div>
            <div className="space-y-2">
              <Label>{t("Format")}</Label>
              <select
                required
                disabled={!product}
                className="h-12 w-full rounded-md border bg-background px-3 text-base font-semibold"
                value={recipeId}
                onChange={(e) => setRecipeId(e.target.value)}
              >
                <option value="">{t("Select format")}</option>
                {productRecipes.map((recipe) => (
                  <option key={recipe.id} value={recipe.id}>
                    {recipe.format_name}
                  </option>
                ))}
              </select>
            </div>
            <div className="space-y-2">
              <Label>{t("Quantity")}</Label>
              <Input
                className="h-14 text-2xl font-black"
                inputMode="decimal"
                type="number"
                min="0.001"
                step="0.001"
                value={quantity}
                onChange={(e) => setQuantity(e.target.value)}
                placeholder="100"
              />
            </div>
            <div className="space-y-2">
              <Label>{t("Location")}</Label>
              <select
                required
                className="h-14 w-full rounded-md border bg-background px-3"
                value={locationId}
                onChange={(e) => setLocationId(e.target.value)}
              >
                {data.locations.map((location) => (
                  <option key={location.id} value={location.id}>
                    {location.name}
                  </option>
                ))}
              </select>
            </div>
          </div>
          <div className="mt-4 space-y-2">
            <Label>{t("Comment")}</Label>
            <Textarea
              maxLength={2000}
              value={comment}
              onChange={(e) => setComment(e.target.value)}
              placeholder={t("Optional preparation notes")}
            />
          </div>
        </section>

        <section className="border bg-card p-4 shadow-sm sm:p-5">
          <h2 className="mb-4 font-black uppercase">{t("Required components")}</h2>
          {loadingPreview && (
            <p className="flex items-center gap-2 text-sm">
              <LoaderCircle className="size-4 animate-spin" /> {t("Calculating…")}
            </p>
          )}
          {!preview && !loadingPreview && (
            <p className="text-sm text-muted-foreground">
              {t("Select product, format, and quantity to calculate requirements.")}
            </p>
          )}
          {preview && (
            <div className="space-y-3">
              {preview.components.map((item) => (
                <article
                  key={item.stock_item_id}
                  className={cn(
                    "border p-4",
                    item.sufficient
                      ? "border-success/30 bg-success-soft"
                      : "border-danger/30 bg-danger-soft",
                  )}
                >
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <p className="font-black">{item.name}</p>
                      <p className="mt-1 text-xs uppercase text-muted-foreground">
                        {t(item.category === "empty_bottle" ? "Empty bottle" : "Label")}
                      </p>
                    </div>
                    <span
                      className={cn(
                        "text-xs font-black uppercase",
                        item.sufficient ? "text-success" : "text-danger",
                      )}
                    >
                      {t(item.sufficient ? "Available" : "Unavailable")}
                    </span>
                  </div>
                  <dl className="mt-3 grid grid-cols-3 gap-2 text-sm">
                    <Metric
                      label={t("Required")}
                      value={formatStockQuantity(item.required_quantity, locale)}
                    />
                    <Metric
                      label={t("Available")}
                      value={formatStockQuantity(item.available_quantity, locale)}
                    />
                    <Metric
                      label={t("Missing")}
                      value={formatStockQuantity(item.missing_quantity, locale)}
                    />
                  </dl>
                </article>
              ))}
            </div>
          )}
        </section>

        {preview && (
          <section className="border border-primary/30 bg-secondary p-5">
            <p className="text-xs font-black uppercase text-muted-foreground">{t("Output")}</p>
            <div className="mt-2 flex items-end justify-between gap-3">
              <p className="font-black">{preview.output.name}</p>
              <p className="text-2xl font-black text-primary">
                +{formatStockQuantity(preview.output.quantity, locale)}
              </p>
            </div>
          </section>
        )}
        {preview && !availability.sufficient && (
          <p
            role="alert"
            className="flex items-start gap-2 border border-danger/30 bg-danger-soft p-4 text-sm font-semibold text-danger"
          >
            <TriangleAlert className="mt-0.5 size-5 shrink-0" />
            {availability.missingCount}{" "}
            {t(
              availability.missingCount === 1
                ? "component is unavailable"
                : "components are unavailable",
            )}
            . {t("Confirmation is disabled.")}
          </p>
        )}
        <p className="flex items-start gap-2 border border-warning/30 bg-warning-soft p-4 text-sm">
          <ShieldCheck className="mt-0.5 size-5 shrink-0" />
          {t("Confirmation is atomic and creates immutable stock movements.")}
        </p>
        {error && (
          <p
            role="alert"
            className="border border-danger/30 bg-danger-soft p-4 text-sm font-semibold text-danger"
          >
            {error}
          </p>
        )}
        <div className="fixed inset-x-0 bottom-16 z-30 border-t bg-background/95 p-3 backdrop-blur lg:static lg:border-0 lg:bg-transparent lg:p-0">
          <div className="mx-auto grid max-w-3xl grid-cols-2 gap-3 lg:flex lg:justify-end">
            <Button
              variant="outline"
              size="lg"
              disabled={Boolean(pending) || !recipeId || Number(quantity) <= 0}
              onClick={() => void save(false)}
            >
              {pending === "save" ? <LoaderCircle className="animate-spin" /> : <Save />}{" "}
              {t("Save draft")}
            </Button>
            <Button
              size="lg"
              disabled={Boolean(pending) || !availability.sufficient}
              onClick={() => void save(true)}
            >
              {pending === "confirm" ? <LoaderCircle className="animate-spin" /> : <CheckCircle2 />}{" "}
              {t("Confirm preparation")}
            </Button>
          </div>
        </div>
      </div>
    </>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className="mt-1 font-black tabular-nums">{value}</dd>
    </div>
  );
}
