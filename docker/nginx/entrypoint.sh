#!/bin/bash
set -e

# Setup Let's Encrypt automated renewal cron job with explicit PATH (twice daily per EFF recommendation)
CRON_FILE="/etc/cron.d/certbot-renew"
if [ ! -f "$CRON_FILE" ]; then
    cat << 'EOF' > "$CRON_FILE"
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 3,15 * * * root certbot renew --quiet --post-hook 'nginx -s reload' >> /var/log/cron-certbot.log 2>&1
EOF
    chmod 0644 "$CRON_FILE"
fi

# Ensure Let's Encrypt acme-challenge directory exists
mkdir -p /var/www/acme-challenge

# Ensure default.conf exists from default.conf.example template if not present
if [ ! -f /etc/nginx/conf.d/default.conf ] && [ -f /etc/nginx/conf.d/default.conf.example ]; then
    cp /etc/nginx/conf.d/default.conf.example /etc/nginx/conf.d/default.conf
fi

# Start cron service in the background
service cron start

# Execute the container CMD (nginx)
exec "$@"
