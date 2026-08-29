#!/usr/bin/env bash
set -euo pipefail

karpenter_region="ap-northeast-2"
karpenter_cluster="rps-arena-eks"
karpenter_version="1.14.1"
karpenter_namespace="kube-system"
karpenter_service_account="karpenter"
karpenter_controller_role="${karpenter_cluster}-karpenter"
karpenter_stack="Karpenter-${karpenter_cluster}"
karpenter_account=$(aws sts get-caller-identity --query Account --output text)
karpenter_template=$(mktemp)

curl -fsSL \
  "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${karpenter_version}/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml" \
  -o "$karpenter_template"

aws cloudformation deploy \
  --region "$karpenter_region" \
  --stack-name "$karpenter_stack" \
  --template-file "$karpenter_template" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${karpenter_cluster}"

if ! aws iam get-role \
  --role-name AWSServiceRoleForEC2Spot >/dev/null 2>&1; then
  aws iam create-service-linked-role \
    --aws-service-name spot.amazonaws.com >/dev/null
fi

karpenter_trust_policy='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"pods.eks.amazonaws.com"},"Action":["sts:AssumeRole","sts:TagSession"]}]}'

if ! aws iam get-role --role-name "$karpenter_controller_role" >/dev/null 2>&1; then
  aws iam create-role \
    --role-name "$karpenter_controller_role" \
    --assume-role-policy-document "$karpenter_trust_policy" \
    --tags Key=CreatedBy,Value=Codex >/dev/null
fi

for karpenter_policy in \
  KarpenterControllerNodeLifecyclePolicy \
  KarpenterControllerIAMIntegrationPolicy \
  KarpenterControllerEKSIntegrationPolicy \
  KarpenterControllerInterruptionPolicy \
  KarpenterControllerZonalShiftPolicy \
  KarpenterControllerResourceDiscoveryPolicy; do
  aws iam attach-role-policy \
    --role-name "$karpenter_controller_role" \
    --policy-arn "arn:aws:iam::${karpenter_account}:policy/${karpenter_policy}-${karpenter_cluster}"
done

if ! aws eks describe-addon \
  --region "$karpenter_region" \
  --cluster-name "$karpenter_cluster" \
  --addon-name eks-pod-identity-agent >/dev/null 2>&1; then
  aws eks create-addon \
    --region "$karpenter_region" \
    --cluster-name "$karpenter_cluster" \
    --addon-name eks-pod-identity-agent \
    --addon-version v1.3.10-eksbuild.3 \
    --resolve-conflicts OVERWRITE >/dev/null
fi

aws eks wait addon-active \
  --region "$karpenter_region" \
  --cluster-name "$karpenter_cluster" \
  --addon-name eks-pod-identity-agent

karpenter_role_arn="arn:aws:iam::${karpenter_account}:role/${karpenter_controller_role}"
karpenter_association_count=$(aws eks list-pod-identity-associations \
  --region "$karpenter_region" \
  --cluster-name "$karpenter_cluster" \
  --namespace "$karpenter_namespace" \
  --service-account "$karpenter_service_account" \
  --query 'length(associations)' --output text)

if [ "$karpenter_association_count" = "0" ]; then
  aws eks create-pod-identity-association \
    --region "$karpenter_region" \
    --cluster-name "$karpenter_cluster" \
    --namespace "$karpenter_namespace" \
    --service-account "$karpenter_service_account" \
    --role-arn "$karpenter_role_arn" >/dev/null
fi

karpenter_node_role_arn="arn:aws:iam::${karpenter_account}:role/KarpenterNodeRole-${karpenter_cluster}"
if ! aws eks describe-access-entry \
  --region "$karpenter_region" \
  --cluster-name "$karpenter_cluster" \
  --principal-arn "$karpenter_node_role_arn" >/dev/null 2>&1; then
  aws eks create-access-entry \
    --region "$karpenter_region" \
    --cluster-name "$karpenter_cluster" \
    --principal-arn "$karpenter_node_role_arn" \
    --type EC2_LINUX >/dev/null
fi

karpenter_subnet_text=$(aws eks describe-cluster \
  --region "$karpenter_region" \
  --name "$karpenter_cluster" \
  --query 'cluster.resourcesVpcConfig.subnetIds[]' --output text)
read -r -a karpenter_subnets <<< "$karpenter_subnet_text"
karpenter_security_group=$(aws eks describe-cluster \
  --region "$karpenter_region" \
  --name "$karpenter_cluster" \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)

aws ec2 create-tags \
  --region "$karpenter_region" \
  --resources "${karpenter_subnets[@]}" "$karpenter_security_group" \
  --tags "Key=karpenter.sh/discovery,Value=${karpenter_cluster}"

printf 'Karpenter AWS prerequisites are ready for GitOps synchronization.\n'
