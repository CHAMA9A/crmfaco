import { createFileRoute } from "@tanstack/react-router";
import { PreparationForm } from "@/components/preparation/preparation-form";
import { getPreparationEditorDataFn } from "@/lib/preparation/functions";

type Search = { preparationId?: string };
export const Route = createFileRoute("/facolub/preparation/new")({
  validateSearch: (search: Record<string, unknown>): Search =>
    typeof search["preparationId"] === "string" ? { preparationId: search["preparationId"] } : {},
  loaderDeps: ({ search }) => ({ preparationId: search.preparationId ?? null }),
  loader: ({ deps }) => getPreparationEditorDataFn({ data: deps }),
  component: PreparationNewRoute,
});
function PreparationNewRoute() {
  return <PreparationForm data={Route.useLoaderData()} />;
}
