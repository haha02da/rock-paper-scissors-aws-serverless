#!/usr/bin/env bash
set -euo pipefail

gitops_root=$(cd "$(dirname "$0")/../.." && pwd)
gitops_argocd_chart_version="10.4.1"
gitops_argocd_namespace="argocd"
gitops_monitoring_namespace="monitoring"

helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update argo

helm upgrade --install argo-cd argo/argo-cd \
  --version "$gitops_argocd_chart_version" \
  --namespace "$gitops_argocd_namespace" \
  --create-namespace \
  --values "$gitops_root/infrastructure/gitops/argocd-values.yaml" \
  --wait \
  --timeout 10m

kubectl create namespace "$gitops_monitoring_namespace" \
  --dry-run=client -o yaml | kubectl apply -f -

if ! kubectl get secret monitoring-grafana-admin \
  --namespace "$gitops_monitoring_namespace" >/dev/null 2>&1; then
  gitops_grafana_password=$(openssl rand -base64 24 | tr -d '\n')
  kubectl create secret generic monitoring-grafana-admin \
    --namespace "$gitops_monitoring_namespace" \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="$gitops_grafana_password"
fi

kubectl apply -f "$gitops_root/infrastructure/gitops/root-application.yaml"

printf 'Argo CD bootstrap completed. Applications will now reconcile from Git.\n'
