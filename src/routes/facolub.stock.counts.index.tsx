import { createFileRoute } from "@tanstack/react-router";

import { StockCountList } from "@/components/stock-counts/count-list";
import { getStockCountWorkspaceFn } from "@/lib/stock-counts/functions";

export const Route = createFileRoute("/facolub/stock/counts/")({
  loader: () => getStockCountWorkspaceFn(),
  component: StockCountsRoute,
});

function StockCountsRoute() {
  const data = Route.useLoaderData();
  return (
    <StockCountList
      rows={data.counts}
      pendingAdjustments={data.adjustments.filter((row) => row.status === "pending").length}
    />
  );
}
