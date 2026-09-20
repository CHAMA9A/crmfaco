import { createStart, createCsrfMiddleware, createMiddleware } from "@tanstack/react-start";

import { renderErrorPage } from "./lib/error-page";
import { reportServerError } from "./lib/error-capture";
import { getSupabasePublicConfig } from "./lib/supabase/config";

function securityHeaders() {
  const supabaseOrigin = getSupabasePublicConfig()?.origin;
  const realtimeOrigin = supabaseOrigin?.replace(/^http/, "ws");
  const connectSources = ["'self'", supabaseOrigin, realtimeOrigin].filter(Boolean).join(" ");
  return {
    "content-security-policy": [
      "default-src 'self'",
      "base-uri 'self'",
      `connect-src ${connectSources}`,
      "font-src 'self' https://fonts.gstatic.com data:",
      "form-action 'self'",
      "frame-ancestors 'none'",
      "img-src 'self' data: blob:",
      "object-src 'none'",
      "script-src 'self' 'unsafe-inline'",
      "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
    ].join("; "),
    "permissions-policy": "camera=(), geolocation=(), microphone=()",
    "referrer-policy": "strict-origin-when-cross-origin",
    "x-content-type-options": "nosniff",
    "x-frame-options": "DENY",
  } as const;
}

function applySecurityHeaders(headers: Headers) {
  for (const [name, value] of Object.entries(securityHeaders())) {
    headers.set(name, value);
  }
}

const securityHeadersMiddleware = createMiddleware().server(async ({ next }) => {
  const result = await next();
  if (result instanceof Response) {
    applySecurityHeaders(result.headers);
  } else {
    applySecurityHeaders(result.response.headers);
  }
  return result;
});

const errorMiddleware = createMiddleware().server(async ({ next }) => {
  try {
    return await next();
  } catch (error) {
    if (error != null && typeof error === "object" && "statusCode" in error) {
      throw error;
    }
    reportServerError(error);
    const response = new Response(renderErrorPage(), {
      status: 500,
      headers: { "content-type": "text/html; charset=utf-8" },
    });
    applySecurityHeaders(response.headers);
    return response;
  }
});

// Start installs this automatically when src/start.ts is absent; defining the
// file opts out, so re-add it explicitly to keep server functions protected
// from cross-site requests.
const csrfMiddleware = createCsrfMiddleware({
  filter: (ctx) => ctx.handlerType === "serverFn",
});

export const startInstance = createStart(() => ({
  requestMiddleware: [securityHeadersMiddleware, errorMiddleware, csrfMiddleware],
}));
