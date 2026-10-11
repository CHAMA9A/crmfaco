import { Outlet, createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/facolub/preparation")({
  head: () => ({ meta: [{ title: "Prepared Bottles — FACOLUB" }] }),
  component: () => <Outlet />,
});
