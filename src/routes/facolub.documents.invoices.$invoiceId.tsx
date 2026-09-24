import { createFileRoute } from "@tanstack/react-router";

import { InvoiceDocument } from "@/components/invoices/invoice-document";
import { getInvoiceDocumentFn } from "@/lib/invoices/functions";

export const Route = createFileRoute("/facolub/documents/invoices/$invoiceId")({
  loader: ({ params }) => getInvoiceDocumentFn({ data: { invoiceId: params.invoiceId } }),
  head: () => ({ meta: [{ title: "Facture — FACOLUB" }] }),
  component: InvoiceDetailRoute,
});

function InvoiceDetailRoute() {
  return <InvoiceDocument invoice={Route.useLoaderData()} />;
}
