import { createFileRoute, redirect } from "@tanstack/react-router";
import { LoginPage } from "@/components/app/pages";
export const Route = createFileRoute("/login")({
  beforeLoad: ({ context }) => {
    if (context.auth?.status === "authenticated") throw redirect({ to: "/environments" });
  },
  head: () => ({
    meta: [
      { title: "Sign in — SOMA Lubrifiants" },
      {
        name: "description",
        content: "Secure access to the SOMA Lubrifiants internal management system.",
      },
      { property: "og:title", content: "Sign in — SOMA Lubrifiants" },
      {
        property: "og:description",
        content: "Secure access to the SOMA Lubrifiants internal management system.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: LoginRoute,
});

function LoginRoute() {
  return <LoginPage inactive={Route.useRouteContext().auth?.status === "inactive"} />;
}
