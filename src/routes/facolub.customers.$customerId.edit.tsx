import { createFileRoute } from "@tanstack/react-router";
import { CustomerForm } from "@/components/customers/customer-form";
import { getCustomerFn } from "@/lib/customers/functions";

export const Route = createFileRoute("/facolub/customers/$customerId/edit")({
  loader: ({ params }) => getCustomerFn({ data: { customerId: params.customerId } }),
  head: () => ({ meta: [{ title: "Modifier le client — FACOLUB" }] }),
  component: EditCustomerRoute,
});

function EditCustomerRoute() {
  return <CustomerForm customer={Route.useLoaderData().customer} />;
}
