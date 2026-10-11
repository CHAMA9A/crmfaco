import { Link } from "@tanstack/react-router";
import { History, PackageCheck } from "lucide-react";
import { useMemo, useState } from "react";

import { EmptyState, PageHeader } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useLanguage } from "@/lib/i18n/use-language";
import type { PreparationListRow } from "@/lib/preparation/types";
import { PreparationCards } from "./preparation-list";

export function PreparationHome({ rows }: { rows: PreparationListRow[] }) {
  const { t } = useLanguage();
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState("");
  const filtered = useMemo(() => {
    const query = search.trim().toLocaleLowerCase();
    return rows.filter(
      (row) =>
        (!status || row.status === status) &&
        (!query ||
          row.preparation_number?.toLocaleLowerCase().includes(query) ||
          row.product_name.toLocaleLowerCase().includes(query) ||
          row.format_name.toLocaleLowerCase().includes(query)),
    );
  }, [rows, search, status]);
  return (
    <>
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <PageHeader
          eyebrow="Stock"
          title="Prepared bottles"
          description="Turn empty bottles and required labels into filling-ready prepared bottles."
        />
        <div className="flex flex-wrap gap-2">
          <Button asChild variant="outline">
            <Link to="/facolub/preparation/history">
              <History /> {t("History")}
            </Link>
          </Button>
          <Button asChild size="lg">
            <Link to="/facolub/preparation/new">
              <PackageCheck /> {t("Prepare bottles")}
            </Link>
          </Button>
        </div>
      </div>
      <section className="mb-6 grid gap-3 border bg-card p-4 shadow-sm sm:grid-cols-[1fr_190px]">
        <Input
          className="h-11"
          placeholder={t("Number, product, or format")}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <select
          className="h-11 rounded-md border bg-background px-3"
          value={status}
          onChange={(e) => setStatus(e.target.value)}
        >
          <option value="">{t("All statuses")}</option>
          <option value="draft">{t("Draft")}</option>
          <option value="confirmed">{t("Confirmed")}</option>
          <option value="cancelled">{t("Cancelled")}</option>
        </select>
      </section>
      {filtered.length ? (
        <PreparationCards rows={filtered} />
      ) : (
        <EmptyState
          title="No preparations found"
          description="Create a draft for the next bottle preparation."
          icon={PackageCheck}
        />
      )}
    </>
  );
}
