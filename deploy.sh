#!/usr/bin/env bash
set -e

echo "=================================================="
echo "🚀 [Deploy] Starting zero-outage rolling deployment"
echo "=================================================="

# Parse arguments
BUILD_FLAG=""
PRUNE_FLAG=false

for arg in "$@"; do
    case "$arg" in
        --build|-b)
            BUILD_FLAG="--build"
            echo "🔨 Full image rebuild mode enabled (--build)"
            ;;
        --prune|-p)
            PRUNE_FLAG=true
            echo "🧹 Docker cache & image pruning enabled (--prune)"
            ;;
        --help|-h)
            echo "Usage: ./deploy.sh [OPTIONS]"
            echo "Options:"
            echo "  -b, --build   Rebuild Docker images (e.g., when Dockerfile or PHP extensions change)"
            echo "  -p, --prune   Prune BuildKit build cache, dangling images, and host crash logs"
            echo "  -h, --help    Show this help message"
            exit 0
            ;;
        *)
            echo "⚠️ Unknown option: $arg (ignored)"
            ;;
    esac
done

# 0. Pre-flight host & Docker hygiene (only when --prune is explicitly passed)
if [ "$PRUNE_FLAG" = true ]; then
    if command -v journalctl &> /dev/null; then
        echo "🧹 [--prune] Pre-flight: Vacuuming systemd journal logs to 50M..."
        journalctl --vacuum-size=50M 2>/dev/null || true
    fi
    echo "🧹 [--prune] Pre-flight: Cleaning host crash dumps and apt cache..."
    rm -rf /var/lib/apport/* /var/crash/* 2>/dev/null || true
    apt-get clean 2>/dev/null || true

    echo "🧹 [--prune] Pre-flight: Clearing stale BuildKit cache and dangling images..."
    docker builder prune -f
    docker image prune -f
fi

# 1. Fetch and merge latest git repository updates
echo "📥 Pulling latest codebase updates..."
git pull

# 2. Ensure Nginx web server is running and updated with latest config
echo "🌐 Ensuring Nginx web server is active..."
docker compose up -d $BUILD_FLAG web

# 3. Explicitly stop app container so Nginx immediately serves 503 Maintenance Page
# for the ENTIRE duration of app-init (Vite asset build, Composer install, migrations).
echo "🛑 Activating maintenance mode (Nginx serves 503 page)..."
docker compose stop app

# 4. Run app-init to completion (Vite build, Composer, migrations).
# Once app-init completes successfully, Docker Compose automatically starts app (PHP-FPM).
echo "📦 Running app-init and recreating application workers..."
docker compose up -d $BUILD_FLAG --force-recreate app-init app queue scheduler postgres-backup

# 5. Safe prune of build cache and obsolete dangling images (only when --prune is passed)
if [ "$PRUNE_FLAG" = true ]; then
    echo "🧹 [--prune] Post-flight: Cleaning up BuildKit build cache to prevent disk exhaustion..."
    docker builder prune -f

    echo "🧹 [--prune] Post-flight: Cleaning up obsolete dangling images..."
    docker image prune -f
fi

echo "=================================================="
echo "✅ [Deploy] Deployment process initialized!"
echo "   • Nginx is running continuously on ports 80/443"
echo "   • Serving 503 Maintenance Page with 12s auto-refresh"
echo "   • Will switch to live store automatically once app-init completes"
echo "💾 Available host disk space:"
df -h /
echo "=================================================="
