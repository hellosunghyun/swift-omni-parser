# OmniParser

> **Draft — 개발·검토 중인 저장소입니다.** API·의존성·패키지 구성이 바뀔 수 있습니다. 현재 자동 CI·안정 버전 릴리스가 없으며, 실서비스 도입 전 기능 검증과 배포 라이선스 검토가 필요합니다.

로컬 문서의 본문·표·삽입 이미지와 OCR 결과를 추출하는 iOS용 Swift Package입니다.

- 저장소: `hellosunghyun/swift-omni-parser`
- 제품·모듈: `OmniParser`
- iOS 27.0+, iOS 27 SDK를 제공하는 Xcode 필요
- 패키지 tools 버전 6.2, Swift 언어 모드 5.0
- 화면·TCA·영구 저장과 독립된 API
- 문서 업로드와 외부 참조 이미지 자동 다운로드 없음

## 설치

```swift
.package(
  url: "https://github.com/hellosunghyun/swift-omni-parser.git",
  exact: "0.1.0-alpha.1"
)
```

사용할 타깃의 의존성에 `.product(name: "OmniParser", package: "swift-omni-parser")`를 추가합니다. `0.1.0-alpha.1`은 개발·검토 중인 프리릴리즈입니다. 소비 프로젝트의 `Package.resolved`도 함께 관리합니다.

## 사용법

```swift
import OmniParser

// 기본값: 네이티브 본문·표만 추출합니다.
let result = try await DocumentParser.parse(.url(fileURL))
let text = result.fullText // 실제 문서 본문은 진단 로그에 기록하지 않는 것을 권장합니다.

// 스캔 문서·이미지의 텍스트가 필요할 때 OCR을 켭니다.
let recognized = try await DocumentParser.parse(
  .data(data, fileName: "document.pdf"),
  options: .init(extractImages: true, performOCR: true)
)

// 입력 순서대로 문서별 성공·실패를 돌려줍니다.
let outcomes = try await DocumentParser.parseBatch(
  inputs,
  options: .init(maximumConcurrentDocuments: 2),
  progress: { event in
    // UI 갱신은 호출 측에서 MainActor로 전달합니다.
  }
)
```

`extractImages`와 `performOCR`은 독립적인 옵션이며 모두 기본값이 `false`입니다. 이미지 단독 입력과 스캔 전용 PDF는 OCR을 켜야 텍스트를 얻을 수 있습니다. 라이브러리는 입력 URL·본문을 로그에 기록하지 않습니다.

## 형식과 처리 경로

| 형식 | 구현 경로 |
| --- | --- |
| TXT·CSV·JSON·XML | Foundation 및 형식별 구조 추출 |
| HTML | SwiftSoup DOM의 본문·제목·목록·표와 내장/로컬 참조 그림. CSS 조판·스크립트 실행 제외 |
| Markdown | 줄 단위 제목·본문·파이프 표와 인라인 그림 참조. CommonMark 전체 방언·참조형 그림은 미지원 |
| RTF | Foundation 문단·표·병합 셀 + 내장 래스터 그림·선택적 OCR. 독립 WMF/EMF/DIB 렌더링 제외 |
| JPEG·PNG·HEIC·TIFF·CGImage | ImageIO·Vision, 다중 프레임과 방향 처리 |
| PDF | 페이지 좌표·선/정렬 기반 표 추정·표시된 그림 영역의 래스터 추출·선택적 OCR. 원본 이미지 스트림 반환은 아님 |
| DOC·PPT | OfficeOxide, OfficeArt 그림 보완 |
| DOCX·XLS·XLSX·PPTX | OpenDocument.core |
| HWP·HWPX | CoreHwp 본문·표·문단/셀 그림 앵커. 지원 래스터 BinData 추출·OCR, 페이지 조판 순서는 경고 |

인코딩 판별은 BOM·UTF-16 패턴과 레거시 문자셋 휴리스틱을 사용합니다. JSON 객체 키는 정렬하며 XML은 엔티티 확장을 허용하지 않습니다. Office는 백엔드가 제공하는 문서 요소를 추출하며, 제공하지 않는 헤더·각주·도형 앵커·좌표까지 완전하게 복원하지 않습니다.

표는 기존 구현의 처리 경로를 나타내며 모든 문서의 완전한 복원을 보장하지 않습니다. 위치를 복원하지 못하거나 일부 요소가 실패하면 경고를 반환합니다. 이미지 속 표의 셀 구조 복원, 암호 해제, 파일 형식 변환은 제공하지 않습니다. 구체적인 옵션·위치·읽기 순서 제약은 [API 문서](Documentation/API.md)를 확인하세요.

