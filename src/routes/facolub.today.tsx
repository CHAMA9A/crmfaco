import { createFileRoute } from "@tanstack/react-router";
import { TodayPage } from "@/components/app/pages";
import { getFactoryProductionMissionsFn } from "@/lib/production/functions";
export const Route = createFileRoute("/facolub/today")({
  head: () => ({
    meta: [
      { title: "Today — FACOLUB" },
      { name: "description", content: "Today’s FACOLUB factory missions and priorities." },
      { property: "og:title", content: "Today — FACOLUB" },
      { property: "og:description", content: "Today’s FACOLUB factory missions and priorities." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  loader: ({ context }) =>
    context.auth?.status === "authenticated" && context.auth.user.profile.role === "factory"
      ? getFactoryProductionMissionsFn()
      : [],
  component: TodayRoute,
});
function TodayRoute() {
  return <TodayPage productionMissions={Route.useLoaderData()} />;
}
