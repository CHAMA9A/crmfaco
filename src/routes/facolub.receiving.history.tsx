import { createFileRoute } from "@tanstack/react-router";

import { ReceivingHistory } from "@/components/receiving/receiving-history";
import { getReceivingHistoryFn } from "@/lib/receiving/functions";

export const Route = createFileRoute("/facolub/receiving/history")({
  loader: () => getReceivingHistoryFn(),
  head: () => ({ meta: [{ title: "Receiving History — FACOLUB" }] }),
  component: ReceivingHistoryRoute,
});

function ReceivingHistoryRoute() {
  return <ReceivingHistory data={Route.useLoaderData()} />;
}
