import { Outlet, createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/facolub/documents/orders/$orderId/transport-note")({
  head: () => ({ meta: [{ title: "Bon de transport — FACOLUB" }] }),
  component: TransportNoteLayout,
});

function TransportNoteLayout() {
  return <Outlet />;
}
