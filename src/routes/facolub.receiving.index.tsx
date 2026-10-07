import { createFileRoute } from "@tanstack/react-router";

import { ReceivingHome } from "@/components/receiving/receiving-home";
import { getReceivingHomeFn } from "@/lib/receiving/functions";

export const Route = createFileRoute("/facolub/receiving/")({
  loader: () => getReceivingHomeFn(),
  component: ReceivingHomeRoute,
});

function ReceivingHomeRoute() {
  return <ReceivingHome data={Route.useLoaderData()} />;
}
