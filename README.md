# OmniParser

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
  branch: "main"
)
```

사용할 타깃의 의존성에 `.product(name: "OmniParser", package: "swift-omni-parser")`를 추가합니다. 초기 공개본에는 버전 태그가 없으므로 소비 프로젝트의 `Package.resolved`로 리비전을 고정합니다.

## 사용법

```swift
import OmniParser

// 기본값: 네이티브 본문·표만 추출합니다.
let result = try await DocumentParser.parse(.url(fileURL))
print(result.fullText)

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
| HTML·Markdown·RTF | SwiftSoup·형식별 해석·Apple 프레임워크 |
| JPEG·PNG·HEIC·TIFF·CGImage | ImageIO·Vision, 다중 프레임과 방향 처리 |
| PDF | PDFKit·페이지 좌표·표 추정·삽입 이미지·선택적 OCR |
| DOC·PPT | OfficeOxide, OfficeArt 그림 보완 |
| DOCX·XLS·XLSX·PPTX | OpenDocument.core |
| HWP·HWPX | hwp-swift의 CoreHwp |

표는 기존 구현의 처리 경로를 나타내며 모든 문서의 완전한 복원을 보장하지 않습니다. 위치를 복원하지 못하거나 일부 요소가 실패하면 경고를 반환합니다. 이미지 속 표의 셀 구조 복원, 암호 해제, 파일 형식 변환은 제공하지 않습니다. 구체적인 옵션·위치·읽기 순서 제약은 [API 문서](Documentation/API.md)를 확인하세요.

## 빌드

```bash
xcodebuild build -scheme OmniParser \
  -destination 'generic/platform=iOS Simulator' -skipMacroValidation

xcodebuild build -scheme OmniParser \
  -destination 'generic/platform=iOS' -skipMacroValidation CODE_SIGNING_ALLOWED=NO

swiftlint lint --strict
```

이 분리본에는 테스트 타깃·샘플을 포함하지 않았습니다. 분리 직전 소스에서 제외된 상태를 유지했으며, 이번 공개 준비에서는 테스트를 추가하거나 실행하지 않았습니다. 빌드 통과는 형식별 추출 결과나 실기기 동작 검증을 대신하지 않습니다.

## 의존성과 라이선스

**OmniParser 자체 Swift 코드와 자체 문서는 MIT입니다. 외부 의존성·바이너리·고지 파일은 각각의 원래 라이선스를 따릅니다.** 모든 구성요소를 MIT로 재라이선스한 패키지가 아닙니다.

| 의존성 | 고정 버전 | 라이선스 |
| --- | --- | --- |
| SwiftSoup | 2.14.3 | MIT |
| OLEKit | 0.3.1 | Apache-2.0 |
| OpenDocument.core | 7.5.2 | MPL-2.0, 네이티브 전이 의존성의 별도 조건 |
| hwp-swift / CoreHwp | 0.19.0 | LGPL-2.1 |
| OfficeOxide | 0.1.15, 고정 커밋 | MIT 선택, 전이 의존성의 별도 조건 |

소스 패키지를 사용하는 앱의 바이너리를 배포할 때에는 MPL·LGPL 등 해당 조건을 별도로 이행해야 합니다. 특히 LGPL의 재링크·소스 제공 조건은 앱의 배포 방식까지 고려해야 합니다. 상세 범위와 확인하지 못한 부분은 [라이선스 검토](Documentation/LICENSE_REVIEW.md), 고지·소스 취득 경로는 [서드파티 고지](THIRD_PARTY_NOTICES.md)를 확인하세요.

OfficeOxide의 iOS·Simulator 정적 XCFramework는 `ThirdParty/OfficeOxide`에 포함됩니다. 약 84MiB로 초기 저장소 크기가 크며, Git LFS나 GitHub Release를 통한 배포로 전환하지 않은 초기 구성입니다. 변경한 소스의 재현 경로·호환 패치·아카이브 해시와 원래 고지를 함께 보존했습니다.
