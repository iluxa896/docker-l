---
name: configuring-docker-environments
description: >-
  Expert skill for crafting production-ready Dockerfiles, docker-compose setups, and container
  security hardening tailored to project scale. Prevents disk space bloat (Docker log capping,
  database WAL/binlog rotation), enforces non-root users (USER 10001), multi-stage builds,
  init signal handling (tini), healthchecks, and resource quotas. Use when creating or refactoring
  Dockerfiles, configuring docker-compose.yml, auditing container security, or setting up deployment stacks.
---

# Configuring Docker & Docker Compose Environments (Master Skill)

## When to use this skill
- Writing or refactoring `Dockerfile`, `docker-compose.yml`, or `.dockerignore` for any service stack.
- Assessing project scale (Dev/MVP vs Staging/Prod vs Enterprise High-Load) to select appropriate container architecture.
- Preventing disk space bloat caused by container log runaway, uncontrolled database binary/WAL logs, or build cache leaks.
- Implementing multi-stage builds, layer caching optimization, unprivileged non-root users (`USER 10001:10001`), and init signal handling (`tini`).
- Setting up container healthchecks (`HEALTHCHECK`), dependency ordering (`depends_on: condition: service_healthy`), and resource quotas (`cpus`, `memory`).
- Running the Docker security and configuration linter tool (`scripts/docker-security-linter.mjs`).

---

## 1. Degrees of Freedom Model

| Freedom Level | Area | Application & Constraints |
| :--- | :--- | :--- |
| **High Freedom** | Architecture & Service Topologies | Deciding service boundaries, cache layers (Redis vs Memcached), proxy selections (Nginx, Traefik, Caddy), volume backup schedules. |
| **Medium Freedom** | Base Images & Health Intervals | Base OS image tag selection (Alpine vs Debian slim), healthcheck intervals (`interval: 15s`, `retries: 3`), internal network naming. |
| **Low Freedom** | Security Hardening & Log Capping | Mandatory non-root user (`USER 10001`), mandatory log rotation caps (`max-size: "10m"`, `max-file: "3"`), init signal wrapping (`tini`), `.dockerignore` exclusion of secrets. |

---

## 2. Project Scale Assessment Framework

Before generating Docker configurations, evaluate the project tier across these 4 dimensions:

| Dimension | Tier 1: Dev / MVP | Tier 2: Staging / Prod Standard | Tier 3: Enterprise High-Load |
| :--- | :--- | :--- | :--- |
| **Purpose** | Fast iteration, hot-reloading | Stable deployment, clean logs | Hardened, high-availability, microservices |
| **Storage & Logs** | Bind mounts, standard stdout | Log rotation (`10m`, 3 files), named volumes | Strict log caps (`5m`, 2 files), `tmpfs` mounts, backup volumes |
| **Security** | Root user allowed in container | Non-root system user (`appuser`) | Non-root + read-only rootfs + dropped capabilities |
| **Resources** | Unlimited local host resources | Memory & CPU limits per service | Strict CPU/Mem quotas, reservation + limit guarantees |

---

## 3. Mandatory Safety & Optimization Checklist

```markdown
- [ ] 1. Container Log Capping
      - Enforce logging: driver: "json-file" with max-size: "10m" and max-file: "3" on all Compose services.
- [ ] 2. Stateful Log & WAL Retention
      - Configure log/journal retention for any stateful service (PostgreSQL WAL, MySQL binlogs, Redis AOF, Nginx logs).
- [ ] 3. Security & Non-Root User
      - Create a dedicated non-root group and user in Dockerfile (USER 10001:10001).
- [ ] 4. Init Process & Signal Handling
      - Use tini or dumb-init to handle SIGTERM/SIGINT gracefully and reap zombie processes.
- [ ] 5. Healthcheck & Service Dependency
      - Define explicit HEALTHCHECK for stateful/dependent services and use depends_on: condition: service_healthy.
- [ ] 6. Build Cache & Ignore Rules
      - Include .dockerignore to exclude node_modules, .git, temporary files, and vendor directories.
- [ ] 7. Automated Linting
      - Run docker linter: node .agent/skills/configuring-docker-environments/scripts/docker-security-linter.mjs
```

---

## 4. Multi-Stage Dockerfile Hardening

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

## 5. Automated Docker Environment Verification

Run the built-in security linter to audit Dockerfiles and docker-compose files:

```bash
node .agent/skills/configuring-docker-environments/scripts/docker-security-linter.mjs --path .
```

---

## 6. Quick Reference Tools & Resources

- **Docker Security Linter**: [docker-security-linter.mjs](./scripts/docker-security-linter.mjs) - Node.js CLI script inspecting Dockerfiles and Compose configurations for log caps, non-root users, and healthchecks.
- **Universal Compose Template**: [docker-compose.universal.yml](./examples/docker-compose.universal.yml) - Production-grade Compose setup with log caps, healthchecks, and Postgres data volume.
- **Node.js Multi-Stage Dockerfile**: [Dockerfile.multi-stage](./examples/Dockerfile.multi-stage) - Multi-stage Node.js Dockerfile with tini and non-root execution.
- **PHP-FPM & Nginx Dockerfile**: [Dockerfile.php-fpm-nginx](./examples/Dockerfile.php-fpm-nginx) - Hardened PHP 8.3/8.4 + Nginx multi-stage build with OPcache and socket IPC.
- **Production Hardening Guide**: [docker-production-hardening.md](./references/docker-production-hardening.md) - Deep architectural guide on Linux namespaces, cgroups v2, capability dropping, and secrets.
- **Disk Bloat Prevention Guide**: [container-disk-bloat-prevention.md](./resources/container-disk-bloat-prevention.md) - Detailed formulas and configurations for log rotation and stateful storage retention.