## 빌드

```bash
xcodebuild build -scheme OmniParser \
  -destination 'generic/platform=iOS Simulator' -skipMacroValidation

xcodebuild build -scheme OmniParser \
  -destination 'generic/platform=iOS' -skipMacroValidation CODE_SIGNING_ALLOWED=NO

swiftlint lint --strict
```

XCTest 타깃 `OmniParserTests`와 출처·고지가 포함된 회귀 샘플을 추가했습니다.

```bash
xcodebuild test -scheme OmniParser \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipMacroValidation -parallel-testing-enabled NO -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=NO
```

기본 의존성은 XLS 중첩 차트 수정을 포함한 OpenDocument.core 포크 `v7.5.2-omni.1`의 고정 커밋입니다. 기존 XLS 원본 셀 정답 검사도 포함해 **32개 테스트가 iPhone 17 Simulator와 실기기에서 모두 통과**했습니다. SwiftLint strict도 53파일·위반 0건입니다.

실기기는 저장소 밖 호스트 앱에 같은 테스트를 연결했습니다. 자체 생성 한영 대용량 스캔·혼합 배치의 시간/메모리와 남은 QoS 경고는 [최종 로컬 검증](Documentation/LOCAL_REVIEW_2026-10-27.md)에 기록했습니다. 이 수치는 Debug·샘플링 측정이며 일반 문서 전체의 성능 보증은 아닙니다. 원래 XLS 결함과 전환 이력은 [XLS 수정·전환 결과](Documentation/XLS_CHART_FIX.md), RTF 구현 검증은 [RTF 후속 검증](Documentation/RTF_COMPLETION_VERIFICATION.md)을 확인하세요.

행 정렬 보완과 어려운 스캔 회귀를 추가한 후속 코드는 Simulator 35개가 통과했으며, 잠금으로 실기기 재검증·동일 발열 3회 반복은 대기 중입니다. 위 32개 실기기 결과와 구분합니다. 같은 Simulator의 65문서 전후 비교도 기록했습니다. 원인 조사·비동기 변경안·로컬 재현 키트는 [OCR 후속 기록](Documentation/OCR_QOS_FOLLOWUP_2026-10-27.md)을 확인하세요.

## 의존성과 라이선스

**OmniParser 자체 Swift 코드와 자체 문서는 MIT입니다. 외부 의존성·바이너리·고지 파일은 각각의 원래 라이선스를 따릅니다.** 모든 구성요소를 MIT로 재라이선스한 패키지가 아닙니다.

| 의존성 | 고정 버전 | 라이선스 |
| --- | --- | --- |
| SwiftSoup | 2.14.3 | MIT |
| OLEKit | 0.3.1 | Apache-2.0 |
| OpenDocument.core 포크 | v7.5.2-omni.1 / b302cc85 | MPL-2.0, 네이티브 전이 의존성의 별도 조건 |
| hwp-swift / CoreHwp | 0.19.0 | LGPL-2.1 |
| OfficeOxide | 0.1.15, 고정 커밋 | MIT 선택, 전이 의존성의 별도 조건 |

현재 단일 제품은 CoreHwp·OdrCore·OfficeOxide를 필수 의존성으로 연결합니다. PDF만 사용하는 런타임 옵션으로 HWP·Office 의존성을 제외할 수는 없습니다.

소스 패키지를 사용하는 앱의 바이너리를 배포할 때에는 MPL·LGPL 등 해당 조건을 별도로 이행해야 합니다. 특히 LGPL의 재링크·소스 제공 조건은 앱의 배포 방식까지 고려해야 합니다. 직접 의존성의 라이선스 대조는 완료했지만 네이티브 바이너리 전체의 재현 빌드·전이 고지 대조는 미완료입니다. 상세 범위와 확인하지 못한 부분은 [라이선스 검토](Documentation/LICENSE_REVIEW.md), 고지·소스 취득 경로는 [서드파티 고지](THIRD_PARTY_NOTICES.md)를 확인하세요.

OfficeOxide의 iOS·Simulator 정적 XCFramework는 `ThirdParty/OfficeOxide`에 포함됩니다. 약 84MiB로 초기 저장소 크기가 크며, Git LFS나 GitHub Release를 통한 배포로 전환하지 않은 초기 구성입니다. 변경한 소스의 재현 경로·호환 패치·아카이브 해시와 원래 고지를 함께 보존했습니다.

## 공개 초안 검토

오픈소스 도입 관점의 확인된 문제와 개선 순서는 [검토 보고서](Documentation/OPEN_SOURCE_REVIEW.md)에 정리했습니다.
