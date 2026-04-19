// 极简静态文件服务器，服务 wasm/ 目录中的宿主侧分发文件
// 运行: node serve.js
// 然后在 Chrome/Edge 打开: http://localhost:3000/test.html

import { createServer } from "http";
import { readFile } from "fs/promises";
import { extname, join } from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js":   "application/javascript; charset=utf-8",
  ".wasm": "application/wasm",
  ".d.ts": "text/plain; charset=utf-8",
};

const PORT = 3000;

createServer(async (req, res) => {
  const url = req.url === "/" ? "/test.html" : req.url;
  const filePath = join(__dirname, url);

  // 安全检查：只允许服务当前目录内的文件
  if (!filePath.startsWith(__dirname)) {
    res.writeHead(403); res.end("Forbidden"); return;
  }

  try {
    const data = await readFile(filePath);
    const ext = extname(filePath);
    const mime = MIME[ext] ?? "application/octet-stream";
    res.writeHead(200, { "Content-Type": mime });
    res.end(data);
  } catch {
    res.writeHead(404); res.end("Not found: " + url);
  }
}).listen(PORT, () => {
  console.log(`✅ 服务器启动成功`);
  console.log(`   Test page:  http://localhost:${PORT}/test.html`);
  console.log(`   按 Ctrl+C 停止服务器`);
});
