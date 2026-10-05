import { Outlet, createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/facolub/documents/invoices/$invoiceId")({
  head: () => ({ meta: [{ title: "Facture — FACOLUB" }] }),
  component: InvoiceLayout,
});

function InvoiceLayout() {
  return <Outlet />;
}
