import { createFileRoute } from "@tanstack/react-router";

import { ResetPasswordPage } from "@/components/auth/password-recovery";

export const Route = createFileRoute("/reset-password")({
  head: () => ({ meta: [{ title: "Choose a new password — SOMA Lubrifiants" }] }),
  component: ResetPasswordPage,
});
