import { Link } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import {
  Boxes,
  CalendarDays,
  CheckSquare,
  ClipboardCheck,
  LoaderCircle,
  MapPin,
} from "lucide-react";
import { useMemo, useState } from "react";

import { PageHeader } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { useLanguage } from "@/lib/i18n/use-language";
import { createStockCountFn } from "@/lib/stock-counts/functions";
import type { NewStockCountData, StockCountScope } from "@/lib/stock-counts/types";
import {
  formatStockQuantity,
  stockCategories,
  stockCategoryLabels,
  stockUnitLabels,
} from "@/lib/stock/types";
import type { StockItemCategory } from "@/types/database";

export function StockCountForm({ data }: { data: NewStockCountData }) {
  const createCount = useServerFn(createStockCountFn);
  const { language, t } = useLanguage();
  const locale = language === "fr" ? "fr-FR" : "en-GB";
  const [locationId, setLocationId] = useState(data.locations[0]?.id ?? "");
  const [countDate, setCountDate] = useState(data.today);
  const [comment, setComment] = useState("");
  const [scope, setScope] = useState<StockCountScope>("all");
  const [category, setCategory] = useState<StockItemCategory>("empty_bottle");
  const [selected, setSelected] = useState<string[]>([]);
  const [search, setSearch] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");

  const locationItems = useMemo(() => {
    const term = search.trim().toLowerCase();
    return data.items.filter(
      (item) =>
        item.location_id === locationId &&
        (!term || `${item.name} ${item.code ?? ""}`.toLowerCase().includes(term)),
    );
  }, [data.items, locationId, search]);
  const scopedCount =
    scope === "all"
      ? locationItems.length
      : scope === "category"
        ? locationItems.filter((item) => item.category === category).length
        : selected.length;

  const submit = async () => {
    if (pending) return;
    if (!locationId || !countDate) return setError(t("Date and location are required."));
    if (scope === "items" && selected.length === 0)
      return setError(t("Select at least one stock item."));
    setPending(true);
    setError("");
    try {
      const detail = await createCount({
        data: {
          locationId,
          countDate,
          comment,
          category: scope === "category" ? category : null,
          stockItemIds: scope === "items" ? selected : null,
        },
      });
      window.location.assign(`/facolub/stock/counts/${detail.count.id}`);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t("Unable to create stock count"));
      setPending(false);
    }
  };

  return (
    <>
      <PageHeader
        eyebrow="Physical counts"
        title="New physical stock count"
        description="Choose the scope first. Expected quantities are snapshotted securely when the draft is created."
      />
      <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_340px]">
        <div className="space-y-5">
          <section className="border bg-card p-5 shadow-sm">
            <h2 className="flex items-center gap-2 font-black">
              <CalendarDays className="size-5 text-primary" /> {t("Date and location")}
            </h2>
            <div className="mt-4 grid gap-4 sm:grid-cols-2">
              <div className="space-y-2">
                <Label>{t("Count date")}</Label>
                <Input
                  type="date"
                  value={countDate}
                  onChange={(e) => setCountDate(e.target.value)}
                />
              </div>
              <div className="space-y-2">
                <Label>{t("Location")}</Label>
                <select
                  className="h-10 w-full rounded-md border bg-background px-3"
                  value={locationId}
                  onChange={(e) => {
                    setLocationId(e.target.value);
                    setSelected([]);
                  }}
                >
                  <option value="">{t("Select a location")}</option>
                  {data.locations.map((location) => (
                    <option key={location.id} value={location.id}>
                      {location.name}
                    </option>
                  ))}
                </select>
              </div>
            </div>
          </section>

          <section className="border bg-card p-5 shadow-sm">
            <h2 className="flex items-center gap-2 font-black">
              <Boxes className="size-5 text-primary" /> {t("Count scope")}
            </h2>
            <div className="mt-4 grid gap-3 sm:grid-cols-3">
              {(["all", "category", "items"] as const).map((value) => (
                <button
                  key={value}
                  type="button"
                  onClick={() => setScope(value)}
                  className={`border p-4 text-left transition ${scope === value ? "border-primary bg-secondary" : "bg-background hover:border-primary/50"}`}
                >
                  <p className="font-black">
                    {t(
                      value === "all"
                        ? "All active items"
                        : value === "category"
                          ? "One category"
                          : "Selected items",
                    )}
                  </p>
                  <p className="mt-1 text-xs text-muted-foreground">
                    {t(
                      value === "all"
                        ? "Complete warehouse count"
                        : value === "category"
                          ? "Count a material family"
                          : "Target specific references",
                    )}
                  </p>
                </button>
              ))}
            </div>
            {scope === "category" && (
              <div className="mt-4 max-w-sm space-y-2">
                <Label>{t("Category")}</Label>
                <select
                  className="h-10 w-full rounded-md border bg-background px-3"
                  value={category}
                  onChange={(e) => setCategory(e.target.value as StockItemCategory)}
                >
                  {stockCategories.map((value) => (
                    <option key={value} value={value}>
                      {t(stockCategoryLabels[value])}
                    </option>
                  ))}
                </select>
              </div>
            )}
            {scope === "items" && (
              <div className="mt-4">
                <Input
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  placeholder={t("Search stock items")}
                />
                <div className="mt-3 max-h-80 overflow-y-auto border">
                  {locationItems.map((item) => (
                    <label
                      key={item.id}
                      className="flex cursor-pointer items-center gap-3 border-b p-3 last:border-0 hover:bg-muted/50"
                    >
                      <input
                        type="checkbox"
                        checked={selected.includes(item.id)}
                        onChange={(e) =>
                          setSelected((current) =>
                            e.target.checked
                              ? [...current, item.id]
                              : current.filter((id) => id !== item.id),
                          )
                        }
                      />
                      <div className="min-w-0 flex-1">
                        <p className="font-bold">{item.name}</p>
                        <p className="text-xs text-muted-foreground">
                          {item.code ?? t("No code")} · {t(stockUnitLabels[item.unit])}
                        </p>
                      </div>
                      <span className="text-sm font-black tabular-nums">
                        {formatStockQuantity(item.physical_quantity, locale)}
                      </span>
                    </label>
                  ))}
                </div>
              </div>
            )}
          </section>

          <section className="border bg-card p-5 shadow-sm">
            <Label>{t("Comment (optional)")}</Label>
            <Textarea
              className="mt-2"
              value={comment}
              onChange={(e) => setComment(e.target.value)}
              maxLength={2000}
              placeholder={t("Reason, zone, team or counting instructions")}
            />
          </section>
        </div>

        <aside>
          <section className="sticky top-24 border border-primary/20 bg-secondary p-5">
            <ClipboardCheck className="size-7 text-primary" />
            <h2 className="mt-3 font-black">{t("Ready to count")}</h2>
            <p className="mt-2 text-sm text-muted-foreground">
              {scopedCount} {t("active items will be snapshotted. Drafts never change stock.")}
            </p>
            {error && (
              <p className="mt-4 border border-danger/30 bg-danger-soft p-3 text-sm font-semibold text-danger">
                {error}
              </p>
            )}
            <div className="mt-5 grid gap-2">
              <Button
                size="lg"
                disabled={pending || scopedCount === 0}
                onClick={() => void submit()}
              >
                {pending ? <LoaderCircle className="animate-spin" /> : <CheckSquare />}{" "}
                {pending ? t("Creating…") : t("Create draft count")}
              </Button>
              <Button asChild variant="outline">
                <Link to="/facolub/stock/counts">{t("Cancel")}</Link>
              </Button>
            </div>
          </section>
        </aside>
      </div>
    </>
  );
}
