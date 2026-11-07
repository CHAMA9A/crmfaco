import { Outlet, createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/facolub/customers/$customerId")({
  component: () => <Outlet />,
});
