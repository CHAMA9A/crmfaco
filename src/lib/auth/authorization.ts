import type { AppRole } from "@/types/auth";

const FACTORY_PATHS = new Set([
  "/facolub/today",
  "/facolub/stock",
  "/facolub/receiving",
  "/facolub/planning",
  "/facolub/production",
  "/facolub/dispatch",
  "/facolub/history",
  "/facolub/problems",
]);

const MANAGEMENT_DENIED_PATHS = new Set(["/facolub/settings", "/facolub/users"]);
const FACOLUB_PATHS = new Set([
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
]);

export function normalizeAppPath(pathname: string) {
  if (pathname.length > 1 && pathname.endsWith("/")) return pathname.slice(0, -1);
  return pathname;
}

export function canAccessFacolubPath(role: AppRole, pathname: string) {
  const path = normalizeAppPath(pathname);
  if (role === "admin") return FACOLUB_PATHS.has(path);
  if (role === "management") {
    return FACOLUB_PATHS.has(path) && !MANAGEMENT_DENIED_PATHS.has(path);
  }
  return FACTORY_PATHS.has(path);
}

export function defaultFacolubPath(role: AppRole) {
  return role === "factory" ? "/facolub/today" : "/facolub";
}
