#!/bin/bash
set -eu
export HOME=/root
az login --identity --output none
az aks get-credentials -g rg-azurelab-dev -n aks-azurelab-dev --admin --overwrite-existing >/dev/null
SOURCE_DIR=$(mktemp -d /tmp/azurelab-gitops-XXXXXX)
GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch main https://github.com/duongdinhphong251-dev/AzureLab.git "$SOURCE_DIR"
kubectl kustomize "$SOURCE_DIR/gitops/app" >/tmp/azurelab-rendered.yaml
echo "GITOPS_COMMIT=$(git -C "$SOURCE_DIR" rev-parse HEAD)"
kubectl apply -f "$SOURCE_DIR/gitops/application.yaml"
echo GITOPS_APPLICATION_CREATED
