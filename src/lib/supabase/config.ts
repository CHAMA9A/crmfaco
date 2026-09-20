export type SupabasePublicConfig = { url: string; publishableKey: string; origin: string };

export function getSupabasePublicConfig(): SupabasePublicConfig | null {
  const url = import.meta.env["VITE_SUPABASE_URL"]?.trim();
  const publishableKey = import.meta.env["VITE_SUPABASE_PUBLISHABLE_KEY"]?.trim();
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
