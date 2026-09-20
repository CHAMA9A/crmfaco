import { createFileRoute } from "@tanstack/react-router";

import { ForgotPasswordPage } from "@/components/auth/password-recovery";

export const Route = createFileRoute("/forgot-password")({
  head: () => ({ meta: [{ title: "Reset password — SOMA Lubrifiants" }] }),
  component: ForgotPasswordPage,
});
