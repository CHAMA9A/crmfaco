import { createFileRoute } from "@tanstack/react-router";
import { PreparationHistory } from "@/components/preparation/preparation-history";
import { getPreparationHistoryFn } from "@/lib/preparation/functions";

export const Route = createFileRoute("/facolub/preparation/history")({
  loader: () => getPreparationHistoryFn(),
  component: PreparationHistoryRoute,
});
function PreparationHistoryRoute() {
  return <PreparationHistory data={Route.useLoaderData()} />;
}
