import { createFileRoute } from "@tanstack/react-router";

import { ShippingDocument } from "@/components/orders/shipping-document";
import { getTransportNoteDocumentFn } from "@/lib/orders/functions";

export const Route = createFileRoute("/facolub/documents/orders/$orderId/transport-note/")({
  loader: ({ params }) => getTransportNoteDocumentFn({ data: { orderId: params.orderId } }),
  component: TransportNoteRoute,
});

function TransportNoteRoute() {
  return <ShippingDocument kind="transport" document={Route.useLoaderData()} />;
}
