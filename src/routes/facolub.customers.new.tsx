import { createFileRoute } from "@tanstack/react-router";
import { CustomerForm } from "@/components/customers/customer-form";

export const Route = createFileRoute("/facolub/customers/new")({
  head: () => ({ meta: [{ title: "Nouveau client — FACOLUB" }] }),
  component: () => <CustomerForm />,
});
