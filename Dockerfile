# Stage 1: Official Composer Binary Provider (zero compilation overhead)
FROM composer:2 AS composer-bin

# Stage 2: Hardened Production & Development Runtime
FROM php:8.2-fpm-alpine AS runner

WORKDIR /var/www/html

# 1. Runtime system packages, Node.js, npm, composer prerequisites & process supervisor
RUN apk add --no-cache \
    tini \
    bash \
    curl \
    git \
    zip \
    unzip \
    nodejs \
    npm \
    libpng \
    libjpeg-turbo \
    freetype \
    libzip \
    libpq \
    icu-dev \
    fcgi

# 2. Compile required PHP extensions & PECL Redis within an ephemeral build layer
RUN apk add --no-cache --virtual .build-deps \
    $PHPIZE_DEPS \
    postgresql-dev \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    libzip-dev \
    oniguruma-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        pdo \
        pdo_pgsql \
        pdo_mysql \
        mbstring \
        exif \
        pcntl \
        bcmath \
        gd \
        zip \
        opcache \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && apk del .build-deps \
    && rm -rf /tmp/pear

# 3. Copy official Composer binary from stage 1 (zero compile overhead)
COPY --from=composer-bin /usr/bin/composer /usr/bin/composer

# 4. Copy custom PHP & OPcache configuration
COPY docker/php/custom.ini /usr/local/etc/php/conf.d/custom.ini

# 5. Security: Create dedicated unprivileged system user & group (UID/GID 10001)
RUN addgroup -S appgroup -g 10001 && \
    adduser -S appuser -u 10001 -G appgroup

# 6. Create framework storage & cache directories with unprivileged ownership
RUN mkdir -p /var/www/html/storage /var/www/html/bootstrap/cache && \
    chown -R appuser:appgroup /var/www/html

# 7. Tini init system intercepts OS signals and reaps child processes
ENTRYPOINT ["/sbin/tini", "--"]

# 8. Unprivileged security context
USER appuser:appgroup

EXPOSE 9000

# 9. Healthcheck to verify PHP-FPM responsiveness
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD SCRIPT_NAME=/ping SCRIPT_FILENAME=/ping REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:9000 || exit 1

CMD ["php-fpm"]
