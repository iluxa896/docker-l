#!/usr/bin/env bash
set -e

echo "=================================================="
echo "🚀 [Init Container] Starting Laravel Initialization"
echo "=================================================="

# 1. Automatically create .env from template if missing on fresh deployment
if [ ! -f .env ] && [ -f .env.example ]; then
    echo "📋 .env not found. Creating from .env.example..."
    cp .env.example .env
fi

# 2. Ensure required framework directories exist before any PHP execution
mkdir -p vendor storage/app/public storage/framework/{sessions,views,cache} storage/logs bootstrap/cache public/build

# 3. Allow Composer execution as superuser in init container
export COMPOSER_ALLOW_SUPERUSER=1

# 4. Composer Dependencies
echo "📦 Checking and installing Composer dependencies..."
composer install --no-interaction --prefer-dist --optimize-autoloader

# 5. Application Key Check (Generated before assets or migrations if missing)
if [ -f .env ]; then
    if ! grep -q "^APP_KEY=base64:" .env || [ -z "$(grep "^APP_KEY=" .env | cut -d '=' -f2)" ]; then
        echo "🔑 APP_KEY is missing. Generating application key..."
        php artisan key:generate --force --no-interaction
    fi
fi

# 6. Frontend Assets Build (Vite)
if [ ! -f public/build/manifest.json ] && [ ! -f public/build/.vite/manifest.json ]; then
    echo "🎨 Building frontend assets with Vite..."
    if [ -f package-lock.json ]; then
        npm ci --no-audit --prefer-offline 2>/dev/null || npm install --no-audit
    else
        npm install --no-audit
    fi
    npm run build
fi

# 7. Storage Symlink (Guards against physical folders and dangling/broken symlinks)
echo "🔗 Verifying storage symlink..."
if [ -d public/storage ] && [ ! -L public/storage ]; then
    echo "⚠️ public/storage was a physical directory, removing to recreate as symlink..."
    rm -rf public/storage
elif [ -L public/storage ] && [ ! -e public/storage ]; then
    echo "⚠️ public/storage was a broken symlink, removing to recreate..."
    rm -f public/storage
fi

if [ ! -L public/storage ]; then
    php artisan storage:link --relative --no-interaction 2>/dev/null || php artisan storage:link --no-interaction 2>/dev/null || true
fi

# 8. Database Migrations
echo "🗄️ Running database migrations..."
php artisan migrate --force --no-interaction

# 9. Cache & Optimization (Clears stale cache and precompiles config, routes, events, and views)
echo "⚡ Optimizing application caches..."
php artisan optimize:clear --no-interaction
php artisan optimize --no-interaction

# 10. Queue Workers Reset Signal (Signals Redis so running workers reboot gracefully)
echo "🔄 Signal queue workers to restart..."
php artisan queue:restart --no-interaction || true

# 11. Automatically assign permissions to non-root appuser (10001:10001) for runtime containers
# Note: Do NOT chown /var/www/html blindly, as docker/data belongs to postgres (UID 70) and redis (UID 999)
echo "🔒 Applying ownership & permissions for appuser (10001:10001)..."
chown -R 10001:10001 storage bootstrap/cache vendor public/build node_modules 2>/dev/null || true
chown -h 10001:10001 public/storage 2>/dev/null || true
chmod -R 775 storage bootstrap/cache 2>/dev/null || true
if [ -f .env ]; then
    chown 10001:10001 .env 2>/dev/null || true
    chmod 640 .env 2>/dev/null || true
fi

echo "=================================================="
echo "✅ [Init Container] Initialization completed successfully!"
echo "=================================================="

exit 0
