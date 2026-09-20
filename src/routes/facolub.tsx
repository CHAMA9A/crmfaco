import { Outlet, createFileRoute, redirect } from "@tanstack/react-router";
import { FacolubShell } from "@/components/app/facolub-ui";
import { AuthProvider } from "@/lib/auth/context";
import { canAccessFacolubPath, defaultFacolubPath } from "@/lib/auth/authorization";

export const Route = createFileRoute("/facolub")({
  beforeLoad: ({ context, location }) => {
    if (context.auth?.status !== "authenticated") throw redirect({ to: "/login" });
    const { profile, environments } = context.auth.user;
    if (!environments.some((environment) => environment.code === "FACOLUB")) {
      throw redirect({ to: "/environments" });
    }
    if (profile.role === "factory" && location.pathname.replace(/\/$/, "") === "/facolub") {
      throw redirect({ to: "/facolub/today" });
    }
    if (!canAccessFacolubPath(profile.role, location.pathname)) {
      throw redirect({ href: defaultFacolubPath(profile.role) });
    }
  },
  component: FacolubRoute,
});

function FacolubRoute() {
  const auth = Route.useRouteContext().auth;
  if (auth?.status !== "authenticated") return null;
  return (
    <AuthProvider user={auth.user}>
      <FacolubShell>
        <Outlet />
      </FacolubShell>
    </AuthProvider>
  );
}
