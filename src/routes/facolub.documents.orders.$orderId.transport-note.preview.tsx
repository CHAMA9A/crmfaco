import { createFileRoute } from "@tanstack/react-router";
import { ShippingDocument } from "@/components/orders/shipping-document";
import { getTransportNoteDocumentFn } from "@/lib/orders/functions";

export const Route = createFileRoute("/facolub/documents/orders/$orderId/transport-note/preview")({
  loader: ({ params }) => getTransportNoteDocumentFn({ data: { orderId: params.orderId } }),
  head: () => ({ meta: [{ title: "Aperçu BT — SOMA" }] }),
  component: TransportNotePreviewRoute,
});

function TransportNotePreviewRoute() {
  return <ShippingDocument kind="transport" document={Route.useLoaderData()} printable />;
}
