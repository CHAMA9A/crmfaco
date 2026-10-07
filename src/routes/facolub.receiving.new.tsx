import { createFileRoute } from "@tanstack/react-router";

import { ReceiptForm } from "@/components/receiving/receipt-form";
import { getReceiptEditorDataFn } from "@/lib/receiving/functions";

type NewReceiptSearch = { receiptId?: string };

export const Route = createFileRoute("/facolub/receiving/new")({
  validateSearch: (search: Record<string, unknown>): NewReceiptSearch =>
    typeof search["receiptId"] === "string" ? { receiptId: search["receiptId"] } : {},
  loaderDeps: ({ search }) => ({ receiptId: search.receiptId ?? null }),
  loader: ({ deps }) => getReceiptEditorDataFn({ data: deps }),
  head: () => ({ meta: [{ title: "New Receiving — FACOLUB" }] }),
  component: NewReceiptRoute,
});

function NewReceiptRoute() {
  return <ReceiptForm data={Route.useLoaderData()} />;
}
