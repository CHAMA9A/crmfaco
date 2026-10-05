import { Outlet, createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/facolub/documents/orders/$orderId/delivery-note")({
  head: () => ({ meta: [{ title: "Bon de livraison — FACOLUB" }] }),
  component: DeliveryNoteLayout,
});

function DeliveryNoteLayout() {
  return <Outlet />;
}
