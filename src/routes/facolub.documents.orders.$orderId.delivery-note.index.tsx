import { createFileRoute } from "@tanstack/react-router";

import { ShippingDocument } from "@/components/orders/shipping-document";
import { getDeliveryNoteDocumentFn } from "@/lib/orders/functions";

export const Route = createFileRoute("/facolub/documents/orders/$orderId/delivery-note/")({
  loader: ({ params }) => getDeliveryNoteDocumentFn({ data: { orderId: params.orderId } }),
  component: DeliveryNoteRoute,
});

function DeliveryNoteRoute() {
  return <ShippingDocument kind="delivery" document={Route.useLoaderData()} />;
}
