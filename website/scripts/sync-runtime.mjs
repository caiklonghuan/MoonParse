import { copyFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const publicDir = resolve(ROOT, "website/public");
await mkdir(publicDir, { recursive: true });
for (const file of ["moonparse.js", "moonparse.wasm"]) {
  await copyFile(resolve(ROOT, "wasm", file), resolve(publicDir, file));
}
console.log("Website runtime synchronized from the authoritative wasm package.");

