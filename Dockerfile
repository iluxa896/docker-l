# Stage 1: Build dependencies & Composer
FROM php:8.2-fpm-alpine AS builder

WORKDIR /var/www/html

# Install build dependencies
RUN apk add --no-cache \
    git \
    curl \
    libpng-dev \
    oniguruma-dev \
    libxml2-dev \
    libzip-dev \
    postgresql-dev \
    zip \
    unzip

# Install PHP extensions required by Laravel & PostgreSQL
RUN docker-php-ext-install pdo pdo_pgsql pdo_mysql mbstring exif pcntl bcmath gd zip opcache

# Install Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Stage 2: Production & Development Runner
FROM php:8.2-fpm-alpine AS runner

WORKDIR /var/www/html

# Install runtime dependencies & tini init process
RUN apk add --no-cache \
    tini \
    bash \
    libpng \
    libjpeg-turbo \
    freetype \
    libzip \
    libpq \
    icu-dev \
    fcgi

# Install runtime PHP extensions & PECL Redis with temporary build dependencies
RUN apk add --no-cache --virtual .build-deps \
    $PHPIZE_DEPS \
    postgresql-dev \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    libzip-dev \
    oniguruma-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) pdo pdo_pgsql pdo_mysql mbstring exif pcntl bcmath gd zip opcache \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && apk del .build-deps

# Copy custom PHP & OPcache configuration
COPY docker/php/custom.ini /usr/local/etc/php/conf.d/custom.ini

# Security: Create dedicated non-root user & group
RUN addgroup -S appgroup -g 10001 && \
    adduser -S appuser -u 10001 -G appgroup

# Create framework storage and cache directories with proper permissions
RUN mkdir -p /var/www/html/storage /var/www/html/bootstrap/cache && \
    chown -R appuser:appgroup /var/www/html

# Copy composer from builder
COPY --from=builder /usr/bin/composer /usr/bin/composer

# Use tini as init process to handle SIGTERM/SIGINT and reap zombie processes
ENTRYPOINT ["/sbin/tini", "--"]

USER appuser:appgroup

EXPOSE 9000

# Healthcheck to verify PHP-FPM responsiveness
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD SCRIPT_NAME=/ping SCRIPT_FILENAME=/ping REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:9000 || exit 1

CMD ["php-fpm"]
