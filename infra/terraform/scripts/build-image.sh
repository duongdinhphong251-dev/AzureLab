#!/bin/bash
[ -n "${BASH_VERSION:-}" ] || exec /bin/bash "$0" "$@"
set -euo pipefail
export HOME=/root
export GIT_TERMINAL_PROMPT=0

REPO_URL="https://github.com/duongdinhphong251-dev/AzureLab.git"
ACR_NAME="acrazurelabb436d920"
REGISTRY="${ACR_NAME}.azurecr.io"

echo "=== Checking GitHub access ==="

if ! git ls-remote "$REPO_URL" HEAD >/dev/null; then
  echo "Cannot read repository without credentials."
  echo "Check repository visibility or GitHub connectivity."
  exit 1
fi

SOURCE_DIR=$(mktemp -d /tmp/azurelab-build-XXXXXX)
git clone --depth 1 --branch main "$REPO_URL" "$SOURCE_DIR"

cd "$SOURCE_DIR"

# Dùng commit làm tag để biết image được build từ phiên bản nào.
TAG=$(git rev-parse --short=12 HEAD)

echo "=== Logging in to Azure and ACR ==="

az login --identity --output none
az acr login --name "$ACR_NAME" --output none

# Build logs nằm trên VM để tránh vượt giới hạn output Run Command.
LOG_DIR=/var/log/azurelab-build
mkdir -p "$LOG_DIR"

echo "=== Building backend ==="

if ! docker build \
  -t "$REGISTRY/azurelab-backend:$TAG" \
  ./app/backend >"$LOG_DIR/backend.log" 2>&1; then
  tail -n 35 "$LOG_DIR/backend.log"
  exit 1
fi

echo "=== Building frontend ==="

if ! docker build \
  -t "$REGISTRY/azurelab-frontend:$TAG" \
  ./app/frontend >"$LOG_DIR/frontend.log" 2>&1; then
  tail -n 35 "$LOG_DIR/frontend.log"
  exit 1
fi

echo "=== Pushing backend ==="

if ! docker push "$REGISTRY/azurelab-backend:$TAG" \
  >"$LOG_DIR/backend-push.log" 2>&1; then
  tail -n 25 "$LOG_DIR/backend-push.log"
  exit 1
fi

echo "=== Pushing frontend ==="

if ! docker push "$REGISTRY/azurelab-frontend:$TAG" \
  >"$LOG_DIR/frontend-push.log" 2>&1; then
  tail -n 25 "$LOG_DIR/frontend-push.log"
  exit 1
fi

echo "BUILD AND PUSH COMPLETE"
echo "BACKEND_IMAGE=$REGISTRY/azurelab-backend:$TAG"
echo "FRONTEND_IMAGE=$REGISTRY/azurelab-frontend:$TAG"