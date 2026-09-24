import { describe, expect, test } from "bun:test";

import { getSupabasePublicConfig } from "@/lib/supabase/config";
import { canAccessFacolubPath, defaultFacolubPath } from "./authorization";

const allRoutes = [
  "/facolub",
  "/facolub/today",
  "/facolub/stock",
  "/facolub/receiving",
  "/facolub/planning",
  "/facolub/production",
  "/facolub/dispatch",
  "/facolub/documents",
  "/facolub/customers",
  "/facolub/prices",
  "/facolub/purchases",
  "/facolub/costs",
  "/facolub/analytics",
  "/facolub/history",
  "/facolub/problems",
  "/facolub/settings",
  "/facolub/users",
];

describe("FACOLUB authorization matrix", () => {
  test("admin can access every FACOLUB route", () => {
    for (const route of allRoutes) expect(canAccessFacolubPath("admin", route)).toBe(true);
  });

  test("management is denied only settings and users", () => {
    for (const route of allRoutes) {
      expect(canAccessFacolubPath("management", route)).toBe(
        route !== "/facolub/settings" && route !== "/facolub/users",
      );
    }
  });

  test("factory is limited to the operational route set", () => {
    const allowed = new Set([
      "/facolub/today",
      "/facolub/stock",
      "/facolub/receiving",
      "/facolub/planning",
      "/facolub/production",
      "/facolub/dispatch",
      "/facolub/history",
      "/facolub/problems",
    ]);
    for (const route of allRoutes)
      expect(canAccessFacolubPath("factory", route)).toBe(allowed.has(route));
  });

  test("unknown paths fail closed for every role", () => {
    expect(canAccessFacolubPath("admin", "/facolub/not-real")).toBe(false);
    expect(canAccessFacolubPath("factory", "/facolub/not-real")).toBe(false);
    expect(canAccessFacolubPath("management", "/facolub/not-real")).toBe(false);
    expect(canAccessFacolubPath("management", "/outside")).toBe(false);
  });

  test("invoice detail and preview stay management-only", () => {
    const detail = "/facolub/documents/invoices/123";
    const preview = `${detail}/preview`;
    expect(canAccessFacolubPath("admin", detail)).toBe(true);
    expect(canAccessFacolubPath("management", preview)).toBe(true);
    expect(canAccessFacolubPath("factory", detail)).toBe(false);
  });

  test("each role has the correct landing path", () => {
    expect(defaultFacolubPath("admin")).toBe("/facolub");
    expect(defaultFacolubPath("management")).toBe("/facolub");
    expect(defaultFacolubPath("factory")).toBe("/facolub/today");
  });

  test("Supabase public config can be read from runtime environment variables", () => {
    const previousUrl = process.env["SUPABASE_URL"];
    const previousKey = process.env["SUPABASE_PUBLISHABLE_KEY"];
    const previousViteUrl = process.env["VITE_SUPABASE_URL"];
    const previousViteKey = process.env["VITE_SUPABASE_PUBLISHABLE_KEY"];

    try {
      delete process.env["VITE_SUPABASE_URL"];
      delete process.env["VITE_SUPABASE_PUBLISHABLE_KEY"];
      process.env["SUPABASE_URL"] = "https://example.supabase.co";
      process.env["SUPABASE_PUBLISHABLE_KEY"] = "pub-key";

      expect(getSupabasePublicConfig()).toEqual({
        url: "https://example.supabase.co",
        publishableKey: "pub-key",
        origin: "https://example.supabase.co",
      });
    } finally {
      if (previousUrl === undefined) delete process.env["SUPABASE_URL"];
      else process.env["SUPABASE_URL"] = previousUrl;

      if (previousKey === undefined) delete process.env["SUPABASE_PUBLISHABLE_KEY"];
      else process.env["SUPABASE_PUBLISHABLE_KEY"] = previousKey;

      if (previousViteUrl === undefined) delete process.env["VITE_SUPABASE_URL"];
      else process.env["VITE_SUPABASE_URL"] = previousViteUrl;

      if (previousViteKey === undefined) delete process.env["VITE_SUPABASE_PUBLISHABLE_KEY"];
      else process.env["VITE_SUPABASE_PUBLISHABLE_KEY"] = previousViteKey;
    }
  });
});
