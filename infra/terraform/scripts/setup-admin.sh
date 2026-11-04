#!/bin/bash
set -eu

export HOME=/root
export DEBIAN_FRONTEND=noninteractive

# Đợi quá trình khởi tạo Ubuntu hoàn tất.
cloud-init status --wait

# Công cụ cơ bản và Docker từ kho Ubuntu.
apt-get update
apt-get install -y \
  ca-certificates \
  curl \
  git \
  unzip \
  docker.io \
  postgresql-client

systemctl enable --now docker

# Azure CLI từ bộ cài chính thức Microsoft.
if ! command -v az >/dev/null 2>&1; then
  curl -fsSL https://aka.ms/InstallAzureCLIDeb \
    -o /tmp/install-azure-cli.sh
  bash /tmp/install-azure-cli.sh
fi

# Đăng nhập bằng identity của VM, không dùng mật khẩu cá nhân.
az login --identity --output none

# Đọc phiên bản cluster để cài kubectl tương ứng.
AKS_VERSION=$(az aks show \
  --resource-group rg-azurelab-dev \
  --name aks-azurelab-dev \
  --query currentKubernetesVersion \
  --output tsv)

az aks install-cli --client-version "$AKS_VERSION"

# Lưu kubeconfig admin trên VM, không in nội dung ra log.
install -d -m 700 /root/.kube

az aks get-credentials \
  --resource-group rg-azurelab-dev \
  --name aks-azurelab-dev \
  --admin \
  --file /root/.kube/config \
  --overwrite-existing

chmod 600 /root/.kube/config

echo "=== Docker ==="
docker --version

echo "=== Azure CLI ==="
az version --query '"azure-cli"' --output tsv

echo "=== AKS nodes ==="
kubectl get nodes -o wide

echo "=== SETUP COMPLETE ==="