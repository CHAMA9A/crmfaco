import { createFileRoute } from "@tanstack/react-router";

import { OrderDetail } from "@/components/orders/order-detail";
import { getOrderDetailFn } from "@/lib/orders/functions";

export const Route = createFileRoute("/facolub/documents/orders/$orderId/")({
  loader: ({ params }) => getOrderDetailFn({ data: { orderId: params.orderId } }),
  component: OrderDetailRoute,
});

function OrderDetailRoute() {
  return <OrderDetail data={Route.useLoaderData()} />;
}
