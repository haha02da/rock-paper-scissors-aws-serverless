# 가위바위보 아레나

Next.js와 Supabase로 만든 가위바위보 게임입니다. 모든 경기 결과를 저장하고 누적 승률과 최근 기록을 보여줍니다.

## 로컬 실행

```bash
npm install
cp .env.example .env.local
npm run dev
```

`.env.local`에 Supabase 프로젝트 URL과 publishable key를 설정해야 합니다.

## 주요 기능

- 가위·바위·보 즉시 대결
- 키보드 단축키 `R`, `P`, `S`
- Supabase 경기 기록 저장
- 누적 승·무·패 및 승률 계산
- 반응형 모바일/데스크톱 UI
