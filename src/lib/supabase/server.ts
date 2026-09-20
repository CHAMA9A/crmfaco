import {
  createServerClient,
  parseCookieHeader,
  serializeCookieHeader,
  type CookieOptions,
} from "@supabase/ssr";
import { getRequestHeader, setResponseHeader } from "@tanstack/react-start/server";

import { requireSupabasePublicConfig } from "./config";
import type { Database } from "@/types/database";

export function getSupabaseServerClient() {
  const { url, publishableKey } = requireSupabasePublicConfig();
  return createServerClient<Database>(url, publishableKey, {
    cookieOptions: { secure: import.meta.env.PROD },
    cookies: {
      getAll() {
        return parseCookieHeader(getRequestHeader("cookie") ?? "").map(({ name, value }) => ({
          name,
          value: value ?? "",
        }));
      },
      setAll(cookies, headers) {
        setResponseHeader(
          "Set-Cookie",
          cookies.map(({ name, value, options }) =>
            serializeCookieHeader(name, value, options as CookieOptions),
          ),
        );
        for (const [name, value] of Object.entries(headers)) setResponseHeader(name, value);
      },
    },
  });
}
