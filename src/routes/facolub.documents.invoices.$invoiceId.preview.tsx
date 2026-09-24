import { createFileRoute } from "@tanstack/react-router";

import { InvoiceDocument } from "@/components/invoices/invoice-document";
import { getInvoiceDocumentFn } from "@/lib/invoices/functions";

export const Route = createFileRoute("/facolub/documents/invoices/$invoiceId/preview")({
  loader: ({ params }) => getInvoiceDocumentFn({ data: { invoiceId: params.invoiceId } }),
  head: () => ({ meta: [{ title: "Aperçu facture — SOMA Lubrifiants" }] }),
  component: InvoicePreviewRoute,
});

function InvoicePreviewRoute() {
  return <InvoiceDocument invoice={Route.useLoaderData()} printable />;
}
