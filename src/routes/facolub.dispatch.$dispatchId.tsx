import { createFileRoute } from "@tanstack/react-router";
import { DispatchDetailView } from "@/components/dispatch/dispatch-detail";
import { getDispatchDetailFn } from "@/lib/dispatch/functions";
export const Route = createFileRoute("/facolub/dispatch/$dispatchId")({
  loader: ({ params }) => getDispatchDetailFn({ data: { dispatchId: params.dispatchId } }),
  component: DispatchDetailRoute,
});

function DispatchDetailRoute() {
  return <DispatchDetailView data={Route.useLoaderData()} />;
}
