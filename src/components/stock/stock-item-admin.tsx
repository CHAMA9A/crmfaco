import { useServerFn } from "@tanstack/react-start";
import { useRouter } from "@tanstack/react-router";
import { Pencil, Plus } from "lucide-react";
import { useState, type FormEvent } from "react";

import { EmptyState, PageHeader } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { saveStockItemFn } from "@/lib/stock/functions";
import { useLanguage } from "@/lib/i18n/use-language";
import {
  stockCategories,
  stockCategoryLabels,
  stockUnitLabels,
  stockUnits,
  type StockItemAdminData,
} from "@/lib/stock/types";
import type { StockItem } from "@/types/database";

export function StockItemAdmin({ data }: { data: StockItemAdminData }) {
  const { t } = useLanguage();
  const [editing, setEditing] = useState<StockItem | null>(null);
  const [open, setOpen] = useState(false);
  const startCreate = () => {
    setEditing(null);
    setOpen(true);
  };
  const startEdit = (item: StockItem) => {
    setEditing(item);
    setOpen(true);
  };
  return (
    <>
      <div className="flex items-start justify-between gap-4">
        <PageHeader
          title="Stock items"
          description="Configure item identity, canonical unit, minimum threshold, and active state. Quantities cannot be edited here."
        />
        <Button onClick={startCreate}>
          <Plus /> {t("New item")}
        </Button>
      </div>
      {data.items.length === 0 ? (
        <EmptyState
          title="No stock items"
          description="Create the first stock item. Opening quantities must be recorded through the immutable movement engine."
          icon={Plus}
        />
      ) : (
        <div className="overflow-x-auto border bg-card">
          <table className="w-full text-sm">
            <thead className="border-b bg-muted/50 text-left text-xs uppercase text-muted-foreground">
              <tr>
                <th className="px-4 py-3">{t("Item")}</th>
                <th className="px-4 py-3">{t("Category")}</th>
                <th className="px-4 py-3">{t("Unit")}</th>
                <th className="px-4 py-3">{t("Minimum")}</th>
                <th className="px-4 py-3">{t("State")}</th>
                <th className="px-4 py-3">
                  <span className="sr-only">Actions</span>
                </th>
              </tr>
            </thead>
            <tbody>
              {data.items.map((item) => (
                <tr key={item.id} className="border-b last:border-0">
                  <td className="px-4 py-3">
                    <p className="font-bold">{item.name}</p>
                    <p className="text-xs text-muted-foreground">{item.code ?? t("No code")}</p>
                  </td>
                  <td className="px-4 py-3">{t(stockCategoryLabels[item.category])}</td>
                  <td className="px-4 py-3">{t(stockUnitLabels[item.unit])}</td>
                  <td className="px-4 py-3 tabular-nums">{item.minimum_stock ?? t("Not set")}</td>
                  <td className="px-4 py-3">
                    <span
                      className={
                        item.is_active
                          ? "font-bold text-success"
                          : "font-bold text-muted-foreground"
                      }
                    >
                      {t(item.is_active ? "Active" : "Inactive")}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-right">
                    <Button variant="outline" size="sm" onClick={() => startEdit(item)}>
                      <Pencil /> {t("Edit")}
                    </Button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <Dialog open={open} onOpenChange={setOpen}>
        <StockItemDialog item={editing} close={() => setOpen(false)} />
      </Dialog>
    </>
  );
}

function StockItemDialog({ item, close }: { item: StockItem | null; close: () => void }) {
  const save = useServerFn(saveStockItemFn);
  const router = useRouter();
  const { t } = useLanguage();
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (pending) return;
    setPending(true);
    setError("");
    const form = new FormData(event.currentTarget);
    try {
      await save({
        data: {
          id: item?.id ?? "",
          code: String(form.get("code") ?? ""),
          name: String(form.get("name") ?? ""),
          category: String(form.get("category") ?? "other") as StockItem["category"],
          unit: String(form.get("unit") ?? "piece") as StockItem["unit"],
          productFormatId: item?.product_format_id ?? "",
          minimumStock: String(form.get("minimumStock") ?? ""),
          notes: String(form.get("notes") ?? ""),
          isActive: form.get("isActive") === "on",
        },
      });
      close();
      await router.invalidate();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : t("Unable to save stock item"));
    } finally {
      setPending(false);
    }
  };
  return (
    <DialogContent className="max-h-[90vh] overflow-y-auto">
      <DialogHeader>
        <DialogTitle>{t(item ? "Edit stock item" : "New stock item")}</DialogTitle>
        <DialogDescription>
          {t("Configuration only. Stock quantities remain ledger-derived.")}
        </DialogDescription>
      </DialogHeader>
      <form onSubmit={submit} className="space-y-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label={t("Name")} name="name" defaultValue={item?.name} required />
          <Field label={t("Code")} name="code" defaultValue={item?.code ?? ""} />
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <label className="text-sm font-medium">
            {t("Category")}
            <select
              name="category"
              defaultValue={item?.category ?? "other"}
              className="mt-2 h-10 w-full rounded-md border bg-background px-3 font-normal"
            >
              {stockCategories.map((category) => (
                <option key={category} value={category}>
                  {t(stockCategoryLabels[category])}
                </option>
              ))}
            </select>
          </label>
          <label className="text-sm font-medium">
            {t("Canonical unit")}
            <select
              name="unit"
              defaultValue={item?.unit ?? "piece"}
              className="mt-2 h-10 w-full rounded-md border bg-background px-3 font-normal"
            >
              {stockUnits.map((unit) => (
                <option key={unit} value={unit}>
                  {t(stockUnitLabels[unit])}
                </option>
              ))}
            </select>
          </label>
        </div>
        <Field
          label={t("Minimum available stock")}
          name="minimumStock"
          type="number"
          min="0"
          step="0.001"
          defaultValue={item?.minimum_stock ?? ""}
        />
        <div>
          <Label htmlFor="stock-notes">{t("Notes")}</Label>
          <Textarea
            id="stock-notes"
            name="notes"
            className="mt-2"
            defaultValue={item?.notes ?? ""}
            maxLength={2000}
          />
        </div>
        <label className="flex items-center gap-3 border p-3 text-sm font-semibold">
          <input
            name="isActive"
            type="checkbox"
            defaultChecked={item?.is_active ?? true}
            className="size-4"
          />{" "}
          {t("Active item")}
        </label>
        {error && (
          <p role="alert" className="text-sm font-semibold text-danger">
            {error}
          </p>
        )}
        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={close}>
            {t("Cancel")}
          </Button>
          <Button type="submit" disabled={pending}>
            {pending ? t("Saving…") : t("Save item")}
          </Button>
        </div>
      </form>
    </DialogContent>
  );
}

function Field({
  label,
  name,
  ...props
}: { label: string; name: string } & React.ComponentProps<typeof Input>) {
  return (
    <div>
      <Label htmlFor={`stock-${name}`}>{label}</Label>
      <Input id={`stock-${name}`} name={name} className="mt-2" {...props} />
    </div>
  );
}
