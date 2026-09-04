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

# Copy and prepare entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
