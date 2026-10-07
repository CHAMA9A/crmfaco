import { createFileRoute } from "@tanstack/react-router";

import { ReceiptDetailView } from "@/components/receiving/receipt-detail";
import { getReceiptDetailFn } from "@/lib/receiving/functions";

export const Route = createFileRoute("/facolub/receiving/$receiptId")({
  loader: ({ params }) => getReceiptDetailFn({ data: { receiptId: params.receiptId } }),
  head: () => ({ meta: [{ title: "Receiving Detail — FACOLUB" }] }),
  component: ReceiptDetailRoute,
});

function ReceiptDetailRoute() {
  return <ReceiptDetailView data={Route.useLoaderData()} />;
}
