import { createFileRoute } from "@tanstack/react-router";
import { ShippingDocument } from "@/components/orders/shipping-document";
import { getDeliveryNoteDocumentFn } from "@/lib/orders/functions";

export const Route = createFileRoute("/facolub/documents/orders/$orderId/delivery-note/preview")({
  loader: ({ params }) => getDeliveryNoteDocumentFn({ data: { orderId: params.orderId } }),
  head: () => ({ meta: [{ title: "Aperçu BL — SOMA" }] }),
  component: DeliveryNotePreviewRoute,
});

function DeliveryNotePreviewRoute() {
  return <ShippingDocument kind="delivery" document={Route.useLoaderData()} printable />;
}
