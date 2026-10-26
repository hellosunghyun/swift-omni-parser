# OmniParser 회귀 테스트 구성안

> 개인 절대 경로는 [로컬 검증 경로 별칭](RESEARCH_PATHS.md)으로 표기했다. 원시 로그·진단 덤프는 저장소에 포함하지 않는다.

> 후속 작업: [운영 회귀 테스트 반영](REGRESSION_TESTS.md), [Ream/OdrCore XLS 수정 검증](ODR_XLS_FIX_VALIDATION.md). 아래는 이전 단계 기록이며, Ream 수정 후 기존 앱 크기·성능을 다시 측정한 결과는 아닙니다.

2026-10-26. **제안이며 운영 Package.swift·테스트 타깃에는 아직 적용하지 않았다.** 기존 제품 OmniParser와 iOS 27.0/Swift 5.0/tools 6.2를 유지한다. 새 테스트 프레임워크나 운영 의존성은 추가하지 않는다.

## 최소 구성

```text
Tests/OmniParserTests/
  APIContractTests.swift
  FormatRegressionTests.swift
  OfficeSourceTruthTests.swift
  ResourceAndCancellationTests.swift
  Fixtures/
    Manifest.json
    GoldenAssertions.json
    Generated/
    RealWorld/
    Licenses/
```

기존 XCTest 방식과 Bundle.module 리소스를 사용한다. Package.swift의 targets에 다음 한 타깃을 추가한다. 별도 Core 제품이나 Ream 제품, UI 앱은 만들지 않는다.

```swift
.testTarget(
  name: "OmniParserTests",
  dependencies: ["OmniParser"],
  resources: [.copy("Fixtures")]
)
```

생성 fixture와 외부 fixture를 같은 manifest에서 출처·원본/현재 해시·변환 이력으로 구분한다. 외부 원본의 LICENSE/NOTICE를 함께 보존한다. 기존 앱의 샘플 manifest는 출발점이며 자산별 재배포 확인 없이 공개 패키지로 일괄 복사하지 않는다. 이번 구성 제안에 외부 다운로드는 없다.

## 테스트에서 확인할 것

| 파일 | 핵심 assertion |
|---|---|
| APIContractTests | 전체 텍스트와 블록의 일관성, readingOrder, 독립 이미지/OCR 4조합, URL/Data/CGImage 입력, 혼합 배치 순서·개별 실패·진행 종료 |
| FormatRegressionTests | 기존 65개 고유 파일 corpus 및 자체 구조 4파일. 텍스트·표·셀·앵커·그림 픽셀·제공 가능한 신뢰도. TIFF 프레임·PDF 일반/스캔/혼합·Word 각주·슬라이드 상속/목록·셀 서식의 구체적인 기대값 |
| OfficeSourceTruthTests | XLS 워크시트와 chart substream 구분, 동일 시트 셀 주소 유일성, 실제 문자열/숫자의 원본 주소, DOCX 각주 참조, 표시 형식과 병합/빈 셀 정책 |
| ResourceAndCancellationTests | 중간/배치/OCR 취소, 부분 결과 보존, 접근/임시 파일 수명, 손상·암호화·ZIP 실제 해제량·CRC·경로·엔티티·픽셀·동시성 한도 |

원본 정답 assertion과 기존 엔진 fingerprint 비교를 구별한다. 기존 결과를 그대로 golden으로 승인하면 발견한 XLS 오답까지 정답으로 고정한다. 전체 해시 차이는 조사 신호로 사용하고, 의미상 중요한 본문/셀/위치는 원본 근거가 있는 assertion으로 검증한다. 그림 픽셀과 PNG 인코딩 바이트를 구분하며 ICC 변동을 텍스트·위치 검사까지 느슨하게 만드는 이유로 쓰지 않는다.

공백 전체 정규화나 숫자/목록 마커 삭제를 전역 비교 규칙으로 두지 않는다. 공백과 표시 형식도 의미가 있을 수 있으므로 허용 차이는 해당 fixture/필드에만 근거와 함께 둔다. OCR 글꼴/OS 차이를 고려하되 해당 문구·방향·위치·제공 신뢰도를 실제로 검사한다.

## 실행과 CI

제안 타깃을 추가한 뒤 xcodebuild -list로 생성 scheme을 확인한다. 기존 실험 패키지는 같은 XCTest/resource 방식으로 실행했지만, 운영 저장소에 이 타깃을 추가한 빌드 자체는 아직 NOT_RUN이다.

```bash
xcodebuild -list
xcodebuild test -scheme OmniParser \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=NO
swiftlint lint --strict
```

새 CI는 기존 운영 빌드/린트와 별도로 테스트를 실행하게 한다. iOS 27 SDK를 갖춘 runner와 해당 Simulator가 필요하다. 출처 모호한 임의 이미지/문서를 실행 시 다운로드하는 단계는 넣지 않는다. 대용량·실기기 성능은 기능 회귀와 구분된 실행으로 남기고, Simulator의 절대 시간/RSS를 범용 합격 기준으로 고정하지 않는다.

## 현재 검증 및 적용 전 조건

- 별도 SplitParity 하네스에서 동일 public API 기반 83결과 비교를 이미 실행했다. 분리 전후 의미 결과는 83/83 일치했다.
- 이번에 추가한 11문서 진단 테스트는 현재/Ream 각 1개 PASS다.
- **새 원본 정답 테스트는 현재 엔진 BASELINE_FAIL, Ream FAIL**이다. 기존 엔진은 chart cache로 잘못된 셀 값, Ream은 실제 값과 chart cache의 같은 주소 중복을 검출했다. 이 테스트를 정상 PASS로 보고하지 않는다.
- 적용 시 이 결함을 수정하거나 명시적 미해결 항목으로 남겨야 한다. 실패를 감추는 skip/expected-failure, 잘못된 결과로 기대값 변경은 제안하지 않는다.
- 65문서 자산·고지의 재배포 확인과 생성 fixture 이관을 완료한 다음 운영 타깃/CI에 연결한다. 구성 승인 없이 운영 manifest·구조를 변경하지 않았다.
- Ream 진단용 JS 번들·원문 덤프·LibreOffice 변환본·대형 실험 로그는 배포 리소스나 기본 테스트 자산에 포함하지 않는다. 필요한 회귀 입력과 정답·출처만 보존한다.

실제 진단·실패 재현 코드는 `${OMNI_RESEARCH_ROOT}/SplitParity/{after,ream}/Tests/ParityTests/`에 있다. 운영 엔진에서 즉시 실행 가능한 테스트 하네스이지만 캐시 폴더 자체를 공개 테스트 배포본으로 취급하지 않는다.
