import { Outlet, createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/facolub/documents/orders/$orderId")({
  head: () => ({ meta: [{ title: "Commande — FACOLUB" }] }),
  component: OrderLayout,
});

function OrderLayout() {
  return <Outlet />;
}
