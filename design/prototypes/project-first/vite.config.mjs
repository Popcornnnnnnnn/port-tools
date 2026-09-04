import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const prototypeRoot = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(prototypeRoot, "../../..");
const scanner = path.join(repoRoot, "prototype/port_tools.py");

function liveInventory() {
  let cached = null;
  let cachedAt = 0;
  return {
    name: "port-tools-live-inventory",
    configureServer(server) {
      server.middlewares.use("/api/inventory", (request, response) => {
        if (request.method !== "GET") {
          response.statusCode = 405;
          response.end("Method not allowed");
          return;
        }
        if (cached && Date.now() - cachedAt < 5000) {
          response.setHeader("Content-Type", "application/json; charset=utf-8");
          response.setHeader("Cache-Control", "no-store");
          response.end(cached);
          return;
        }
        execFile(
          "python3",
          [scanner, "scan", "--json", "--all"],
          { cwd: repoRoot, timeout: 20000, maxBuffer: 8 * 1024 * 1024 },
          (error, stdout, stderr) => {
            if (error) {
              response.statusCode = 500;
              response.setHeader("Content-Type", "application/json; charset=utf-8");
              response.end(JSON.stringify({ error: stderr.trim() || error.message }));
              return;
            }
            cached = stdout;
            cachedAt = Date.now();
            response.setHeader("Content-Type", "application/json; charset=utf-8");
            response.setHeader("Cache-Control", "no-store");
            response.end(stdout);
          },
        );
      });
    },
  };
}

export default defineConfig({
  build: {
    outDir: "dist/client",
  },
  optimizeDeps: {
    include: ["react", "react-dom/client"],
  },
  server: {
    host: "0.0.0.0",
    allowedHosts: ["terminal.local"],
    fs: {
      allow: ["/Users/forge/Workspace/port-tools"],
    },
    warmup: {
      clientFiles: ["./src/main.jsx"],
    },
  },
  plugins: [react(), liveInventory()],
});
