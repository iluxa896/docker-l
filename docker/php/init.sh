#!/usr/bin/env bash
set -e

echo "=================================================="
echo "🚀 [Init Container] Starting Laravel Initialization"
echo "=================================================="

# 1. Composer Dependencies
echo "📦 Checking and installing Composer dependencies..."
composer install --no-interaction --prefer-dist --optimize-autoloader

# 2. Application Key Check
if [ -f .env ]; then
    if ! grep -q "^APP_KEY=base64:" .env || [ -z "$(grep "^APP_KEY=" .env | cut -d '=' -f2)" ]; then
        echo "🔑 APP_KEY is missing. Generating application key..."
        php artisan key:generate --force --no-interaction
    fi
fi

# 3. Storage Symlink
echo "🔗 Creating storage symlink..."
php artisan storage:link --no-interaction 2>/dev/null || true

# 4. Database Migrations
echo "🗄️ Running database migrations..."
php artisan migrate --force --no-interaction

# 5. Cache & Optimization based on APP_ENV
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

# 6. Queue Workers Reset Signal (Signals Redis so running workers reboot gracefully)
echo "🔄 Signal queue workers to restart..."
php artisan queue:restart --no-interaction || true

echo "=================================================="
echo "✅ [Init Container] Initialization completed successfully!"
echo "=================================================="

exit 0
