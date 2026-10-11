import { createFileRoute } from "@tanstack/react-router";
import { PlanningAdmin } from "@/components/planning/planning-admin";
import { getPlanningAdminDataFn } from "@/lib/planning/functions";

export const Route = createFileRoute("/facolub/settings/production-planning")({
  loader: () => getPlanningAdminDataFn(),
  component: PlanningSettingsRoute,
});
function PlanningSettingsRoute() {
  return <PlanningAdmin data={Route.useLoaderData()} />;
}
