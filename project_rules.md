# Project Rules & Architectural Guidelines

1. **Docker Configuration Standards**:
   - Enforce non-root user execution in containers (`USER 10001:10001`).
   - Use multi-stage builds to optimize image size and security.
   - Limit container logs (`json-file` driver with max-size 10m and max-file 3).
   - Use `tini` or `dumb-init` for signal handling and zombie reaping.
   - Define explicit `HEALTHCHECK` and `depends_on: condition: service_healthy` in compose setups.
