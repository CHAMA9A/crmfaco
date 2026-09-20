import { createBrowserClient } from "@supabase/ssr";
import type { SupabaseClient } from "@supabase/supabase-js";

import { requireSupabasePublicConfig } from "./config";
import type { Database } from "@/types/database";

let browserClient: SupabaseClient<Database> | undefined;

export function getSupabaseBrowserClient() {
  if (!browserClient) {
    const { url, publishableKey } = requireSupabasePublicConfig();
    browserClient = createBrowserClient<Database>(url, publishableKey, {
      cookieOptions: { secure: import.meta.env.PROD },
    });
  }
  return browserClient;
}
