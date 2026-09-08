FROM nginx:1.27

# Install certbot, certbot nginx plugin, cron, and curl with minimal layer footprint
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        certbot \
        python3-certbot-nginx \
        cron \
        curl \
        bash && \
    rm -rf /var/lib/apt/lists/*

# Copy static maintenance page template into nginx html directory
COPY maintenance.html.template /usr/share/nginx/html/maintenance.html.template

# Copy and prepare entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

HEALTHCHECK --interval=15s --timeout=5s --start-period=5s --retries=3 \
  CMD curl -f http://127.0.0.1/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
