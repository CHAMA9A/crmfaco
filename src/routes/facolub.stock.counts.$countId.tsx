import { createFileRoute } from "@tanstack/react-router";

import { StockCountDetailView } from "@/components/stock-counts/count-detail";
import { getStockCountFn } from "@/lib/stock-counts/functions";

export const Route = createFileRoute("/facolub/stock/counts/$countId")({
  loader: ({ params }) => getStockCountFn({ data: { countId: params.countId } }),
  head: () => ({ meta: [{ title: "Stock Count — FACOLUB" }] }),
  component: StockCountDetailRoute,
});

function StockCountDetailRoute() {
  return <StockCountDetailView data={Route.useLoaderData()} />;
}
