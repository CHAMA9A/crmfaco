import { Link } from "@tanstack/react-router";
import { History, PackagePlus, Search } from "lucide-react";
import { useMemo, useState } from "react";

import { EmptyState, PageHeader } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useLanguage } from "@/lib/i18n/use-language";
import type { ReceivingHomeData } from "@/lib/receiving/types";
import { ReceiptCards } from "./receipt-list";

export function ReceivingHome({ data }: { data: ReceivingHomeData }) {
  const { t } = useLanguage();
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState("all");
  const filtered = useMemo(() => {
    const query = search.trim().toLocaleLowerCase();
    return data.rows.filter(
      (row) =>
        (status === "all" || row.status === status) &&
        (!query ||
          row.receipt_number?.toLocaleLowerCase().includes(query) ||
          row.supplier_name?.toLocaleLowerCase().includes(query) ||
          row.reference?.toLocaleLowerCase().includes(query)),
    );
  }, [data.rows, search, status]);

  return (
    <>
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <PageHeader
          eyebrow="Stock"
          title="Receiving"
          description="Record physical goods received at FACOLUB. Only confirmation changes stock."
        />
        <div className="flex flex-wrap gap-2">
          <Button asChild variant="outline">
            <Link to="/facolub/receiving/history">
              <History /> {t("Receiving history")}
            </Link>
          </Button>
          <Button asChild size="lg">
            <Link to="/facolub/receiving/new">
              <PackagePlus /> {t("New receiving")}
            </Link>
          </Button>
        </div>
      </div>

      <section className="mb-6 border bg-card p-4 shadow-sm" aria-label={t("Receipt filters")}>
        <div className="grid gap-3 sm:grid-cols-[1fr_190px]">
          <label className="relative">
            <span className="sr-only">{t("Search receipts")}</span>
            <Search className="pointer-events-none absolute left-3 top-3 size-4 text-muted-foreground" />
            <Input
              className="h-10 pl-9"
              placeholder={t("Receipt number, supplier, or reference")}
              value={search}
              onChange={(event) => setSearch(event.target.value)}
            />
          </label>
          <select
            className="h-10 rounded-md border bg-background px-3 text-sm"
            value={status}
            onChange={(event) => setStatus(event.target.value)}
            aria-label={t("Receipt status")}
          >
            <option value="all">{t("All statuses")}</option>
            <option value="draft">{t("Draft")}</option>
            <option value="confirmed">{t("Confirmed")}</option>
            <option value="cancelled">{t("Cancelled")}</option>
          </select>
        </div>
      </section>

      <div className="mb-3 flex items-center justify-between gap-3">
        <h2 className="text-lg font-bold">{t("Recent receipts")}</h2>
        <span className="text-xs font-semibold text-muted-foreground">
          {filtered.length} {t(filtered.length === 1 ? "receipt" : "receipts")}
        </span>
      </div>
      {filtered.length ? (
        <ReceiptCards rows={filtered} />
      ) : (
        <EmptyState
          title="No receipts found"
          description="Create a draft to record the next physical delivery."
          icon={PackagePlus}
        />
      )}
    </>
  );
}
