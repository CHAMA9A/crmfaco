import { createFileRoute } from "@tanstack/react-router";

import { SupplierAdmin } from "@/components/receiving/supplier-admin";
import { getSuppliersForAdminFn } from "@/lib/receiving/functions";

export const Route = createFileRoute("/facolub/settings/suppliers")({
  loader: () => getSuppliersForAdminFn(),
  head: () => ({ meta: [{ title: "Suppliers — FACOLUB" }] }),
  component: SuppliersRoute,
});

function SuppliersRoute() {
  return <SupplierAdmin data={Route.useLoaderData()} />;
}
