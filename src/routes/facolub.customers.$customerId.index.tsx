import { createFileRoute } from "@tanstack/react-router";
import { CustomerDetail } from "@/components/customers/customer-detail";
import { getCustomerFn } from "@/lib/customers/functions";

export const Route = createFileRoute("/facolub/customers/$customerId/")({
  loader: ({ params }) => getCustomerFn({ data: { customerId: params.customerId } }),
  head: () => ({ meta: [{ title: "Fiche client — FACOLUB" }] }),
  component: CustomerDetailRoute,
});

function CustomerDetailRoute() {
  return <CustomerDetail data={Route.useLoaderData()} />;
}
