import { createFileRoute } from "@tanstack/react-router";
import { PreparationHome } from "@/components/preparation/preparation-home";
import { getPreparationHomeFn } from "@/lib/preparation/functions";

export const Route = createFileRoute("/facolub/preparation/")({
  loader: () => getPreparationHomeFn(),
  component: PreparationHomeRoute,
});
function PreparationHomeRoute() {
  return <PreparationHome rows={Route.useLoaderData().rows} />;
}
