#!/usr/bin/env bash
set -e

echo "=================================================="
echo "🚀 [Init Container] Starting Laravel Initialization"
echo "=================================================="

# 0. Automatically create .env from template if missing on fresh deployment
if [ ! -f .env ] && [ -f .env.example ]; then
    echo "📋 .env not found. Creating from .env.example..."
    cp .env.example .env
fi

# 1. Ensure required framework directories exist
mkdir -p vendor storage/framework/{sessions,views,cache} storage/logs bootstrap/cache public/storage

# 2. Allow Composer execution as superuser in init container
export COMPOSER_ALLOW_SUPERUSER=1

# 3. Composer Dependencies
echo "📦 Checking and installing Composer dependencies..."
composer install --no-interaction --prefer-dist --optimize-autoloader

# 4. Application Key Check
if [ -f .env ]; then
    if ! grep -q "^APP_KEY=base64:" .env || [ -z "$(grep "^APP_KEY=" .env | cut -d '=' -f2)" ]; then
        echo "🔑 APP_KEY is missing. Generating application key..."
        php artisan key:generate --force --no-interaction
    fi
fi

# 5. Storage Symlink
echo "🔗 Creating storage symlink..."
php artisan storage:link --no-interaction 2>/dev/null || true

# 6. Database Migrations
echo "🗄️ Running database migrations..."
php artisan migrate --force --no-interaction

# 7. Cache & Optimization based on APP_ENV
echo "⚡ Processing application caches for APP_ENV=${APP_ENV:-local}..."
if [ "${APP_ENV}" = "production" ] || [ "${APP_ENV}" = "staging" ]; then
    echo "🔒 Caching config, routes, events, and views for production..."
    php artisan config:cache --no-interaction
    php artisan route:cache --no-interaction
    php artisan view:cache --no-interaction
    php artisan event:cache --no-interaction
else
    echo "🧹 Clearing config, routes, views, and application caches for development..."
    php artisan config:clear --no-interaction
    php artisan route:clear --no-interaction
    php artisan view:clear --no-interaction
    php artisan cache:clear --no-interaction
fi

# 8. Queue Workers Reset Signal (Signals Redis so running workers reboot gracefully)
echo "🔄 Signal queue workers to restart..."
php artisan queue:restart --no-interaction || true

# 9. Automatically assign permissions to non-root appuser (10001:10001) for runtime containers
echo "🔒 Applying ownership & permissions for appuser (10001:10001)..."
chown -R 10001:10001 /var/www/html 2>/dev/null || true
chmod -R 775 storage bootstrap/cache 2>/dev/null || true

echo "=================================================="
echo "✅ [Init Container] Initialization completed successfully!"
echo "=================================================="

exit 0
