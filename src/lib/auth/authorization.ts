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
  const isRegistered =
    FACOLUB_PATHS.has(path) ||
    path.startsWith("/facolub/stock/") ||
    path.startsWith("/facolub/receiving/") ||
    path.startsWith("/facolub/settings/") ||
    path.startsWith("/facolub/documents/invoices/") ||
    path.startsWith("/facolub/documents/orders/");
  if (!isRegistered) return false;
  if (role === "admin") return true;
  if (role === "management") {
    return ![...MANAGEMENT_DENIED_PATHS].some(
      (candidate) => path === candidate || path.startsWith(`${candidate}/`),
    );
  }
  return [...FACTORY_PATHS].some(
    (candidate) => path === candidate || path.startsWith(`${candidate}/`),
  );
}

export function defaultFacolubPath(role: AppRole) {
  return role === "factory" ? "/facolub/today" : "/facolub";
}
