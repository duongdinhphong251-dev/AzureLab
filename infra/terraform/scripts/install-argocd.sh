#!/bin/bash
set -eu
export HOME=/root
az login --identity --output none
az aks get-credentials -g rg-azurelab-dev -n aks-azurelab-dev --admin --overwrite-existing >/dev/null
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# Resolve the stable channel to a commit and record it for reproducibility.
ARGO_COMMIT=f55566445ee3a2a4f3339bf10df0f6bc1ecf7f23
test -n "$ARGO_COMMIT"
echo "ARGOCD_INSTALL_COMMIT=$ARGO_COMMIT"
kubectl apply --server-side --force-conflicts -n argocd -f "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGO_COMMIT/manifests/install.yaml" >/var/log/azurelab-argocd-install.log 2>&1 || { tail -n 35 /var/log/azurelab-argocd-install.log; exit 1; }
kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=120s
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=600s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=600s
kubectl -n argocd rollout status deployment/argocd-server --timeout=600s
echo ARGOCD_READY
