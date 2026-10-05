import { Outlet, createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/facolub/documents/orders/$orderId/invoice")({
  head: () => ({ meta: [{ title: "Facture de commande — FACOLUB" }] }),
  component: OrderInvoiceLayout,
});

function OrderInvoiceLayout() {
  return <Outlet />;
}
