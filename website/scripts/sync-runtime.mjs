import { copyFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const publicDir = resolve(ROOT, "website/public");
const sourceLibDir = resolve(ROOT, "website/src/lib");
await mkdir(publicDir, { recursive: true });
await mkdir(sourceLibDir, { recursive: true });
for (const file of ["moonparse.js", "moonparse.wasm"]) {
  await copyFile(resolve(ROOT, "wasm", file), resolve(publicDir, file));
}
await copyFile(
  resolve(ROOT, "wasm/moonparse.js"),
  resolve(sourceLibDir, "moonparse.js"),
);
console.log("Website runtime synchronized from the authoritative wasm package.");
