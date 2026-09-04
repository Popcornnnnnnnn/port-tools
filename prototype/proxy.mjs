#!/usr/bin/env node

import fs from "node:fs";
import http from "node:http";
import https from "node:https";
import net from "node:net";


function parseArguments(argv) {
  const options = { listen: "127.0.0.1:17890", state: ".port-tools-spike/routes.json" };
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (key === "--listen") options.listen = value;
    else if (key === "--state") options.state = value;
    else throw new Error(`unknown argument: ${key}`);
  }
  const separator = options.listen.lastIndexOf(":");
  if (separator < 1) throw new Error("listen must be host:port");
  return {
    ...options,
    host: options.listen.slice(0, separator),
    port: Number(options.listen.slice(separator + 1)),
  };
}


function loadRoutes(statePath) {
  try {
    const document = JSON.parse(fs.readFileSync(statePath, "utf8"));
    return document.routes || {};
  } catch (error) {
    if (error.code === "ENOENT") return {};
    throw error;
  }
}


function aliasFromHost(hostHeader) {
  const hostname = (hostHeader || "").toLowerCase().split(":", 1)[0];
  if (!hostname.endsWith(".localhost")) return null;
  const alias = hostname.slice(0, -".localhost".length);
  return alias && !alias.includes(".") ? alias : null;
}


function resolveRoute(request, statePath) {
  const alias = aliasFromHost(request.headers.host);
  return { alias, route: alias ? loadRoutes(statePath)[alias] : null };
}


function diagnostic(response, status, title, detail) {
  const body = Buffer.from(
    `<!doctype html><html><head><meta charset="utf-8"><title>${title}</title></head>` +
      `<body><main><h1>${title}</h1><p>${detail}</p></main></body></html>`,
  );
  response.writeHead(status, {
    "content-type": "text/html; charset=utf-8",
    "content-length": body.length,
    "cache-control": "no-store",
  });
  response.end(body);
}


function upstreamHeaders(request, route) {
  const headers = { ...request.headers };
  if (route.hostMode !== "preserve") headers.host = `127.0.0.1:${route.port}`;
  headers["x-forwarded-host"] = request.headers.host || "";
  headers["x-forwarded-proto"] = "http";
  headers["x-forwarded-for"] = request.socket.remoteAddress || "127.0.0.1";
  delete headers["proxy-connection"];
  return headers;
}


const options = parseArguments(process.argv.slice(2));

const server = http.createServer((request, response) => {
  const { alias, route } = resolveRoute(request, options.state);
  if (!alias) {
    diagnostic(response, 404, "Unknown local name", "Use an <alias>.localhost Host header.");
    return;
  }
  if (!route) {
    diagnostic(response, 404, "Alias not configured", `${alias}.localhost has no route.`);
    return;
  }

  const transport = route.scheme === "https" ? https : http;
  const upstream = transport.request(
    {
      hostname: "127.0.0.1",
      port: route.port,
      method: request.method,
      path: request.url,
      headers: upstreamHeaders(request, route),
      rejectUnauthorized: route.tlsPolicy !== "insecure-local",
    },
    (upstreamResponse) => {
      response.writeHead(upstreamResponse.statusCode || 502, upstreamResponse.headers);
      upstreamResponse.pipe(response);
    },
  );
  upstream.on("error", (error) => {
    if (!response.headersSent) {
      diagnostic(
        response,
        502,
        "Local app unavailable",
        `${alias}.localhost points to 127.0.0.1:${route.port} (${error.code || "connection failed"}).`,
      );
    } else {
      response.destroy(error);
    }
  });
  request.pipe(upstream);
});

server.on("upgrade", (request, clientSocket, head) => {
  const { alias, route } = resolveRoute(request, options.state);
  if (!alias || !route) {
    clientSocket.end("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n");
    return;
  }
  if (route.scheme === "https") {
    clientSocket.end("HTTP/1.1 501 Not Implemented\r\nConnection: close\r\n\r\n");
    return;
  }
  const upstreamSocket = net.connect(route.port, "127.0.0.1");
  clientSocket.on("error", () => upstreamSocket.destroy());
  upstreamSocket.on("connect", () => {
    const headers = upstreamHeaders(request, route);
    const lines = [`${request.method} ${request.url} HTTP/${request.httpVersion}`];
    for (const [name, value] of Object.entries(headers)) {
      if (Array.isArray(value)) {
        for (const item of value) lines.push(`${name}: ${item}`);
      } else if (value !== undefined) {
        lines.push(`${name}: ${value}`);
      }
    }
    upstreamSocket.write(`${lines.join("\r\n")}\r\n\r\n`);
    if (head.length) upstreamSocket.write(head);
    clientSocket.pipe(upstreamSocket).pipe(clientSocket);
  });
  upstreamSocket.on("error", () => {
    if (!clientSocket.destroyed) {
      clientSocket.end("HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n");
    }
  });
});

server.on("clientError", (_error, socket) => {
  socket.end("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n");
});

server.listen(options.port, options.host, () => {
  process.stdout.write(
    `${JSON.stringify({ event: "listening", host: options.host, port: options.port, state: options.state })}\n`,
  );
});

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
