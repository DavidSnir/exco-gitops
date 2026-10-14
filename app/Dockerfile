# syntax=docker/dockerfile:1

# Single stage on purpose: the service has no build step and no dependencies,
# so there is nothing for a second stage to prune.
FROM node:22-alpine

# Injected by CI so the app can report exactly which commit it is running.
# Falls back to 'dev' for local builds.
ARG APP_VERSION=dev

ENV NODE_ENV=production \
    APP_VERSION=${APP_VERSION} \
    PORT=8080

WORKDIR /app

# Only two files. Root-owned source files remain readable by the non-root
# runtime user; the app needs no write access to its working directory.
COPY package.json server.js ./

# `node` (uid 1000, gid 1000) ships with the official image.
USER node

EXPOSE 8080

# Uses the app's own liveness endpoint so container health and Kubernetes
# liveness probe agree on what "healthy" means.
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||8080)+'/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

# Exec form: node becomes PID 1 and receives SIGTERM directly, which is what
# the graceful shutdown handler in server.js relies on.
CMD ["node", "server.js"]
