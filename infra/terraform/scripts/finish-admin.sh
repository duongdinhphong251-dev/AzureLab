#!/bin/bash
[ -n "${BASH_VERSION:-}" ] || exec /bin/bash "$0" "$@"
set -euo pipefail

export HOME=/root

az login --identity --output none

# Đọc phiên bản đầy đủ đang chạy trên control plane.
AKS_VERSION=$(az aks show \
  --resource-group rg-azurelab-dev \
  --name aks-azurelab-dev \
  --query currentKubernetesVersion \
  --output tsv)

echo "AKS version: $AKS_VERSION"

# Dừng rõ ràng nếu chưa lấy được phiên bản đầy đủ.
if [[ ! "$AKS_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Chưa lấy được phiên bản x.y.z. Thông tin cluster:"
  az aks show \
    --resource-group rg-azurelab-dev \
    --name aks-azurelab-dev \
    --query '{configured:kubernetesVersion,running:currentKubernetesVersion}' \
    --output json
  exit 1
fi

az aks install-cli --client-version "$AKS_VERSION"

install -d -m 700 /root/.kube

az aks get-credentials \
  --resource-group rg-azurelab-dev \
  --name aks-azurelab-dev \
  --admin \
  --file /root/.kube/config \
  --overwrite-existing

chmod 600 /root/.kube/config

docker --version
kubectl get nodes -o wide

echo "=== SETUP COMPLETE ==="