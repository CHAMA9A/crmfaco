import { createFileRoute } from "@tanstack/react-router";
import { DispatchMissions } from "@/components/dispatch/dispatch-missions";
import { getDispatchMissionsFn } from "@/lib/dispatch/functions";
export const Route = createFileRoute("/facolub/dispatch/")({
  loader: () => getDispatchMissionsFn(),
  component: DispatchIndexRoute,
});

function DispatchIndexRoute() {
  return <DispatchMissions data={Route.useLoaderData()} />;
}
