export type SupabasePublicConfig = { url: string; publishableKey: string; origin: string };

function readEnvValue(...keys: string[]) {
  const env = typeof process !== "undefined" ? process.env : undefined;
  for (const key of keys) {
    const directValue = env?.[key]?.trim();
    if (directValue) return directValue;

    const importMetaValue = import.meta.env?.[key]?.trim();
    if (importMetaValue) return importMetaValue;
  }

  return null;
}

export function getSupabasePublicConfig(): SupabasePublicConfig | null {
  const url = readEnvValue(
    "VITE_SUPABASE_URL",
    "SUPABASE_URL",
    "PUBLIC_SUPABASE_URL",
    "NEXT_PUBLIC_SUPABASE_URL",
  );
  const publishableKey = readEnvValue(
    "VITE_SUPABASE_PUBLISHABLE_KEY",
    "SUPABASE_PUBLISHABLE_KEY",
    "PUBLIC_SUPABASE_PUBLISHABLE_KEY",
    "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
  );

  if (!url || !publishableKey) return null;

  try {
    const parsed = new URL(url);
    if (
      parsed.protocol !== "https:" &&
      parsed.hostname !== "127.0.0.1" &&
      parsed.hostname !== "localhost"
    ) {
      return null;
    }
    return { url: parsed.toString().replace(/\/$/, ""), publishableKey, origin: parsed.origin };
  } catch {
    return null;
  }
}

export function requireSupabasePublicConfig(): SupabasePublicConfig {
  const config = getSupabasePublicConfig();
  if (!config) throw new Error("Supabase public configuration is missing or invalid.");
  return config;
}
