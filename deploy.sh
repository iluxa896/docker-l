#!/usr/bin/env bash
set -e

echo "=================================================="
echo "🚀 [Deploy] Starting zero-outage rolling deployment"
echo "=================================================="

# 1. Fetch and merge latest git repository updates
echo "📥 Pulling latest codebase updates..."
git pull

# 2. Determine build mode
# Pass --build or -b to rebuild Docker images (e.g., when Dockerfiles or PHP extensions change)
BUILD_FLAG=""
if [[ "$1" == "--build" || "$1" == "-b" ]]; then
    echo "🔨 Full image rebuild mode enabled (--build)..."
    BUILD_FLAG="--build"
fi

# 3. Recreate app-init and app containers with zero web server downtime
# Nginx, PostgreSQL, and Redis remain running uninterrupted.
# Nginx immediately catches 502/504 and serves the branded 503 Maintenance Page
# while app-init installs Composer packages, compiles Vite assets, and runs migrations.
echo "📦 Recreating application workers (app-init, app, queue, scheduler)..."
docker compose up -d $BUILD_FLAG --force-recreate app-init app queue scheduler

# 4. Safe prune of dangling images left behind from builds (leaves active images & volumes untouched)
echo "🧹 Cleaning up obsolete dangling images..."
docker image prune -f

echo "=================================================="
echo "✅ [Deploy] Deployment launched successfully!"
echo "   • Nginx is running continuously on ports 80/443"
echo "   • Serving 503 Maintenance Page with 12s auto-refresh"
echo "   • Will switch to live store automatically once app-init completes"
echo "=================================================="
