# 🍽️ 기억의 만찬 (Feast of Memory)

넷플릭스 예능 **〈데스게임〉**의 1라운드 게임 "기억의 만찬"을 iOS 게임으로 구현한 프로젝트입니다.

- **1인용** — AI와 암기 대결 (난이도 3단계). 규칙대로 **스크린샷 등 기록 행위를 감지하면 즉시 몰수패**(암기 위반)합니다.
- **2인용** — 방을 만들면 6자리 방코드가 생성되고, 친구가 코드를 입력해 입장하면 실시간 온라인 대결이 시작됩니다.

## 게임 규칙

> 커버로 덮인 20개의 접시 중, **같은 개수의 토큰이 들어 있는 두 접시**를 찾는 게임.

1. **배치 단계** — 각자 배치 토큰 45개를 들고 시작. 선 플레이어부터 번갈아 빈 접시에 토큰을 놓고 커버를 덮는다. 라운드마다 놓는 개수가 1개씩 늘어 9개까지(1+2+…+9=45), 접시 18개가 채워지고 2개는 빈 채(0개)로 남는다.
2. **암기** — 접시 속 토큰 개수는 오직 암기로만. 물리적으로 기록하면 몰수패.
3. **오픈 단계** — 각자 토큰 10개를 추가 지급. 선부터 제한 시간 1분 안에 접시 2개를 오픈한다.
   - 두 접시의 개수 **일치** → 내 토큰 1개를 두 접시 중 한 곳에 **추가** (접시의 개수가 변한다!)
   - **불일치** → 페널티 토큰 +1
   - **시간 초과** → 페널티 토큰 +2
4. **승리** — 자신의 토큰을 먼저 전부 소진한 플레이어가 승리.

## 프로젝트 구조

```
FeastOfMemory.xcodeproj      Xcode 16+ 프로젝트
FeastOfMemory/
├── App/FeastOfMemoryApp.swift
├── Game/
│   ├── GameEngine.swift     규칙 상태기계 (순수 값 타입 — 양쪽 기기에서 동일 재현)
│   ├── AIPlayer.swift       불완전 기억 모델 기반 AI (쉬움/보통/어려움)
│   ├── GameViewModel.swift  대국 진행, 60초 타이머, 공개/커버 연출, 암기 위반 처리
│   └── EngineSelfTest.swift 실제 방송 대국(이세돌 vs 홍진호) 리플레이 검증 (DEBUG)
├── Online/RoomClient.swift  WebSocket 클라이언트 (방 생성/코드 입장/무브 릴레이)
└── Views/                   홈, 대국 화면(4×5 접시 그리드), 온라인 로비, 규칙
server/
├── index.js                 2인용 릴레이 서버 (Node.js + ws)
└── test.js                  서버 통합 테스트
```

## 실행 방법

### iOS 앱 (Xcode 16 이상, iOS 17+)

```bash
open FeastOfMemory.xcodeproj
```

시뮬레이터나 기기에서 Run. DEBUG 빌드는 시작 시 엔진 셀프테스트(방송 대국 리플레이)를 자동 실행합니다.

### 2인용 서버

앱에는 기본 서버 주소(`OnlineConfig.defaultServerURLString`)가 내장되어 있어 사용자는 방 코드만 주고받으면 된다.

**클라우드 배포 (Render 무료 티어)**

