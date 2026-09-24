import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const compatibilityDate = "2026-09-23";
const configPath = resolve(".output/server/wrangler.json");
const config = JSON.parse(await readFile(configPath, "utf8"));

config.compatibility_date = compatibilityDate;
await writeFile(configPath, `${JSON.stringify(config, null, 2)}\n`, "utf8");

console.log(`Pinned Wrangler compatibility_date to ${compatibilityDate}`);
