import { Link, createFileRoute } from "@tanstack/react-router";
import { ArrowRight, Boxes, Truck } from "lucide-react";

import { PageHeader } from "@/components/app/facolub-ui";
import { useLanguage } from "@/lib/i18n/use-language";

export const Route = createFileRoute("/facolub/settings/")({
  component: SettingsIndexRoute,
});

function SettingsIndexRoute() {
  const { t } = useLanguage();
  return (
    <>
      <PageHeader title="Settings" description="Configure FACOLUB operational reference data." />
      <div className="grid max-w-xl gap-3">
        <Link
          to="/facolub/settings/stock-items"
          className="group flex items-center justify-between gap-4 border bg-card p-5 shadow-sm hover:border-primary"
        >
          <span className="flex items-center gap-4">
            <span className="grid size-11 place-items-center rounded-md bg-secondary text-primary">
              <Boxes className="size-5" />
            </span>
            <span>
              <span className="block font-bold">{t("Stock items")}</span>
              <span className="mt-1 block text-sm text-muted-foreground">
                {t("Categories, units, thresholds, and activation")}
              </span>
            </span>
          </span>
          <ArrowRight className="size-5 transition-transform group-hover:translate-x-1" />
        </Link>
        <Link
          to="/facolub/settings/suppliers"
          className="group flex items-center justify-between gap-4 border bg-card p-5 shadow-sm hover:border-primary"
        >
          <span className="flex items-center gap-4">
            <span className="grid size-11 place-items-center rounded-md bg-secondary text-primary">
              <Truck className="size-5" />
            </span>
            <span>
              <span className="block font-bold">{t("Suppliers")}</span>
              <span className="mt-1 block text-sm text-muted-foreground">
                {t("Receiving supplier directory and activation")}
              </span>
            </span>
          </span>
          <ArrowRight className="size-5 transition-transform group-hover:translate-x-1" />
        </Link>
      </div>
    </>
  );
}
