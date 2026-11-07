import { createFileRoute } from "@tanstack/react-router";

import { AdjustmentCenter } from "@/components/stock-counts/adjustment-center";
import { getStockCountWorkspaceFn } from "@/lib/stock-counts/functions";

export const Route = createFileRoute("/facolub/stock/adjustments")({
  loader: () => getStockCountWorkspaceFn(),
  head: () => ({ meta: [{ title: "Stock Adjustments — FACOLUB" }] }),
  component: StockAdjustmentsRoute,
});

function StockAdjustmentsRoute() {
  const data = Route.useLoaderData();
  return <AdjustmentCenter data={data} />;
}
