# 가위바위보 아레나

Next.js로 만든 가위바위보 게임입니다. 모든 경기 결과를 저장하고 누적 승률과 최근 기록을 보여줍니다. 같은 앱을 AWS 서버리스와 EKS 컨테이너 아키텍처로 각각 배포할 수 있습니다.

- **EKS 라이브 데모:** http://a8a2767b13241474c9d985bd0e250c94-6736acbf7b3594e4.elb.ap-northeast-2.amazonaws.com
- **서버리스 라이브 데모:** http://rps-arena-719030485343-ap-northeast-2.s3-website.ap-northeast-2.amazonaws.com

## EKS 컨테이너 아키텍처

- EKS 1.36 관리형 클러스터와 `t3.medium` 노드 2대
- NLB → Nginx 웹 서버 2 replicas → Flask/Gunicorn 앱 서버 2 replicas
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

## 주요 기능

- 가위·바위·보 즉시 대결
- 키보드 단축키 `R`, `P`, `S`
- 데이터베이스 경기 기록 저장
- 누적 승·무·패 및 승률 계산
- 반응형 모바일/데스크톱 UI
