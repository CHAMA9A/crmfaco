import { createFileRoute } from "@tanstack/react-router";

import { StockOverview } from "@/components/stock/stock-overview";
import { getStockOverviewFn } from "@/lib/stock/functions";

export const Route = createFileRoute("/facolub/stock/")({
  loader: () => getStockOverviewFn(),
  component: StockOverviewRoute,
});

function StockOverviewRoute() {
  return <StockOverview data={Route.useLoaderData()} />;
}
