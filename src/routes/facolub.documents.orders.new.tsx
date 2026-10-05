import { createFileRoute } from "@tanstack/react-router";
import { OrderForm } from "@/components/orders/order-form";
import { getOrderEditorDataFn } from "@/lib/orders/functions";

export const Route = createFileRoute("/facolub/documents/orders/new")({
  loader: () => getOrderEditorDataFn(),
  head: () => ({ meta: [{ title: "Nouvelle commande — FACOLUB" }] }),
  component: NewOrderRoute,
});

function NewOrderRoute() {
  return <OrderForm data={Route.useLoaderData()} />;
}
