import { createFileRoute, redirect } from "@tanstack/react-router";
import { EnvironmentsPage } from "@/components/app/pages";
export const Route = createFileRoute("/environments")({
  beforeLoad: ({ context }) => {
    if (context.auth?.status !== "authenticated") throw redirect({ to: "/login" });
  },
  head: () => ({
    meta: [
      { title: "Select environment — SOMA Lubrifiants" },
      { name: "description", content: "Select a SOMA Lubrifiants operational environment." },
      { property: "og:title", content: "Select environment — SOMA Lubrifiants" },
      { property: "og:description", content: "Select a SOMA Lubrifiants operational environment." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: EnvironmentsRoute,
});

function EnvironmentsRoute() {
  const auth = Route.useRouteContext().auth;
  if (auth?.status !== "authenticated") return null;
  return <EnvironmentsPage user={auth.user} />;
}
