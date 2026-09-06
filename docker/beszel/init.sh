#!/bin/sh
set -e

EMAIL="${BESZEL_USER_EMAIL:-admin@example.com}"
PASSWORD="${BESZEL_USER_PASSWORD:-secret_password}"
DATA_DIR="/beszel_data"
DB_FILE="$DATA_DIR/data.db"

mkdir -p "$DATA_DIR"

# 1. If private key exists, extract public key for beszel-agent
if [ -f "$DATA_DIR/id_ed25519" ]; then
    echo "[beszel-init] Extracting Ed25519 public key for agent authentication..."
    ssh-keygen -y -f "$DATA_DIR/id_ed25519" > "$DATA_DIR/id_ed25519.pub" 2>/dev/null || true
    chmod 644 "$DATA_DIR/id_ed25519.pub" 2>/dev/null || true
fi

if [ ! -f "$DB_FILE" ]; then
    echo "[beszel-init] Initializing: database $DB_FILE does not exist yet."
    echo "[beszel-init] Beszel Hub will provision the initial admin user ($EMAIL) on first boot."
    exit 0
fi

echo "[beszel-init] Existing database detected at $DB_FILE."
echo "[beszel-init] Synchronizing admin credentials from environment for '$EMAIL'..."

# Generate bcrypt hash compatible with PocketBase / Beszel
BCRYPT_HASH=$(htpasswd -bnBC 10 "" "$PASSWORD" | tr -d ':\n')

# 2. Update the 'users' collection record (used by the Beszel Hub Dashboard)
sqlite3 "$DB_FILE" <<EOF
UPDATE users 
SET email = '$EMAIL', 
    password = '$BCRYPT_HASH',
    updated = strftime('%Y-%m-%d %H:%M:%f', 'now')
WHERE id = (SELECT id FROM users LIMIT 1);
EOF

# 3. If '_superusers' table exists, synchronize it as well
SUPERUSERS_EXISTS=$(sqlite3 "$DB_FILE" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='_superusers';" 2>/dev/null || echo "0")
if [ "$SUPERUSERS_EXISTS" = "1" ]; then
    sqlite3 "$DB_FILE" <<EOF
UPDATE _superusers 
SET email = '$EMAIL', 
    password = '$BCRYPT_HASH',
    updated = strftime('%Y-%m-%d %H:%M:%f', 'now')
WHERE id = (SELECT id FROM _superusers LIMIT 1);
EOF
fi

# 4. Invoke binary superuser upsert for PocketBase internal metadata alignment
/usr/local/bin/beszel superuser upsert "$EMAIL" "$PASSWORD" --dir="$DATA_DIR" 2>/dev/null || true

echo "[beszel-init] Credentials synchronized successfully. Starting Beszel Hub."
exit 0
