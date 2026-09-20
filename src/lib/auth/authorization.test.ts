import { describe, expect, test } from "bun:test";

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

  test("each role has the correct landing path", () => {
    expect(defaultFacolubPath("admin")).toBe("/facolub");
    expect(defaultFacolubPath("management")).toBe("/facolub");
    expect(defaultFacolubPath("factory")).toBe("/facolub/today");
  });
});
