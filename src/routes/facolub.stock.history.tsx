import { createFileRoute } from "@tanstack/react-router";

import { StockHistory } from "@/components/stock/stock-history";
import { getStockHistoryFn } from "@/lib/stock/functions";

export const Route = createFileRoute("/facolub/stock/history")({
  loader: () => getStockHistoryFn({ data: {} }),
  head: () => ({ meta: [{ title: "Stock Movement History — FACOLUB" }] }),
  component: StockHistoryRoute,
});

function StockHistoryRoute() {
  return <StockHistory data={Route.useLoaderData()} />;
}
