import { createFileRoute } from "@tanstack/react-router";

import { OrderWorkspace } from "@/components/orders/order-workspace";
import { getOrdersWorkspaceFn } from "@/lib/orders/functions";

export const Route = createFileRoute("/facolub/documents/")({
  loader: () => getOrdersWorkspaceFn(),
  component: DocumentsIndexRoute,
});

function DocumentsIndexRoute() {
  return <OrderWorkspace data={Route.useLoaderData()} />;
}
