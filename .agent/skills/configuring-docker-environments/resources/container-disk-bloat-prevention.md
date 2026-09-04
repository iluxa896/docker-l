# Universal Container Disk Bloat & Resource Runaway Prevention Guide

Uncontrolled disk consumption in Docker environments is one of the most common causes of production downtime. This guide details techniques to prevent disk space exhaustion across container logs, stateful database logs, build caches, and ephemeral files.

---

## 1. Container Log Capping (Docker Daemon & Compose)

By default, Docker's `json-file` log driver captures unlimited stdout/stderr logs for every container, easily filling disk partitions.

### A. Per-Service Log Cap (`docker-compose.yml`)
Always declare log limits on every service:

```yaml
services:
  any-service:
    image: my-service:latest
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

### B. Daemon-Wide Default (`/etc/docker/daemon.json`)
To enforce global defaults across all containers on a host machine:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

---

## 2. Stateful Service Log & Storage Management

Stateful services require specific log and write-ahead log (WAL) retention policies:

### PostgreSQL
- **WAL Accumulation**: If replication slots are orphaned or `max_slot_wal_keep_size` is not set, WAL files (`/var/lib/postgresql/data/pg_wal`) will grow infinitely.
- **Config Fix**:
  ```ini
  wal_keep_size = 1024       # Cap WAL files kept for standby (1GB)
  max_slot_wal_keep_size = 4096 # Max WAL kept by inactive slots (4GB)
  ```

### MySQL & MariaDB
- **Binary Logs (`binlog`)**: Binary logging is enabled by default in MySQL 8.0 and can consume hundreds of gigabytes if unpurged.
- **Config Fix** (`my.cnf`):
  ```ini
  binlog_expire_logs_seconds = 259200 # Automatically expire binlogs after 3 days (259200 seconds)
  max_binlog_size = 100M              # Rotate binlog file once it reaches 100MB
  ```

### Redis
- **AOF (Append Only File) Growth**: Uncompressed AOF logs grow continuously without rewriting.
- **Config Fix** (`redis.conf`):
  ```ini
  auto-aof-rewrite-percentage 100
  auto-aof-rewrite-min-size 64mb
  aof-use-rdb-preamble yes
  ```

### Web Proxies (Nginx / Apache / Traefik)
- Stream logs to `stdout`/`stderr` (`/dev/stdout`, `/dev/stderr`) so Docker's `json-file` driver can manage rotation, instead of writing log files directly inside container filesystems.

---

## 3. Ephemeral Storage & `tmpfs` Mounts

Writing temporary files, cache entries, or sessions to container layers increases overlay2 storage overhead and wear.

- Use `tmpfs` mounts for temporary scratch directories:
  ```yaml
  services:
    web:
      image: nginx:alpine
      tmpfs:
        - /tmp:rw,noexec,nosuid,size=64m
        - /var/cache/nginx:rw,noexec,nosuid,size=128m
  ```

---

## 4. Docker Build Cache & Pruning Maintenance

Old build layers, dangling images, and stopped containers accumulate on host disks over time.

### Automated Maintenance Commands
- **Remove stopped containers, dangling images, and unused networks**:
  ```bash
  docker system prune -f
  ```
- **Remove unused volumes (CAUTION: ensure stateful volumes are backed up)**:
  ```bash
  docker volume prune -f
  ```
- **Cap BuildKit cache size** (`/etc/docker/daemon.json`):
  ```json
  {
    "builder": {
      "gc": {
        "defaultKeepStorage": "20GB",
        "enabled": true
      }
    }
  }
  ```
