import { createFileRoute } from "@tanstack/react-router";

import { RecoveryCallbackPage } from "@/components/auth/password-recovery";

export const Route = createFileRoute("/auth/callback")({
  validateSearch: (search: Record<string, unknown>) => {
    const code = search["code"];
    return typeof code === "string" ? { code } : {};
  },
  head: () => ({ meta: [{ title: "Verify recovery link — SOMA Lubrifiants" }] }),
  component: RecoveryCallbackRoute,
});

function RecoveryCallbackRoute() {
  return <RecoveryCallbackPage code={Route.useSearch().code} />;
}
