import { createFileRoute } from "@tanstack/react-router";
import { OrderForm } from "@/components/orders/order-form";
import { getOrderEditorDataFn } from "@/lib/orders/functions";

type NewOrderSearch = { customerId?: string };

export const Route = createFileRoute("/facolub/documents/orders/new")({
  validateSearch: (search: Record<string, unknown>): NewOrderSearch =>
    typeof search["customerId"] === "string" ? { customerId: search["customerId"] } : {},
  loader: () => getOrderEditorDataFn(),
  head: () => ({ meta: [{ title: "Nouvelle commande — FACOLUB" }] }),
  component: NewOrderRoute,
});

function NewOrderRoute() {
  const customerId = Route.useSearch().customerId;
  return (
    <OrderForm
      data={Route.useLoaderData()}
      {...(customerId ? { selectedCustomerId: customerId } : {})}
    />
  );
}
