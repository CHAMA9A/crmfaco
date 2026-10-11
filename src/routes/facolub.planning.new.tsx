import { createFileRoute } from "@tanstack/react-router";
import { PlanningForm } from "@/components/planning/planning-form";
import { getPlanningEditorDataFn } from "@/lib/planning/functions";

type Search = { planId?: string };
export const Route = createFileRoute("/facolub/planning/new")({
  validateSearch: (search: Record<string, unknown>): Search =>
    typeof search["planId"] === "string" ? { planId: search["planId"] } : {},
  loaderDeps: ({ search }) => ({ planId: search.planId ?? null }),
  loader: ({ deps }) => getPlanningEditorDataFn({ data: deps }),
  component: PlanningNewRoute,
});
function PlanningNewRoute() {
  return <PlanningForm data={Route.useLoaderData()} />;
}
