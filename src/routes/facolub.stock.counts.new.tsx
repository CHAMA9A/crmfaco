import { createFileRoute } from "@tanstack/react-router";

import { StockCountForm } from "@/components/stock-counts/count-form";
import { getNewStockCountDataFn } from "@/lib/stock-counts/functions";

export const Route = createFileRoute("/facolub/stock/counts/new")({
  loader: () => getNewStockCountDataFn(),
  head: () => ({ meta: [{ title: "New Physical Count — FACOLUB" }] }),
  component: NewStockCountRoute,
});

function NewStockCountRoute() {
  return <StockCountForm data={Route.useLoaderData()} />;
}
