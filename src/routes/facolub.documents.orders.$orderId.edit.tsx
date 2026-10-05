import { createFileRoute } from "@tanstack/react-router";
import { OrderForm } from "@/components/orders/order-form";
import { getDraftOrderEditorFn } from "@/lib/orders/functions";

export const Route = createFileRoute("/facolub/documents/orders/$orderId/edit")({
  loader: ({ params }) => getDraftOrderEditorFn({ data: { orderId: params.orderId } }),
  head: () => ({ meta: [{ title: "Modifier la commande — FACOLUB" }] }),
  component: EditOrderRoute,
});

function EditOrderRoute() {
  return <OrderForm data={Route.useLoaderData()} />;
}
