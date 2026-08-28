# 가위바위보 아레나

Next.js와 AWS 서버리스 서비스로 만든 가위바위보 게임입니다. 모든 경기 결과를 DynamoDB에 저장하고 누적 승률과 최근 기록을 보여줍니다.

**라이브 데모:** http://rps-arena-719030485343-ap-northeast-2.s3-website.ap-northeast-2.amazonaws.com

## 아키텍처

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

## AWS 서울 리전 배포

AWS CLI 인증 후 다음 명령을 실행하면 인프라 생성, 프런트엔드 빌드, S3 업로드까지 한 번에 처리합니다.

```bash
chmod +x infrastructure/deploy.sh
./infrastructure/deploy.sh
```

배포 결과 URL과 리소스 이름은 `deployment-output.json`에 기록됩니다.

## 주요 기능

- 가위·바위·보 즉시 대결
- 키보드 단축키 `R`, `P`, `S`
- DynamoDB 경기 기록 저장
- 누적 승·무·패 및 승률 계산
- 반응형 모바일/데스크톱 UI
