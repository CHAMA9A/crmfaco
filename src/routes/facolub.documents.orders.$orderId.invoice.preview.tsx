import { createFileRoute } from "@tanstack/react-router";
import { OrderInvoice } from "@/components/orders/order-invoice";
import { getInvoiceDocumentFn } from "@/lib/invoices/functions";
import { getOrderDetailFn } from "@/lib/orders/functions";

export const Route = createFileRoute("/facolub/documents/orders/$orderId/invoice/preview")({
  loader: async ({ params }) => {
    const order = await getOrderDetailFn({ data: { orderId: params.orderId } });
    if (!order.invoice) throw new Error("Facture non préparée");
    return getInvoiceDocumentFn({ data: { invoiceId: order.invoice.id } });
  },
  head: () => ({ meta: [{ title: "Aperçu facture — SOMA" }] }),
  component: OrderInvoicePreviewRoute,
});

function OrderInvoicePreviewRoute() {
  return <OrderInvoice invoice={Route.useLoaderData()} printable />;
}
