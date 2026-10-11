import { createFileRoute } from "@tanstack/react-router";
import { PageHeader } from "@/components/app/facolub-ui";
import { FactoryMissionList } from "@/components/production/factory-missions";
import { ProductionHistory } from "@/components/production/production-history";
import { getFactoryProductionMissionsFn, getProductionHistoryFn } from "@/lib/production/functions";

export const Route = createFileRoute("/facolub/production/")({
  loader: async ({ context }) => {
    const factory =
      context.auth?.status === "authenticated" && context.auth.user.profile.role === "factory";
    return factory
      ? { role: "factory" as const, missions: await getFactoryProductionMissionsFn() }
      : { role: "management" as const, rows: await getProductionHistoryFn() };
  },
  component: ProductionIndexRoute,
});

function ProductionIndexRoute() {
  const data = Route.useLoaderData();
  if (data.role === "management") return <ProductionHistory rows={data.rows} />;
  return (
    <>
      <PageHeader
        eyebrow="Factory"
        title="Production"
        description="Start or resume today’s reserved production missions."
      />
      <FactoryMissionList missions={data.missions} />
    </>
  );
}
