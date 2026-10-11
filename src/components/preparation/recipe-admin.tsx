import { useRouter } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { Beaker, LoaderCircle, Plus, PowerOff, Save, Trash2 } from "lucide-react";
import { useMemo, useState } from "react";

import { PageHeader } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useLanguage } from "@/lib/i18n/use-language";
import { deactivateRecipeFn, saveRecipeFn } from "@/lib/preparation/functions";
import type { PreparedBottleRecipe, RecipeAdminData } from "@/lib/preparation/types";

type ComponentDraft = { key: string; stockItemId: string; quantity: string };
const blankComponent = (): ComponentDraft => ({
  key: crypto.randomUUID(),
  stockItemId: "",
  quantity: "1",
});

export function RecipeAdmin({ data }: { data: RecipeAdminData }) {
  const router = useRouter();
  const saveRecipe = useServerFn(saveRecipeFn);
  const deactivateRecipe = useServerFn(deactivateRecipeFn);
  const { t } = useLanguage();
  const [editing, setEditing] = useState<PreparedBottleRecipe | null>(null);
  const [productName, setProductName] = useState("");
  const [formatName, setFormatName] = useState("");
  const [outputId, setOutputId] = useState("");
  const [components, setComponents] = useState<ComponentDraft[]>([
    blankComponent(),
    blankComponent(),
  ]);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const items = useMemo(
    () => new Map(data.componentItems.map((item) => [item.id, item])),
    [data.componentItems],
  );

  const edit = (recipe: PreparedBottleRecipe) => {
    setEditing(recipe);
    setProductName(recipe.product_name);
    setFormatName(recipe.format_name);
    setOutputId(recipe.output_stock_item_id);
    setComponents(
      recipe.components.map((component) => ({
        key: component.id,
        stockItemId: component.stock_item_id,
        quantity: String(component.quantity_per_output),
      })),
    );
    setError("");
    window.scrollTo({ top: 0, behavior: "smooth" });
  };
  const clear = () => {
    setEditing(null);
    setProductName("");
    setFormatName("");
    setOutputId("");
    setComponents([blankComponent(), blankComponent()]);
    setError("");
  };
  const save = async () => {
    if (pending) return;
    setPending(true);
    setError("");
    try {
      await saveRecipe({
        data: {
          recipeId: editing?.id ?? null,
          productName,
          formatName,
          outputStockItemId: outputId,
          components: components.map((component) => ({
            stockItemId: component.stockItemId,
            quantityPerOutput: Number(component.quantity),
          })),
        },
      });
      await router.invalidate();
      clear();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t("Unable to save recipe"));
    } finally {
      setPending(false);
    }
  };
  const deactivate = async (recipe: PreparedBottleRecipe) => {
    if (pending || !window.confirm(t("Deactivate this recipe?"))) return;
    setPending(true);
    setError("");
    try {
      await deactivateRecipe({ data: { recipeId: recipe.id } });
      await router.invalidate();
      if (editing?.id === recipe.id) clear();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t("Unable to deactivate recipe"));
    } finally {
      setPending(false);
    }
  };
  const valid =
    productName.trim() &&
    formatName.trim() &&
    outputId &&
    components.length >= 2 &&
    components.every((component) => component.stockItemId && Number(component.quantity) > 0) &&
    components.some((component) => items.get(component.stockItemId)?.category === "empty_bottle") &&
    components.some((component) => items.get(component.stockItemId)?.category === "label");

  return (
    <>
      <PageHeader
        eyebrow="Settings"
        title="Prepared bottle recipes"
        description="Configure the empty bottle and label components required for each product and format."
      />
      <section className="mb-7 max-w-3xl border bg-card p-5 shadow-sm">
        <div className="mb-4 flex items-center justify-between gap-3 border-b pb-3">
          <h2 className="flex items-center gap-2 font-black">
            <Beaker className="size-5 text-primary" />
            {editing ? t("New recipe version") : t("New recipe")}
          </h2>
          {editing && (
            <Button variant="ghost" onClick={clear}>
              {t("Cancel editing")}
            </Button>
          )}
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field
            label={t("Product")}
            value={productName}
            onChange={setProductName}
            placeholder="10W40"
          />
          <Field label={t("Format")} value={formatName} onChange={setFormatName} placeholder="5L" />
          <label className="space-y-2 sm:col-span-2">
            <Label>{t("Prepared bottle output")}</Label>
            <select
              className="h-11 w-full rounded-md border bg-background px-3"
              value={outputId}
              onChange={(e) => setOutputId(e.target.value)}
            >
              <option value="">{t("Select prepared bottle item")}</option>
              {data.outputItems.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.name}
                </option>
              ))}
            </select>
          </label>
        </div>
        <div className="mt-5">
          <div className="mb-3 flex items-center justify-between">
            <Label>{t("Components")}</Label>
            <Button
              variant="outline"
              size="sm"
              onClick={() => setComponents((current) => [...current, blankComponent()])}
            >
              <Plus /> {t("Add component")}
            </Button>
          </div>
          <div className="space-y-3">
            {components.map((component, index) => (
              <div
                key={component.key}
                className="grid grid-cols-[1fr_110px_40px] gap-2 border bg-background p-3"
              >
                <select
                  className="h-10 rounded-md border bg-card px-3"
                  value={component.stockItemId}
                  onChange={(e) =>
                    setComponents((current) =>
                      current.map((item) =>
                        item.key === component.key
                          ? { ...item, stockItemId: e.target.value }
                          : item,
                      ),
                    )
                  }
                >
                  <option value="">{t("Select component")}</option>
                  {data.componentItems.map((item) => (
                    <option
                      key={item.id}
                      value={item.id}
                      disabled={components.some(
                        (candidate) =>
                          candidate.key !== component.key && candidate.stockItemId === item.id,
                      )}
                    >
                      {item.name} · {t(item.category === "label" ? "Label" : "Empty bottle")}
                    </option>
                  ))}
                </select>
                <Input
                  aria-label={`${t("Quantity")} ${index + 1}`}
                  inputMode="decimal"
                  type="number"
                  min="0.001"
                  step="0.001"
                  value={component.quantity}
                  onChange={(e) =>
                    setComponents((current) =>
                      current.map((item) =>
                        item.key === component.key ? { ...item, quantity: e.target.value } : item,
                      ),
                    )
                  }
                />
                <Button
                  variant="ghost"
                  size="icon"
                  disabled={components.length <= 2}
                  onClick={() =>
                    setComponents((current) => current.filter((item) => item.key !== component.key))
                  }
                >
                  <Trash2 />
                </Button>
              </div>
            ))}
          </div>
        </div>
        <p className="mt-3 text-xs text-muted-foreground">
          {t(
            "Every recipe requires at least one empty bottle and one label. Saving an edit creates a new immutable version.",
          )}
        </p>
        {error && (
          <p className="mt-4 border border-danger/30 bg-danger-soft p-3 text-sm font-semibold text-danger">
            {error}
          </p>
        )}
        <div className="mt-5 flex justify-end">
          <Button size="lg" disabled={!valid || pending} onClick={() => void save()}>
            {pending ? <LoaderCircle className="animate-spin" /> : <Save />} {t("Save recipe")}
          </Button>
        </div>
      </section>
      <h2 className="mb-3 text-lg font-black">{t("Recipe versions")}</h2>
      <div className="grid gap-3 lg:grid-cols-2">
        {data.recipes.map((recipe) => (
          <article key={recipe.id} className="border bg-card p-4 shadow-sm">
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="font-black">
                  {recipe.product_name} · {recipe.format_name}
                </p>
                <p className="mt-1 text-sm text-muted-foreground">
                  {recipe.output_stock_item_name} · v{recipe.version}
                </p>
              </div>
              <span
                className={
                  recipe.is_active
                    ? "text-xs font-black uppercase text-success"
                    : "text-xs font-black uppercase text-muted-foreground"
                }
              >
                {t(recipe.is_active ? "Active" : "Inactive")}
              </span>
            </div>
            <ul className="mt-4 space-y-2 border-t pt-3 text-sm">
              {recipe.components.map((component) => (
                <li key={component.id} className="flex justify-between gap-3">
                  <span>{component.stock_item_name}</span>
                  <strong>× {component.quantity_per_output}</strong>
                </li>
              ))}
            </ul>
            {recipe.is_active && (
              <div className="mt-4 flex justify-end gap-2">
                <Button variant="outline" size="sm" onClick={() => edit(recipe)}>
                  {t("Edit")}
                </Button>
                <Button variant="outline" size="sm" onClick={() => void deactivate(recipe)}>
                  <PowerOff /> {t("Deactivate")}
                </Button>
              </div>
            )}
          </article>
        ))}
      </div>
    </>
  );
}

function Field({
  label,
  value,
  onChange,
  placeholder,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  placeholder: string;
}) {
  return (
    <div className="space-y-2">
      <Label>{label}</Label>
      <Input
        className="h-11"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
      />
    </div>
  );
}
