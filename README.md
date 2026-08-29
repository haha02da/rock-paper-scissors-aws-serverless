# 가위바위보 아레나

Next.js로 만든 가위바위보 게임입니다. 모든 경기 결과를 저장하고 누적 승률과 최근 기록을 보여줍니다. 같은 앱을 AWS 서버리스와 EKS 컨테이너 아키텍처로 각각 배포할 수 있습니다.

- **EKS 라이브 데모:** http://a9f8b1c4fface4c7598361ab094c6475-fcdbc55666ff2ce2.elb.ap-northeast-2.amazonaws.com
- **서버리스 라이브 데모:** http://rps-arena-719030485343-ap-northeast-2.s3-website.ap-northeast-2.amazonaws.com

## EKS 컨테이너 아키텍처

- EKS 1.36 관리형 클러스터와 `t3.medium` 노드 2대
- NLB → Envoy Gateway → Nginx 웹 서버 2 replicas / Flask·Gunicorn 앱 서버 2 replicas
- PostgreSQL 17 StatefulSet 1 replica와 5Gi gp3 EBS 영구 볼륨
- ECR의 웹·API `linux/amd64` 컨테이너 이미지
- 기존 DynamoDB 경기 기록을 PostgreSQL로 중복 없이 이관하는 스크립트

## 서버리스 아키텍처

- S3 정적 웹사이트: Next.js 정적 빌드 호스팅
- API Gateway HTTP API: `GET /games`, `POST /games`
- Lambda (Python 3.13): 컴퓨터 선택, 승패 판정, 기록 조회 및 저장
- DynamoDB: 브라우저별 익명 세션의 전체 경기 기록
- CloudWatch Logs: Lambda 실행 로그(14일 보존)

## 로컬 실행

```bash
npm install
NEXT_PUBLIC_API_URL=https://your-api-id.execute-api.ap-northeast-2.amazonaws.com npm run dev
```

## EKS 서울 리전 배포

AWS CLI, Docker, `kubectl`, `eksctl` 인증 및 설치 후 실행합니다. 클러스터 생성과 앱 배포는 분리되어 있어 앱만 다시 배포할 때 클러스터를 재생성하지 않습니다.

```bash
chmod +x infrastructure/eks/*.sh
./infrastructure/eks/create-cluster.sh
./infrastructure/eks/deploy.sh
./infrastructure/eks/migrate-dynamodb.sh
```

배포 결과는 `eks-deployment-output.json`에 기록됩니다. 데이터 이관은 `ON CONFLICT DO NOTHING`을 사용하므로 다시 실행해도 기존 행이 중복되지 않습니다.

로컬에서 웹 서버, 앱 서버, PostgreSQL 컨테이너를 함께 실행하려면 다음 명령을 사용합니다.

```bash
docker compose up --build
```

## 서버리스 서울 리전 배포

AWS CLI 인증 후 다음 명령을 실행하면 인프라 생성, 프런트엔드 빌드, S3 업로드까지 한 번에 처리합니다.

```bash
chmod +x infrastructure/deploy.sh
./infrastructure/deploy.sh
```

배포 결과 URL과 리소스 이름은 `deployment-output.json`에 기록됩니다.

## GitOps 및 모니터링

Argo CD가 GitHub `main` 브랜치를 자동 동기화하고, `kube-prometheus-stack`으로 Prometheus와 Grafana를 설치합니다. Grafana와 Prometheus는 기본적으로 외부에 공개되지 않습니다.

```bash
chmod +x infrastructure/gitops/bootstrap.sh
./infrastructure/gitops/bootstrap.sh
```

Argo CD 접속:

```bash
kubectl port-forward -n argocd service/argo-cd-argocd-server 8081:443
kubectl get secret -n argocd argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 --decode; echo
```

브라우저에서 `https://localhost:8081`에 접속하고 사용자명 `admin`을 사용합니다.

Grafana 접속:

```bash
kubectl port-forward -n monitoring service/monitoring-grafana 3000:80
kubectl get secret -n monitoring monitoring-grafana-admin \
  -o jsonpath='{.data.admin-password}' | base64 --decode; echo
```

브라우저에서 `http://localhost:3000`에 접속하고 사용자명 `admin`을 사용합니다. Prometheus는 `kubectl port-forward -n monitoring service/monitoring-kube-prometheus-prometheus 9090:9090`으로 접근할 수 있습니다.

## 자동 확장

HPA는 웹 서버와 API 서버를 각각 최소 2개에서 최대 10개 Pod까지 CPU 60% 기준으로 조절합니다. Karpenter는 Pod를 배치할 공간이 부족할 때 Spot 또는 On-Demand EC2 노드를 추가하며 최대 32 vCPU와 64GiB로 제한됩니다.

Karpenter의 AWS IAM, Pod Identity, 인터럽션 큐 및 네트워크 태그를 준비한 후 Git 변경을 푸시합니다.

```bash
chmod +x infrastructure/gitops/bootstrap-karpenter.sh
./infrastructure/gitops/bootstrap-karpenter.sh
git add infrastructure README.md
git commit -m "Enable Karpenter and HPA autoscaling"
git push aws-origin main
```

상태 확인:

```bash
kubectl get hpa -n rps-arena
kubectl get deployment -n kube-system karpenter
kubectl get ec2nodeclass,nodepool,nodeclaim
kubectl get nodes -L karpenter.sh/nodepool,karpenter.sh/capacity-type
```

## Gateway API 트래픽 라우팅

Envoy Gateway가 Kubernetes Gateway API를 구현합니다. Gateway 프록시는 CPU 60% 기준으로 2~10개까지 자동 확장됩니다.

- `/api/*` → `rps-api:8080` (`/api` prefix 제거)
- `/*` → `rps-web:80`

```bash
kubectl get gatewayclass,gateway,httproute -A
kubectl get hpa -n envoy-gateway-system
kubectl get service -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-name=rps-gateway
```

가중치 기반 카나리 라우팅이 필요하면 `HTTPRoute`의 `backendRefs`에 백엔드를 추가하고 `weight` 비율을 변경합니다.

## 주요 기능

- 가위·바위·보 즉시 대결
- 키보드 단축키 `R`, `P`, `S`
- 데이터베이스 경기 기록 저장
- 누적 승·무·패 및 승률 계산
- 반응형 모바일/데스크톱 UI
