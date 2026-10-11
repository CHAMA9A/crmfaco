import { createFileRoute } from "@tanstack/react-router";
import { PlanningHome } from "@/components/planning/planning-home";
import { getPlanningHomeFn } from "@/lib/planning/functions";

export const Route = createFileRoute("/facolub/planning/")({
  loader: () => getPlanningHomeFn(),
  component: PlanningIndexRoute,
});
function PlanningIndexRoute() {
  return <PlanningHome {...Route.useLoaderData()} />;
}
