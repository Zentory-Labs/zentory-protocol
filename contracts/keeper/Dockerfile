# Multi-stage build keeps the runtime image lean (~150MB vs 1GB+).
# Stage 1 compiles TypeScript with full dev deps; stage 2 runs only the
# compiled JS with production deps.

FROM node:20-alpine AS builder

WORKDIR /app

# Copy manifests first so Docker can cache `npm ci` when only source changes.
COPY package.json package-lock.json ./
COPY tsconfig.json ./
RUN npm ci

COPY src ./src
RUN npm run build

# --- Runtime image ---
FROM node:20-alpine

WORKDIR /app

# Drop root for runtime — Alpine ships with a `node` user pre-baked.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY --from=builder /app/dist ./dist

USER node

# Default entrypoint runs the epoch settler (`src/index.ts` → `dist/index.js`).
# The heartbeat service overrides this via Railway's "Start Command" to
# `node dist/heartbeat.js`. One image, two services.
CMD ["node", "dist/index.js"]
