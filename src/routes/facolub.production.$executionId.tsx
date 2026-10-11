import { createFileRoute } from "@tanstack/react-router";
import { ProductionDetail } from "@/components/production/production-detail";
import { getProductionExecutionFn } from "@/lib/production/functions";

export const Route = createFileRoute("/facolub/production/$executionId")({
  loader: ({ params }) => getProductionExecutionFn({ data: { executionId: params.executionId } }),
  component: ProductionExecutionRoute,
});

function ProductionExecutionRoute() {
  return <ProductionDetail data={Route.useLoaderData()} />;
}
