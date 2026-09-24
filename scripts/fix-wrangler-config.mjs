import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const compatibilityDate = "2026-09-23";
const configPath = resolve(".output/server/wrangler.json");
const nitroPreset = process.env.NITRO_PRESET?.toLowerCase();
const isVercelBuild = Boolean(process.env.VERCEL) || nitroPreset?.startsWith("vercel");

if (isVercelBuild) {
  console.log("Vercel build detected; skipping Wrangler compatibility_date pin.");
  process.exit(0);
}

let config;

try {
  config = JSON.parse(await readFile(configPath, "utf8"));
} catch (error) {
  if (error?.code === "ENOENT") {
    console.log("No Wrangler config generated; skipping compatibility_date pin.");
    process.exit(0);
  }
  throw error;
}

config.compatibility_date = compatibilityDate;
await writeFile(configPath, `${JSON.stringify(config, null, 2)}\n`, "utf8");

console.log(`Pinned Wrangler compatibility_date to ${compatibilityDate}`);
