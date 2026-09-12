#!/bin/sh
set -eu

echo "=================================================="
echo "🚀 [Postgres Backup Service] Initializing daemon"
echo "=================================================="

# Ensure backup directory exists
mkdir -p /backups

# Verify connection to PostgreSQL before scheduling cron
echo "📡 Verifying PostgreSQL connectivity at ${POSTGRES_HOST}:${POSTGRES_PORT}..."
export PGPASSWORD="${POSTGRES_PASSWORD}"
until pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t 5; do
    echo "⏳ Waiting for PostgreSQL to be ready..."
    sleep 3
done
echo "✅ PostgreSQL connection confirmed."

# Configure cron schedule
CRON_SCHEDULE="${CRON_SCHEDULE:-0 2 * * *}"
echo "⏰ Configuring crontab: ${CRON_SCHEDULE} -> /usr/local/bin/backup.sh"

# Direct cron job output to PID 1 stdout/stderr so logs appear in Docker & Dozzle
cat <<EOF > /etc/crontabs/root
# Daily PostgreSQL Backup with strict 2-copy rotation
${CRON_SCHEDULE} /usr/local/bin/backup.sh > /proc/1/fd/1 2>/proc/1/fd/2
EOF

# Run an initial backup if BACKUP_ON_STARTUP is true
if [ "${BACKUP_ON_STARTUP:-false}" = "true" ]; then
    echo "🏁 BACKUP_ON_STARTUP is enabled. Running initial backup..."
    /usr/local/bin/backup.sh
fi

echo "🛡️ Crond scheduler started. Waiting for scheduled triggers..."

# Graceful SIGTERM/SIGINT shutdown handling for instant container stopping
trap 'echo "🛑 Received shutdown signal. Stopping crond..."; kill -TERM "$CROND_PID" 2>/dev/null; exit 0' TERM INT

/usr/sbin/crond -f -l 2 &
CROND_PID=$!
wait "$CROND_PID"
