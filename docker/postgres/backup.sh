#!/bin/sh
set -euo pipefail

# Configuration defaults
POSTGRES_HOST="${POSTGRES_HOST:-postgres}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-laravel}"
POSTGRES_USER="${POSTGRES_USER:-laravel_user}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"
BACKUP_MAX_KEEP="${BACKUP_MAX_KEEP:-2}"

echo "=================================================="
echo "🕒 [$(date -u +"%Y-%m-%d %H:%M:%S UTC")] Starting PostgreSQL Database Backup"
echo "   Target DB: ${POSTGRES_DB} on ${POSTGRES_HOST}:${POSTGRES_PORT}"
echo "   Storage Dir: ${BACKUP_DIR}"
echo "   Retention Limit: ${BACKUP_MAX_KEEP} backup(s)"
echo "=================================================="

# Ensure backup destination directory exists
mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date -u +"%Y%m%d_%H%M%S")
TEMP_FILE="${BACKUP_DIR}/.backup_${TIMESTAMP}.sql.gz.tmp"
FINAL_FILE="${BACKUP_DIR}/backup_${TIMESTAMP}.sql.gz"

# Cleanup trap for partial / temporary files
cleanup() {
    EXIT_CODE=$?
    if [ -f "$TEMP_FILE" ]; then
        echo "⚠️ Cleaning up incomplete temporary file: ${TEMP_FILE}"
        rm -f "$TEMP_FILE"
    fi
    if [ "$EXIT_CODE" -ne 0 ]; then
        echo "❌ Backup process failed with exit code ${EXIT_CODE}"
    fi
    exit "$EXIT_CODE"
}
trap cleanup EXIT INT TERM

# Export password securely for pg_dump without CLI argument exposure
export PGPASSWORD="$POSTGRES_PASSWORD"

echo "📦 Executing pg_dump and compressing with gzip..."
/usr/local/bin/pg_dump \
    -h "$POSTGRES_HOST" \
    -p "$POSTGRES_PORT" \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" \
    --no-owner \
    --no-acl \
    | gzip -9 > "$TEMP_FILE"

# Sanity Check: Ensure temporary file exists and is non-empty
if [ ! -s "$TEMP_FILE" ]; then
    echo "❌ CRITICAL: Dump file was not created or is empty: ${TEMP_FILE}"
    rm -f "$TEMP_FILE"
    exit 1
fi

FILE_SIZE_HUMAN=$(du -h "$TEMP_FILE" | cut -f1)
FILE_SIZE_BYTES=$(wc -c < "$TEMP_FILE" | tr -d ' ')

# Atomically rename to final backup filename
mv "$TEMP_FILE" "$FINAL_FILE"
chmod 0640 "$FINAL_FILE"

echo "✅ Backup successfully created: $(basename "$FINAL_FILE") (${FILE_SIZE_HUMAN}, ${FILE_SIZE_BYTES} bytes)"

# ==============================================================================
# Strict Retention Rotation: Keep strictly at most $BACKUP_MAX_KEEP copies
# ==============================================================================
echo "🔄 Checking backup rotation (maximum allowed: ${BACKUP_MAX_KEEP})..."

# List all existing valid backups sorted alphabetically reverse (ISO timestamp = chronological descending)
# Only consider final complete backups matching pattern backup_*.sql.gz
BACKUP_FILES=$(find "$BACKUP_DIR" -maxdepth 1 -name "backup_*.sql.gz" -type f | sort -r)
TOTAL_COUNT=$(echo "$BACKUP_FILES" | grep -c "backup_" || true)

echo "   Current backup count: ${TOTAL_COUNT}"

if [ "$TOTAL_COUNT" -gt "$BACKUP_MAX_KEEP" ]; then
    EXCESS_COUNT=$((TOTAL_COUNT - BACKUP_MAX_KEEP))
    echo "   Found ${EXCESS_COUNT} obsolete backup(s) exceeding retention limit. Pruning..."

    # Extract all files starting from index (BACKUP_MAX_KEEP + 1)
    FILES_TO_DELETE=$(echo "$BACKUP_FILES" | tail -n "+$((BACKUP_MAX_KEEP + 1))")

    echo "$FILES_TO_DELETE" | while IFS= read -r file; do
        if [ -n "$file" ] && [ -f "$file" ]; then
            echo "   🗑️ Deleting old backup: $(basename "$file")"
            rm -f "$file"
        fi
    done
else
    echo "   No rotation needed. Count (${TOTAL_COUNT}) <= limit (${BACKUP_MAX_KEEP})."
fi

# Final Assertion Verification: Total files MUST be <= BACKUP_MAX_KEEP
FINAL_COUNT=$(find "$BACKUP_DIR" -maxdepth 1 -name "backup_*.sql.gz" -type f | grep -c "backup_" || true)
if [ "$FINAL_COUNT" -gt "$BACKUP_MAX_KEEP" ]; then
    echo "❌ FATAL: Rotation invariant violated! Count on disk (${FINAL_COUNT}) exceeds limit (${BACKUP_MAX_KEEP})!"
    exit 1
fi

echo "=================================================="
echo "🎉 Backup & rotation cycle completed successfully!"
echo "   Retained archives (${FINAL_COUNT}/${BACKUP_MAX_KEEP}):"
find "$BACKUP_DIR" -maxdepth 1 -name "backup_*.sql.gz" -type f | sort -r | while IFS= read -r file; do
    echo "   • $(basename "$file") ($(du -h "$file" | cut -f1))"
done
echo "=================================================="
