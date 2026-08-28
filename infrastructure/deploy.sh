#!/usr/bin/env bash
set -euo pipefail

deploy_region="ap-northeast-2"
deploy_account_id=$(aws sts get-caller-identity --query Account --output text)
deploy_table="rps-arena-games"
deploy_function="rps-arena-api-handler"
deploy_role="rps-arena-lambda-role"
deploy_api_name="rps-arena-api"
deploy_bucket="rps-arena-${deploy_account_id}-${deploy_region}"
deploy_root=$(cd "$(dirname "$0")/.." && pwd)
deploy_tmp=$(mktemp -d)
trap 'rm -rf "$deploy_tmp"' EXIT

if ! aws dynamodb describe-table --region "$deploy_region" --table-name "$deploy_table" >/dev/null 2>&1; then
  aws dynamodb create-table \
    --region "$deploy_region" \
    --table-name "$deploy_table" \
    --attribute-definitions AttributeName=session_id,AttributeType=S AttributeName=game_key,AttributeType=S \
    --key-schema AttributeName=session_id,KeyType=HASH AttributeName=game_key,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST \
    --tags Key=Name,Value="$deploy_table" Key=CreatedBy,Value=Codex >/dev/null
  aws dynamodb wait table-exists --region "$deploy_region" --table-name "$deploy_table"
fi

deploy_assume_policy='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
if ! aws iam get-role --role-name "$deploy_role" >/dev/null 2>&1; then
  aws iam create-role \
    --role-name "$deploy_role" \
    --assume-role-policy-document "$deploy_assume_policy" \
    --tags Key=CreatedBy,Value=Codex >/dev/null
  sleep 8
fi

deploy_table_arn="arn:aws:dynamodb:${deploy_region}:${deploy_account_id}:table/${deploy_table}"
deploy_role_policy=$(printf '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["dynamodb:PutItem","dynamodb:Query"],"Resource":"%s"},{"Effect":"Allow","Action":["logs:CreateLogStream","logs:PutLogEvents"],"Resource":"arn:aws:logs:%s:%s:log-group:/aws/lambda/%s:*"}]}' "$deploy_table_arn" "$deploy_region" "$deploy_account_id" "$deploy_function")
aws iam put-role-policy \
  --role-name "$deploy_role" \
  --policy-name rps-arena-runtime \
  --policy-document "$deploy_role_policy"

(cd "$deploy_root/infrastructure/lambda" && zip -q "$deploy_tmp/lambda.zip" handler.py)
deploy_role_arn="arn:aws:iam::${deploy_account_id}:role/${deploy_role}"
if aws lambda get-function --region "$deploy_region" --function-name "$deploy_function" >/dev/null 2>&1; then
  aws lambda update-function-code \
    --region "$deploy_region" \
    --function-name "$deploy_function" \
    --zip-file "fileb://$deploy_tmp/lambda.zip" >/dev/null
  aws lambda wait function-updated --region "$deploy_region" --function-name "$deploy_function"
  aws lambda update-function-configuration \
    --region "$deploy_region" \
    --function-name "$deploy_function" \
    --runtime python3.13 \
    --handler handler.handler \
    --role "$deploy_role_arn" \
    --timeout 10 \
    --memory-size 128 \
    --environment "Variables={TABLE_NAME=$deploy_table}" >/dev/null
else
  aws lambda create-function \
    --region "$deploy_region" \
    --function-name "$deploy_function" \
    --runtime python3.13 \
    --handler handler.handler \
    --role "$deploy_role_arn" \
    --timeout 10 \
    --memory-size 128 \
    --zip-file "fileb://$deploy_tmp/lambda.zip" \
    --environment "Variables={TABLE_NAME=$deploy_table}" \
    --tags Name="$deploy_function",CreatedBy=Codex >/dev/null
fi
aws lambda wait function-active-v2 --region "$deploy_region" --function-name "$deploy_function"

if ! aws logs describe-log-groups --region "$deploy_region" --log-group-name-prefix "/aws/lambda/$deploy_function" --query 'logGroups[?logGroupName==`/aws/lambda/'"$deploy_function"'`].logGroupName' --output text | grep -q .; then
  aws logs create-log-group --region "$deploy_region" --log-group-name "/aws/lambda/$deploy_function"
fi
aws logs put-retention-policy --region "$deploy_region" --log-group-name "/aws/lambda/$deploy_function" --retention-in-days 14

deploy_api_id=$(aws apigatewayv2 get-apis --region "$deploy_region" --query "Items[?Name=='$deploy_api_name'].ApiId | [0]" --output text)
if [ "$deploy_api_id" = "None" ]; then
  deploy_api_id=$(aws apigatewayv2 create-api \
    --region "$deploy_region" \
    --name "$deploy_api_name" \
    --protocol-type HTTP \
    --cors-configuration '{"AllowOrigins":["*"],"AllowMethods":["GET","POST","OPTIONS"],"AllowHeaders":["content-type"]}' \
    --tags Name="$deploy_api_name",CreatedBy=Codex \
    --query ApiId --output text)
