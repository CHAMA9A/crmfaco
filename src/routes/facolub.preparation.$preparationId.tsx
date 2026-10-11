import { createFileRoute } from "@tanstack/react-router";
import { PreparationDetailView } from "@/components/preparation/preparation-detail";
import { getPreparationDetailFn } from "@/lib/preparation/functions";

export const Route = createFileRoute("/facolub/preparation/$preparationId")({
  loader: ({ params }) => getPreparationDetailFn({ data: { preparationId: params.preparationId } }),
  component: PreparationDetailRoute,
});
function PreparationDetailRoute() {
  return <PreparationDetailView data={Route.useLoaderData()} />;
}
