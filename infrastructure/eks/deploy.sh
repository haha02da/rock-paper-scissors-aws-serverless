#!/usr/bin/env bash
set -euo pipefail

eks_region="ap-northeast-2"
eks_cluster="rps-arena-eks"
eks_namespace="rps-arena"
eks_root=$(cd "$(dirname "$0")/../.." && pwd)
eks_account=$(aws sts get-caller-identity --query Account --output text)
eks_registry="${eks_account}.dkr.ecr.${eks_region}.amazonaws.com"
eks_tag=$(git -C "$eks_root" rev-parse --short HEAD)

for eks_repo in rps-arena-web rps-arena-api; do
  if ! aws ecr describe-repositories --region "$eks_region" --repository-names "$eks_repo" >/dev/null 2>&1; then
    aws ecr create-repository \
      --region "$eks_region" \
      --repository-name "$eks_repo" \
      --image-scanning-configuration scanOnPush=true \
      --tags Key=CreatedBy,Value=Codex >/dev/null
  fi
done

aws ecr get-login-password --region "$eks_region" | docker login --username AWS --password-stdin "$eks_registry"

eks_api_image="${eks_registry}/rps-arena-api:${eks_tag}"
eks_web_image="${eks_registry}/rps-arena-web:${eks_tag}"

docker buildx build --platform linux/amd64 --provenance=false -f "$eks_root/backend/Dockerfile" -t "$eks_api_image" --push "$eks_root"
docker buildx build --platform linux/amd64 --provenance=false -f "$eks_root/Dockerfile.web" -t "$eks_web_image" --push "$eks_root"

aws eks update-kubeconfig --region "$eks_region" --name "$eks_cluster"
kubectl apply -f "$eks_root/infrastructure/eks/k8s.yaml"

if ! kubectl get secret rps-db -n "$eks_namespace" >/dev/null 2>&1; then
  eks_db_password=$(openssl rand -hex 24)
  kubectl create secret generic rps-db \
    --namespace "$eks_namespace" \
    --from-literal=POSTGRES_USER=rps \
    --from-literal=POSTGRES_PASSWORD="$eks_db_password" \
    --from-literal=POSTGRES_DB=rps \
    --from-literal="DATABASE_URL=postgresql://rps:${eks_db_password}@postgres:5432/rps"
fi

kubectl set image deployment/rps-api api="$eks_api_image" -n "$eks_namespace"
kubectl set image deployment/rps-web web="$eks_web_image" -n "$eks_namespace"

kubectl rollout status statefulset/postgres -n "$eks_namespace" --timeout=10m
kubectl rollout status deployment/rps-api -n "$eks_namespace" --timeout=10m
kubectl rollout status deployment/rps-web -n "$eks_namespace" --timeout=10m

eks_attempt=1
eks_hostname=""
while [ "$eks_attempt" -le 60 ]; do
  eks_hostname=$(kubectl get service rps-web -n "$eks_namespace" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [ -n "$eks_hostname" ]; then break; fi
  sleep 10
  eks_attempt=$((eks_attempt + 1))
done

if [ -z "$eks_hostname" ]; then
  printf 'Load balancer hostname was not assigned within 10 minutes.\n' >&2
  exit 1
fi

printf '{\n  "cluster": "%s",\n  "region": "%s",\n  "url": "http://%s",\n  "apiImage": "%s",\n  "webImage": "%s"\n}\n' \
  "$eks_cluster" "$eks_region" "$eks_hostname" "$eks_api_image" "$eks_web_image" \
  > "$eks_root/eks-deployment-output.json"
cat "$eks_root/eks-deployment-output.json"
