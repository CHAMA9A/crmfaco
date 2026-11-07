import { createFileRoute } from "@tanstack/react-router";
import { CustomerList } from "@/components/customers/customer-list";
import { getCustomersFn } from "@/lib/customers/functions";

export const Route = createFileRoute("/facolub/customers/")({
  loader: () => getCustomersFn(),
  head: () => ({ meta: [{ title: "Clients — FACOLUB" }] }),
  component: CustomersIndexRoute,
});

function CustomersIndexRoute() {
  const data = Route.useLoaderData();
  return <CustomerList initialRows={data.rows} cities={data.cities} />;
}
