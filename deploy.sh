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

# 3. Ensure Nginx web server is running and updated with latest config
echo "🌐 Ensuring Nginx web server is active..."
docker compose up -d $BUILD_FLAG web

# 4. Explicitly stop app container so Nginx immediately serves 503 Maintenance Page
# for the ENTIRE duration of app-init (Vite asset build, Composer install, migrations).
echo "🛑 Activating maintenance mode (Nginx serves 503 page)..."
docker compose stop app

# 5. Run app-init to completion (Vite build, Composer, migrations).
# Once app-init completes successfully, Docker Compose automatically starts app (PHP-FPM).
echo "📦 Running app-init and recreating application workers..."
docker compose up -d $BUILD_FLAG --force-recreate app-init app queue scheduler

# 6. Safe prune of dangling images left behind from builds (leaves active images & volumes untouched)
echo "🧹 Cleaning up obsolete dangling images..."
docker image prune -f

echo "=================================================="
echo "✅ [Deploy] Deployment process initialized!"
echo "   • Nginx is running continuously on ports 80/443"
echo "   • Serving 503 Maintenance Page with 12s auto-refresh"
echo "   • Will switch to live store automatically once app-init completes"
echo "=================================================="
