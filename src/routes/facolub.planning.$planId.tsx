import { createFileRoute } from "@tanstack/react-router";
import { PlanningDetailView } from "@/components/planning/planning-detail";
import { getPlanningDetailFn } from "@/lib/planning/functions";

export const Route = createFileRoute("/facolub/planning/$planId")({
  loader: ({ params }) => getPlanningDetailFn({ data: { planId: params.planId } }),
  component: PlanningDetailRoute,
});
function PlanningDetailRoute() {
  return <PlanningDetailView data={Route.useLoaderData()} />;
}
