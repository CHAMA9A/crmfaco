import { createFileRoute } from "@tanstack/react-router";
import { DispatchHistory } from "@/components/dispatch/dispatch-history";
import { getDispatchHistoryFn } from "@/lib/dispatch/functions";
export const Route = createFileRoute("/facolub/dispatch/history")({
  loader: () => getDispatchHistoryFn(),
  component: DispatchHistoryRoute,
});

function DispatchHistoryRoute() {
  return <DispatchHistory rows={Route.useLoaderData()} />;
}
