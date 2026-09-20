import { createServerFn } from "@tanstack/react-start";
import { getRequestUrl, setResponseHeader } from "@tanstack/react-start/server";
import { z } from "zod";

import { getSupabasePublicConfig } from "@/lib/supabase/config";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import type { AdminUserSummary, AuthState, Environment, Profile } from "@/types/auth";

const loginSchema = z.object({
  email: z.string().trim().email().max(254),
  password: z.string().min(1).max(512),
});

const passwordResetRequestSchema = z.object({
  email: z.string().trim().email().max(254),
});

const recoveryCodeSchema = z.object({
  code: z.string().trim().min(1).max(2048),
});

const newPasswordSchema = z.object({
  password: z.string().min(12).max(128),
});

function privateResponse() {
  setResponseHeader("Cache-Control", "private, no-store");
  setResponseHeader("Vary", "Cookie, Authorization");
}

async function resolveAuthState(): Promise<AuthState> {
  privateResponse();
  if (!getSupabasePublicConfig())
    return { status: "anonymous", user: null, reason: "unconfigured" };

  const supabase = getSupabaseServerClient();
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return { status: "anonymous", user: null };

  const { data: profileData, error: profileError } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", userData.user.id)
    .maybeSingle();
  const profile = profileData as Profile | null;
  if (profileError || !profile) return { status: "anonymous", user: null };

  const identity = { id: userData.user.id, email: userData.user.email ?? null };
  if (!profile.is_active) return { status: "inactive", user: identity, profile };

  const { data: environmentData, error: environmentError } = await supabase
    .from("environments")
    .select("*")
    .eq("is_active", true)
    .order("name");
  const environments = (environmentError ? [] : environmentData) as Environment[];

  return {
    status: "authenticated",
    user: { ...identity, profile, environments },
  };
}

export const getAuthStateFn = createServerFn({ method: "GET" }).handler(resolveAuthState);

export const signInFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => loginSchema.parse(input))
  .handler(async ({ data }) => {
    privateResponse();
    if (!getSupabasePublicConfig()) {
      return { ok: false as const, code: "unavailable" as const };
    }

    const supabase = getSupabaseServerClient();
    const { data: authData, error } = await supabase.auth.signInWithPassword(data);
    if (error || !authData.user) {
      console.warn("Supabase sign-in rejected", {
        code: error?.code ?? "missing_user",
        status: error?.status ?? null,
      });
      return { ok: false as const, code: "invalid" as const };
    }

    const { data: profileData } = await supabase
      .from("profiles")
      .select("*")
      .eq("id", authData.user.id)
      .maybeSingle();
    const profile = profileData as Profile | null;
    if (!profile?.is_active) {
      await supabase.auth.signOut({ scope: "local" });
      return { ok: false as const, code: profile ? ("inactive" as const) : ("invalid" as const) };
    }

    return { ok: true as const };
  });

export const signOutFn = createServerFn({ method: "POST" }).handler(async () => {
  privateResponse();
  if (getSupabasePublicConfig()) {
    const supabase = getSupabaseServerClient();
    await supabase.auth.signOut({ scope: "local" });
  }
  return { ok: true as const };
});

export const requestPasswordResetFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => passwordResetRequestSchema.parse(input))
  .handler(async ({ data }) => {
    privateResponse();
    if (!getSupabasePublicConfig()) return { ok: true as const };

    const requestUrl = getRequestUrl();
    const redirectTo = new URL("/auth/callback?next=/reset-password", requestUrl.origin).toString();
    const supabase = getSupabaseServerClient();
    const { error } = await supabase.auth.resetPasswordForEmail(data.email, { redirectTo });
    if (error) {
      console.warn("Supabase password-reset request rejected", {
        code: error.code,
        status: error.status,
      });
    }

    // Keep the response identical whether or not the account exists.
    return { ok: true as const };
  });

export const exchangeRecoveryCodeFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => recoveryCodeSchema.parse(input))
  .handler(async ({ data }) => {
    privateResponse();
    if (!getSupabasePublicConfig()) return { ok: false as const };

    const supabase = getSupabaseServerClient();
    const { error } = await supabase.auth.exchangeCodeForSession(data.code);
    return { ok: !error } as const;
  });

export const updateRecoveredPasswordFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => newPasswordSchema.parse(input))
  .handler(async ({ data }) => {
    privateResponse();
    if (!getSupabasePublicConfig()) return { ok: false as const };

    const supabase = getSupabaseServerClient();
    const { data: userData, error: userError } = await supabase.auth.getUser();
    if (userError || !userData.user) return { ok: false as const };

    const { error } = await supabase.auth.updateUser({ password: data.password });
    if (error) return { ok: false as const };

    await supabase.auth.signOut({ scope: "local" });
    return { ok: true as const };
  });

export const getAdminUsersFn = createServerFn({ method: "GET" }).handler(async () => {
  const auth = await resolveAuthState();
  if (auth.status !== "authenticated" || auth.user.profile.role !== "admin") {
    throw new Error("Forbidden");
  }

  const supabase = getSupabaseServerClient();
  const [{ data: profiles, error: profileError }, { data: environments, error: environmentError }] =
    await Promise.all([
      supabase.from("profiles").select("*").order("display_name"),
      supabase.from("environments").select("id, code").eq("code", "FACOLUB").maybeSingle(),
    ]);
  if (profileError || environmentError) throw new Error("Unable to load user access.");

  const environmentId = environments?.id;
  const { data: memberships, error: membershipError } = environmentId
    ? await supabase.from("user_environment_access").select("*").eq("environment_id", environmentId)
    : { data: [], error: null };
  if (membershipError) throw new Error("Unable to load user access.");

  const membershipByUser = new Map((memberships ?? []).map((item) => [item.user_id, item]));
  return (profiles ?? []).map((profile): AdminUserSummary => ({
    profile: profile as Profile,
    facolubAccess: membershipByUser.get(profile.id) ?? null,
  }));
});
