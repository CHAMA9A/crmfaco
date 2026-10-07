import { createFileRoute } from "@tanstack/react-router";

import { StockItemAdmin } from "@/components/stock/stock-item-admin";
import { getStockItemsForAdminFn } from "@/lib/stock/functions";

export const Route = createFileRoute("/facolub/settings/stock-items")({
  loader: () => getStockItemsForAdminFn(),
  head: () => ({ meta: [{ title: "Stock Items — FACOLUB" }] }),
  component: StockItemsRoute,
});

function StockItemsRoute() {
  return <StockItemAdmin data={Route.useLoaderData()} />;
}
