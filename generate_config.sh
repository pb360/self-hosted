#!/usr/bin/env bash
set -euo pipefail

# --- Argument validation ---
if [ $# -ne 1 ] || [ -z "$1" ]; then
    echo "Usage: $0 <hostname>"
    echo "Example: $0 chat.safespace.place"
    exit 1
fi

HOSTNAME="$1"

# --- Idempotency guard ---
if [ -f Revolt.toml ]; then
    echo "ERROR: Revolt.toml already exists. Remove it first if you want to regenerate."
    echo "  rm Revolt.toml .env .env.web"
    exit 1
fi

if [ -f .env ]; then
    echo "ERROR: .env already exists. Remove it first if you want to regenerate."
    exit 1
fi

echo "Generating config for: $HOSTNAME"

# --- Generate random credentials ---
MONGO_ROOT_USER="safespace"
MONGO_ROOT_PASS="$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)"
RABBITMQ_USER="safespace"
RABBITMQ_PASS="$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)"
MINIO_ROOT_USER="safespace"
MINIO_ROOT_PASS="$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)"

# --- Write .env (Docker Compose credentials) ---
cat > .env <<EOF
# Auto-generated credentials — DO NOT COMMIT
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

MONGO_ROOT_USER=${MONGO_ROOT_USER}
MONGO_ROOT_PASS=${MONGO_ROOT_PASS}
RABBITMQ_USER=${RABBITMQ_USER}
RABBITMQ_PASS=${RABBITMQ_PASS}
MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASS=${MINIO_ROOT_PASS}
EOF
chmod 600 .env
echo "Created .env with random credentials"

# --- Write .env.web (Caddy hostname) ---
cat > .env.web <<EOF
HOSTNAME=https://${HOSTNAME}
REVOLT_PUBLIC_URL=https://${HOSTNAME}/api
EOF
echo "Created .env.web"

# --- Write Revolt.toml ---
cat > Revolt.toml <<EOF
[database]
mongodb = "mongodb://${MONGO_ROOT_USER}:${MONGO_ROOT_PASS}@database/?authSource=admin"
redis = "redis://redis/"

[hosts]
app = "https://${HOSTNAME}"
api = "https://${HOSTNAME}/api"
events = "wss://${HOSTNAME}/ws"
autumn = "https://${HOSTNAME}/autumn"
january = "https://${HOSTNAME}/january"

[rabbit]
host = "rabbit"
port = 5672
username = "${RABBITMQ_USER}"
password = "${RABBITMQ_PASS}"

[files.s3]
endpoint = "http://minio:9000"
path_style_buckets = false
region = "minio"
access_key_id = "${MINIO_ROOT_USER}"
secret_access_key = "${MINIO_ROOT_PASS}"
default_bucket = "revolt-uploads"
EOF

# --- VAPID keys ---
openssl ecparam -name prime256v1 -genkey -noout -out vapid_private.pem 2>/dev/null
VAPID_PRIVATE="$(base64 -i vapid_private.pem | tr -d '\n' | tr -d '=')"
VAPID_PUBLIC="$(openssl ec -in vapid_private.pem -outform DER 2>/dev/null | tail --bytes 65 | base64 | tr '/+' '_-' | tr -d '\n' | tr -d '=')"
rm vapid_private.pem

cat >> Revolt.toml <<EOF

[pushd.vapid]
private_key = "${VAPID_PRIVATE}"
public_key = "${VAPID_PUBLIC}"
EOF

# --- File encryption key ---
ENCRYPTION_KEY="$(openssl rand -base64 32)"

cat >> Revolt.toml <<EOF

[files]
encryption_key = "${ENCRYPTION_KEY}"
EOF

echo ""
echo "=== Configuration generated successfully ==="
echo "Files created:"
echo "  .env          - Credentials (DO NOT COMMIT)"
echo "  .env.web      - Caddy hostname"
echo "  Revolt.toml   - Application config (contains secrets, DO NOT COMMIT)"
echo ""
echo "Next steps:"
echo "  1. Review .env and Revolt.toml"
echo "  2. docker compose up -d"
echo "  3. Verify: https://${HOSTNAME}"
