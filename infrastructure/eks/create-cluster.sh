#!/usr/bin/env bash
set -euo pipefail

eks_region="ap-northeast-2"
eks_cluster="rps-arena-eks"
eks_root=$(cd "$(dirname "$0")/../.." && pwd)

if aws eks describe-cluster --region "$eks_region" --name "$eks_cluster" >/dev/null 2>&1; then
  printf 'EKS cluster %s already exists.\n' "$eks_cluster"
else
  eksctl create cluster -f "$eks_root/infrastructure/eks/cluster.yaml"
fi

aws eks update-kubeconfig --region "$eks_region" --name "$eks_cluster"
kubectl get nodes -o wide