1. [render.com](https://render.com) 가입 (GitHub 로그인)
2. New → **Blueprint** → 이 저장소 연결 → `render.yaml`이 자동 인식됨 → Deploy
3. 배포 완료 후 주소 확인 (서비스 이름이 `feast-of-memory`면 `wss://feast-of-memory.onrender.com`)
4. 주소가 다르면 `FeastOfMemory/Online/OnlineConfig.swift`의 기본 주소를 수정

무료 티어는 15분간 접속이 없으면 잠들며, 다음 접속 시 깨어나는 데 최대 1분 걸린다 (로비에 안내 문구 표시됨).

**로컬 실행/테스트**

```bash
cd server
npm install
npm start        # ws://0.0.0.0:8080  (헬스체크: http://localhost:8080)
npm test         # 통합 테스트
```

다른 서버를 쓰려면 `OnlineConfig.defaultServerURLString`을 수정해 빌드한다.

## TestFlight 배포 (Mac 불필요 — GitHub Actions)

`.github/workflows/testflight.yml`이 macOS 러너에서 빌드·서명 후 TestFlight에 업로드합니다.
인증서/프로비저닝 프로파일은 [fastlane match](https://docs.fastlane.tools/actions/match/)가
CI에서 자동 생성해 별도 private repo에 보관하므로 Mac이 전혀 필요 없습니다.

### 사전 준비 (1회)

1. **Apple Developer Program 가입** — [developer.apple.com](https://developer.apple.com) (연 $99)
2. **번들 ID 등록** — Certificates, Identifiers & Profiles → Identifiers → `+` → App IDs → `com.feastofmemory.game`
   (다른 ID를 쓰려면 `project.pbxproj`의 `PRODUCT_BUNDLE_IDENTIFIER`와 `fastlane/Fastfile`·`Appfile`의 `BUNDLE_ID`를 함께 수정)
3. **App Store Connect에 앱 생성** — [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → 나의 앱 → `+` → 위 번들 ID 선택
4. **App Store Connect API 키 생성** — Users and Access → Integrations → App Store Connect API → Team Keys → `+`
   (Role: **App Manager**) → Issuer ID·Key ID 기록, `.p8` 파일 다운로드(단 한 번만 가능!)
5. **Team ID 확인** — developer.apple.com → Membership 페이지
6. **인증서 보관용 private repo 생성** — 예: `ios-certificates` (빈 저장소)
7. **GitHub PAT 발급** — github.com → Settings → Developer settings → Personal access tokens (classic) → `repo` 권한

### GitHub Secrets 등록

이 저장소 → Settings → Secrets and variables → Actions → New repository secret:

| Secret | 값 |
|---|---|
| `APP_STORE_CONNECT_KEY_ID` | API 키의 Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | API 키의 Issuer ID |
| `APP_STORE_CONNECT_KEY` | `.p8` 파일을 **base64 인코딩**한 문자열 (`base64 -w0 AuthKey_XXX.p8`) |
| `APPLE_TEAM_ID` | Team ID (예: `AB12CD34EF`) |
| `MATCH_GIT_URL` | 인증서 repo 주소 (`https://github.com/<계정>/ios-certificates.git`) |
| `MATCH_GIT_BASIC_AUTHORIZATION` | `echo -n "<깃허브계정>:<PAT>" \| base64 -w0` 결과 |
| `MATCH_PASSWORD` | 인증서 암호화용 비밀번호 (아무거나 정해서 기억) |

### 실행

Actions 탭 → **TestFlight** → Run workflow. 성공하면 10~30분 뒤 App Store Connect →
TestFlight 탭에 빌드가 나타납니다. 내부 테스팅 그룹에 본인을 추가하고 iPhone의
**TestFlight 앱**에서 설치하세요.

> 💡 private repo의 macOS 러너는 분당 과금 배율이 10배라 무료 한도(월 2,000분)로는 매달 약 15~20회 빌드가 가능합니다. repo를 public으로 하면 무제한 무료입니다.

## 수익화 (AdMob + 광고 제거 IAP)

- **전면 광고** — 노출 지점은 "게임 종료 후 결과 화면에서 나갈 때" 한 곳뿐 (2판당 1회, 최소 3분 간격). 암기 게임 특성상 게임 도중에는 절대 노출하지 않는다.
- **광고 제거** — 비소모성 IAP `com.feastofmemory.game.removeads`. 설정(⚙️)에서 구매/복원. StoreKit 2 영수증 검증.
- 현재 광고 ID는 **Google 공식 테스트 ID**다. 출시 전 교체할 것:
  1. `FeastOfMemory/Info.plist`의 `GADApplicationIdentifier` → AdMob 앱 ID (`ca-app-pub-XXXX~YYYY`)
  2. `FeastOfMemory/Monetization/MonetizationConfig.swift`의 `interstitialAdUnitID` → 전면 광고 단위 ID (`ca-app-pub-XXXX/ZZZZ`)
- IAP 판매를 위해서는 App Store Connect에서 **유료 앱 계약(Paid Apps) + 은행/세금 등록**과 IAP 상품 등록이 선행되어야 한다.
- 광고 SDK 도입으로 App Privacy(개인정보 보호) 라벨에 광고 관련 데이터 수집 항목을 신고해야 한다.

## 구현 노트

- **엔진 검증**: 나무위키에 기록된 실제 대국 20수를 리플레이해 배치·판정·스코어가 모두 일치함을 확인했습니다. (참고: 위키 표의 9턴 스코어 "7:2"는 오기 — 홍진호는 9턴 연속 성공이므로 7:1이 정합)
- **온라인 동기화**: 서버는 무브를 해석하지 않는 단순 릴레이입니다. 엔진이 결정적(deterministic)이라 같은 무브 스트림이면 양쪽 상태가 항상 일치합니다. 선(先)은 서버가 랜덤 배정합니다.
- **암기 위반**: `UIApplication.userDidTakeScreenshotNotification` 감지 시 해당 플레이어 몰수패로 처리합니다.
