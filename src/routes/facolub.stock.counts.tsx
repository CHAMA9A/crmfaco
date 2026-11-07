import { Outlet, createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/facolub/stock/counts")({
  head: () => ({ meta: [{ title: "Physical Stock Counts — FACOLUB" }] }),
  component: () => <Outlet />,
});
