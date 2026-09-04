---
name: configuring-docker-environments
description: >-
  Expert skill for crafting production-ready Dockerfiles and docker-compose setups
  tailored to project scale (Dev, Staging, Enterprise/Prod). Evaluates project requirements,
  prevents container disk space bloat (Docker log capping, stateful WAL/journal/binlog rotation),
  enforces security hardening (non-root users, multi-stage builds), and configures healthchecks
  and resource quotas for any technology stack. Use when the user asks to write, optimize,
  or configure Docker, Dockerfiles, or docker-compose environments.
---

# Configuring Docker & Docker Compose Environments (Master Skill)

## When to use this skill
- Writing or refactoring `Dockerfile` or `docker-compose.yml` for any service stack.
- Assessing project scale (Dev/MVP vs Staging/Prod vs Enterprise High-Load) to select appropriate container architecture.
- Preventing disk space bloat caused by container log runaway, uncontrolled database binary/WAL logs, or build cache leaks.
- Implementing multi-stage builds, layer caching optimization, unprivileged non-root users (`USER 10001`), and init signal handling (`tini`).
- Setting up container healthchecks (`HEALTHCHECK`), dependency ordering (`depends_on: condition: service_healthy`), and resource quotas (`cpus`, `memory`).

---

## Step 1: Project Scale Assessment Framework

Before generating Docker configurations, evaluate the project tier by asking or identifying these 4 key dimensions:

| Dimension | Tier 1: Dev / MVP | Tier 2: Staging / Prod Standard | Tier 3: Enterprise High-Load |
| :--- | :--- | :--- | :--- |
| **Purpose** | Fast iteration, hot-reloading | Stable deployment, clean logs | Hardened, high-availability, microservices |
| **Storage & Logs** | Bind mounts, standard stdout | Log rotation (`10m`, 3 files), named volumes | Strict log caps (`5m`, 2 files), `tmpfs` mounts, backup volumes |
| **Security** | Root user allowed in container | Non-root system user (`appuser`) | Non-root + read-only rootfs + dropped capabilities |
| **Resources** | Unlimited local host resources | Memory & CPU limits per service | Strict CPU/Mem quotas, reservation + limit guarantees |

---

## Step 2: Mandatory Safety & Optimization Checklist

Execute this checklist for every Docker setup:

- [ ] **1. Container Log Capping**
  - Always enforce `logging: driver: "json-file"` with `max-size` and `max-file` options on all Compose services.
- [ ] **2. Stateful Log & WAL Retention**
  - Configure log/journal retention for any stateful service (PostgreSQL WAL, MySQL binlogs, Redis AOF, Nginx logs).
- [ ] **3. Security & Non-Root User**
  - Create a dedicated non-root group and user in `Dockerfile` (`USER 10001:10001`).
- [ ] **4. Init Process & Signal Handling**
  - Use `tini` or `dumb-init` to handle `SIGTERM`/`SIGINT` gracefully and reap zombie processes.
- [ ] **5. Healthcheck & Service Dependency**
  - Define explicit `HEALTHCHECK` for stateful/dependent services and use `depends_on: condition: service_healthy`.
- [ ] **6. Build Cache & Ignore Rules**
  - Include `.dockerignore` to exclude `node_modules`, `.git`, temporary files, and vendor directories.

---

## Workflow 1: Multi-Stage Dockerfile Hardening

For any backend or web application, separate build tooling from runtime dependencies:

```dockerfile
# Stage 1: Build & Dependencies
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

# Stage 2: Minimal Production Runtime
FROM node:20-alpine AS runner
WORKDIR /app

# Install lightweight init process
RUN apk add --no-cache tini
ENTRYPOINT ["/sbin/tini", "--"]

# Security: Create non-root system user
RUN addgroup -S appgroup -g 10001 && \
    adduser -S appuser -u 10001 -G appgroup
USER appuser:appgroup

COPY --from=builder /app/node_modules ./node_modules
COPY --chown=appuser:appgroup . .

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

CMD ["node", "server.js"]
```

---

## Workflow 2: Universal Docker Compose Configuration

Use a production-ready Compose configuration with log limits and healthchecks:

```yaml
version: '3.8'

x-logging-defaults: &default-logging
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    restart: unless-stopped
    logging: *default-logging
    environment:
      - NODE_ENV=production
      - DB_HOST=db
    depends_on:
      db:
        condition: service_healthy
    deploy:
      resources:
        limits:
          cpus: '1.5'
          memory: 1G
        reservations:
          memory: 256M

  db:
    image: postgres:16-alpine
    restart: unless-stopped
    logging: *default-logging
    environment:
      POSTGRES_DB: app_db
      POSTGRES_USER: app_user
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    volumes:
      - db_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app_user -d app_db"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  db_data:
    driver: local
```

---

## Workflow 3: Universal Disk Space & Log Bloat Prevention

To prevent containers from consuming 100% of host disk space:

1. **Docker Daemon & Container Logs**:
   - Set `max-size: "10m"` and `max-file: "3"` to limit log footprint per container to max 30MB.
2. **Stateful Services (Databases / Caches / Web Servers)**:
   - **PostgreSQL**: Set `wal_keep_size = '1GB'` or `max_slot_wal_keep_size` to prevent WAL buildup.
   - **MySQL / MariaDB**: Set `binlog_expire_logs_seconds = 259200` (3 days) and `max_binlog_size = 100M`.
   - **Redis**: Enable `aof-use-rdb-preamble yes` and configure `auto-aof-rewrite-percentage 100`.
   - **Nginx / Web Servers**: Route access logs to `/dev/stdout` or rotate logs via `logrotate`.
3. **Ephemeral Storage**:
   - Use `tmpfs` mounts for temporary work directories (e.g. `/tmp`, `/var/cache`) to avoid overlay2 disk writes.

> [!IMPORTANT]
> Detailed disk bloat prevention patterns and docker maintenance procedures can be found in [container-disk-bloat-prevention.md](./resources/container-disk-bloat-prevention.md).

---

## Quick Reference Tools & Resources

- [Universal Production Docker Compose Template](./examples/docker-compose.universal.yml)
- [Production Multi-Stage Dockerfile Template](./examples/Dockerfile.multi-stage)
- [Container Disk Bloat & Log Prevention Guide](./resources/container-disk-bloat-prevention.md)