fi

deploy_function_arn="arn:aws:lambda:${deploy_region}:${deploy_account_id}:function:${deploy_function}"
deploy_integration_id=$(aws apigatewayv2 get-integrations --region "$deploy_region" --api-id "$deploy_api_id" --query "Items[?IntegrationUri=='$deploy_function_arn'].IntegrationId | [0]" --output text)
if [ "$deploy_integration_id" = "None" ]; then
  deploy_integration_id=$(aws apigatewayv2 create-integration \
    --region "$deploy_region" \
    --api-id "$deploy_api_id" \
    --integration-type AWS_PROXY \
    --integration-uri "$deploy_function_arn" \
    --payload-format-version 2.0 \
    --query IntegrationId --output text)
fi

for deploy_route in 'GET /games' 'POST /games'; do
  deploy_route_id=$(aws apigatewayv2 get-routes --region "$deploy_region" --api-id "$deploy_api_id" --query "Items[?RouteKey=='$deploy_route'].RouteId | [0]" --output text)
  if [ "$deploy_route_id" = "None" ]; then
    aws apigatewayv2 create-route \
      --region "$deploy_region" \
      --api-id "$deploy_api_id" \
      --route-key "$deploy_route" \
      --target "integrations/$deploy_integration_id" >/dev/null
  fi
done

deploy_stage_id=$(aws apigatewayv2 get-stages --region "$deploy_region" --api-id "$deploy_api_id" --query 'Items[?StageName==`$default`].StageName | [0]' --output text)
if [ "$deploy_stage_id" = "None" ]; then
  aws apigatewayv2 create-stage --region "$deploy_region" --api-id "$deploy_api_id" --stage-name '$default' --auto-deploy >/dev/null
fi

deploy_statement_id="rps-arena-api-gateway"
if ! aws lambda get-policy --region "$deploy_region" --function-name "$deploy_function" --query Policy --output text 2>/dev/null | grep -q "$deploy_statement_id"; then
  aws lambda add-permission \
    --region "$deploy_region" \
    --function-name "$deploy_function" \
    --statement-id "$deploy_statement_id" \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${deploy_region}:${deploy_account_id}:${deploy_api_id}/*/*" >/dev/null
fi

deploy_api_url="https://${deploy_api_id}.execute-api.${deploy_region}.amazonaws.com"

if ! aws s3api head-bucket --bucket "$deploy_bucket" >/dev/null 2>&1; then
  aws s3api create-bucket \
    --region "$deploy_region" \
    --bucket "$deploy_bucket" \
    --create-bucket-configuration LocationConstraint="$deploy_region" >/dev/null
fi
aws s3api put-bucket-tagging \
  --bucket "$deploy_bucket" \
  --tagging 'TagSet=[{Key=Name,Value=rps-arena-web},{Key=CreatedBy,Value=Codex}]'
aws s3api put-public-access-block \
  --bucket "$deploy_bucket" \
  --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false
aws s3api put-bucket-website \
  --bucket "$deploy_bucket" \
  --website-configuration '{"IndexDocument":{"Suffix":"index.html"},"ErrorDocument":{"Key":"404.html"}}'
deploy_bucket_policy=$(printf '{"Version":"2012-10-17","Statement":[{"Sid":"PublicRead","Effect":"Allow","Principal":"*","Action":"s3:GetObject","Resource":"arn:aws:s3:::%s/*"}]}' "$deploy_bucket")
aws s3api put-bucket-policy --bucket "$deploy_bucket" --policy "$deploy_bucket_policy"

deploy_site_url="http://${deploy_bucket}.s3-website.${deploy_region}.amazonaws.com"
(cd "$deploy_root" && NEXT_PUBLIC_API_URL="$deploy_api_url" NEXT_PUBLIC_SITE_URL="$deploy_site_url" npm run build)
aws s3 sync "$deploy_root/out/" "s3://$deploy_bucket/" --delete --only-show-errors

printf '{\n  "region": "%s",\n  "siteUrl": "%s",\n  "apiUrl": "%s",\n  "bucket": "%s",\n  "table": "%s",\n  "function": "%s",\n  "apiId": "%s"\n}\n' \
  "$deploy_region" "$deploy_site_url" "$deploy_api_url" "$deploy_bucket" "$deploy_table" "$deploy_function" "$deploy_api_id" \
  > "$deploy_root/deployment-output.json"
cat "$deploy_root/deployment-output.json"
