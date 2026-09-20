import { createFileRoute } from "@tanstack/react-router";
import { UsersPage } from "@/components/app/pages";
import { getAdminUsersFn } from "@/lib/auth/functions";
export const Route = createFileRoute("/facolub/users")({
  loader: () => getAdminUsersFn(),
  head: () => ({
    meta: [
      { title: "Users — FACOLUB" },
      { name: "description", content: "Users workspace for FACOLUB internal operations." },
      { property: "og:title", content: "Users — FACOLUB" },
      { property: "og:description", content: "Users workspace for FACOLUB internal operations." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: UsersRoute,
});

function UsersRoute() {
  return <UsersPage users={Route.useLoaderData()} />;
}
