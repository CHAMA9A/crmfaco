import { spawn, spawnSync } from "node:child_process";
import { resolve } from "node:path";

const port = 4173;
const baseUrl = `http://127.0.0.1:${port}`;
const publicRoutes = ["/login", "/forgot-password", "/reset-password"];
const protectedRoutes = [
  "/environments",
  "/facolub",
  "/facolub/today",
  "/facolub/stock",
  "/facolub/planning",
  "/facolub/dispatch",
  "/facolub/analytics",
  "/facolub/documents",
  "/facolub/documents/orders/new",
  "/facolub/documents/orders/00000000-0000-4000-8000-000000000001",
  "/facolub/documents/orders/00000000-0000-4000-8000-000000000001/edit",
  "/facolub/documents/orders/00000000-0000-4000-8000-000000000001/invoice",
  "/facolub/documents/orders/00000000-0000-4000-8000-000000000001/delivery-note",
  "/facolub/documents/orders/00000000-0000-4000-8000-000000000001/transport-note",
  "/facolub/documents/invoices/00000000-0000-4000-8000-000000000001",
  "/facolub/documents/invoices/00000000-0000-4000-8000-000000000001/preview",
];
const wranglerCli = resolve("node_modules/wrangler/bin/wrangler.js");
const preview = spawn(process.execPath, [wranglerCli, "dev", "--port", String(port)], {
  env: { ...process.env, WRANGLER_SEND_METRICS: "false" },
  stdio: ["ignore", "pipe", "pipe"],
});

let previewOutput = "";
preview.stdout.on("data", (chunk) => (previewOutput += chunk));
preview.stderr.on("data", (chunk) => (previewOutput += chunk));

async function waitForPreview() {
  const deadline = Date.now() + 45_000;
  while (Date.now() < deadline) {
    if (preview.exitCode !== null) {
      throw new Error(`Production preview exited early.\n${previewOutput}`);
    }
    try {
      const response = await fetch(`${baseUrl}/login`, { redirect: "manual" });
      if (response.status < 500) return;
    } catch {
      // The local Worker is still starting.
    }
    await new Promise((resolveDelay) => setTimeout(resolveDelay, 250));
  }
  throw new Error(`Production preview did not start in time.\n${previewOutput}`);
}

function stopPreview() {
  if (preview.exitCode !== null || preview.pid === undefined) return;
  if (process.platform === "win32") {
    spawnSync("taskkill", ["/PID", String(preview.pid), "/T", "/F"], { stdio: "ignore" });
  } else {
    preview.kill("SIGTERM");
  }
}

try {
  await waitForPreview();
  for (const route of publicRoutes) {
    const response = await fetch(`${baseUrl}${route}`, { redirect: "manual" });
    if (response.status >= 400) {
      throw new Error(`${route} returned HTTP ${response.status}`);
    }
    const headers = response.headers;
    if (headers.get("x-content-type-options") !== "nosniff") {
      throw new Error(`${route} is missing the security header baseline`);
    }
    console.log(`PASS ${route} (${response.status})`);
  }
  for (const route of protectedRoutes) {
    const response = await fetch(`${baseUrl}${route}`, { redirect: "manual" });
    if (![301, 302, 303, 307, 308].includes(response.status)) {
      throw new Error(
        `${route} should redirect an unauthenticated request, received HTTP ${response.status}`,
      );
    }
    const location = response.headers.get("location");
    if (!location?.includes("/login")) throw new Error(`${route} did not redirect to /login`);
    console.log(`PASS ${route} (${response.status} -> /login)`);
  }
} finally {
  stopPreview();
}
