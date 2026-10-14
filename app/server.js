'use strict';

/**
 * Tiny HTTP service used to demonstrate a GitOps deployment.
 *
 *   GET /       -> { message, version, pod, uptimeSeconds }
 *   GET /healthz -> 200 always, as long as the process is alive (liveness)
 *   GET /readyz  -> 200 while able to serve, 503 once draining (readiness)
 *
 * Built on the Node standard library only. No dependencies means no
 * node_modules in the image, which in turn means there is nothing root-owned
 * that has to be chown'ed before the container can drop privileges.
 */

const http = require('node:http');

const PORT = Number(process.env.PORT || 8080);
const HOST = process.env.HOST || '0.0.0.0';

// Injected at image build time by CI so the running app can report which
// commit it is. Falls back to package.json for plain `npm start` locally.
const VERSION = process.env.APP_VERSION || require('./package.json').version;
const MESSAGE = process.env.APP_MESSAGE || 'Hello from the EXCO service';

// POD_NAME defaults to the hostname, which Kubernetes sets to the pod name.
const POD_NAME = process.env.POD_NAME || process.env.HOSTNAME || 'local';

const STARTED_AT = Date.now();

// Flipped as soon as we receive SIGTERM. Readiness starts failing
// immediately so the endpoint slice drops this pod and traffic moves to
// the other replicas while the listener drains.
let draining = false;

function sendJSON(res, statusCode, body) {
  const payload = JSON.stringify(body);
  res.writeHead(statusCode, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(payload),
    'cache-control': 'no-store',
  });
  res.end(payload);
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);

  if (req.method !== 'GET') {
    return sendJSON(res, 405, { error: 'method not allowed' });
  }

  switch (url.pathname) {
    case '/':
      return sendJSON(res, 200, {
        message: MESSAGE,
        version: VERSION,
        pod: POD_NAME,
        uptimeSeconds: Math.floor((Date.now() - STARTED_AT) / 1000),
      });

    case '/healthz':
      return sendJSON(res, 200, { status: 'ok', version: VERSION });

    case '/readyz':
      return draining
        ? sendJSON(res, 503, { status: 'draining' })
        : sendJSON(res, 200, { status: 'ready', version: VERSION });

    default:
      return sendJSON(res, 404, { error: 'not found' });
  }
});

// 'server.keepAliveTimeout' default is 5s; a client holding an idle keep-alive
// connection would otherwise keep the process alive past the grace period.
server.keepAliveTimeout = 5000;
server.headersTimeout = 10000;

server.listen(PORT, HOST, () => {
  console.log(`[${VERSION}] pod=${POD_NAME} listening on http://${HOST}:${PORT}`);
});

let shuttingDown = false;

/**
 * Graceful shutdown. Kubernetes sends SIGTERM before removing a pod, and
 * waits `terminationGracePeriodSeconds` before escalating to SIGKILL. Without
 * a handler Node would exit immediately and drop in-flight requests, which is
 * exactly what we must avoid if we want a zero-downtime rollout.
 */
function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`[${VERSION}] received ${signal}, draining connections`);

  // Stop accepting new connections. Existing ones are allowed to finish.
  server.close(() => {
    console.log(`[${VERSION}] all connections closed, exiting`);
    process.exit(0);
  });

  // Hard cap, so a stuck connection can never wedge a rollout until SIGKILL.
  const forced = setTimeout(() => {
    console.error(`[${VERSION}] grace period elapsed, forcing exit`);
    process.exit(1);
  }, 10000);
  forced.unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));