#!/bin/bash
[ -n "${BASH_VERSION:-}" ] || exec /bin/bash "$0" "$@"
set -euo pipefail
export HOME=/root
echo 'DATABASE PREPARATION START'
trap 'echo DATABASE_PREPARATION_FAILED >&2' ERR

# Các biến được truyền bằng Managed Run Command.
: "${PGHOST:?Missing PGHOST}"
: "${VAULT_NAME:?Missing VAULT_NAME}"
: "${ADMIN_PASSWORD:?Missing ADMIN_PASSWORD}"

az login --identity --output none

# File chứa secret chỉ cho root đọc; tự xóa khi script kết thúc.
umask 077
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Verify the administrator login before saving its password.
export PGUSER=labadmin
export PGDATABASE=azurelab
export PGPASSWORD="$ADMIN_PASSWORD"
export PGSSLMODE=verify-full
export PGSSLROOTCERT=/etc/ssl/certs/ca-certificates.crt
export PGCONNECT_TIMEOUT=10
psql -X --quiet --set=ON_ERROR_STOP=1 --command='SELECT 1;' >/dev/null
echo 'Administrator login verified'
# Lưu mật khẩu admin vào Key Vault.
printf '%s' "$ADMIN_PASSWORD" > "$WORK_DIR/admin-password"

az keyvault secret set \
  --vault-name "$VAULT_NAME" \
  --name postgres-admin-password \
  --file "$WORK_DIR/admin-password" \
  --output none

# Dùng lại mật khẩu app nếu đã chuẩn bị trước đó.
SECRET_EXISTS=$(az keyvault secret list \
  --vault-name "$VAULT_NAME" \
  --query "[?name=='postgres-app-password'].name | [0]" \
  --output tsv)

if [ -n "$SECRET_EXISTS" ]; then
  APP_PASSWORD=$(az keyvault secret show \
    --vault-name "$VAULT_NAME" \
    --name postgres-app-password \
    --query value --output tsv)
else
  APP_PASSWORD=$(openssl rand -hex 24)

  printf '%s' "$APP_PASSWORD" > "$WORK_DIR/app-password"

  az keyvault secret set \
    --vault-name "$VAULT_NAME" \
    --name postgres-app-password \
    --file "$WORK_DIR/app-password" \
    --output none
fi

export PGUSER=labadmin
export PGDATABASE=azurelab
export PGPASSWORD="$ADMIN_PASSWORD"
export PGSSLMODE=verify-full
export PGSSLROOTCERT=/etc/ssl/certs/ca-certificates.crt
export PGCONNECT_TIMEOUT=10

# Tạo role nếu chưa có, rồi đồng bộ mật khẩu và quyền.
psql -X --quiet --set=ON_ERROR_STOP=1 \
  --set=app_password="$APP_PASSWORD" <<'SQL'
SELECT 'CREATE ROLE azurelab_app LOGIN'
WHERE NOT EXISTS (
  SELECT 1 FROM pg_roles WHERE rolname = 'azurelab_app'
)
\gexec

SELECT format(
  'ALTER ROLE azurelab_app PASSWORD %L',
  :'app_password'
)
\gexec

GRANT CONNECT ON DATABASE azurelab TO azurelab_app;
GRANT USAGE, CREATE ON SCHEMA public TO azurelab_app;
SQL

# Kiểm tra đăng nhập bằng tài khoản app.
PGUSER=azurelab_app PGPASSWORD="$APP_PASSWORD" \
  psql -X --set=ON_ERROR_STOP=1 \
  --command="SELECT current_user, current_database();"

# Tạo connection string cho backend, không in secret ra log.
export APP_PASSWORD
export CONNECTION_FILE="$WORK_DIR/database-url"

python3 <<'PY'
import os
from pathlib import Path
from urllib.parse import quote

password = quote(os.environ["APP_PASSWORD"], safe="")
host = os.environ["PGHOST"]

url = (
    f"postgresql+psycopg://azurelab_app:{password}@{host}:5432/azurelab"
    "?sslmode=verify-full"
    "&sslrootcert=/etc/ssl/certs/ca-certificates.crt"
)

Path(os.environ["CONNECTION_FILE"]).write_text(url)
PY

az keyvault secret set \
  --vault-name "$VAULT_NAME" \
  --name database-url \
  --file "$WORK_DIR/database-url" \
  --output none

echo "DATABASE PREPARATION COMPLETE"