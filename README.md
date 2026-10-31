# OmniParser

> **Draft — 개발·검토 중인 저장소입니다.** API·의존성·패키지 구성이 바뀔 수 있습니다. 현재 프리릴리즈 단계이며, 실서비스 도입 전 기능 검증과 배포 라이선스 검토가 필요합니다.

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

사용할 타깃의 의존성에 `.product(name: "OmniParser", package: "swift-omni-parser")`를 추가합니다. 공개 `0.1.0-alpha.1` 태그는 내부 revision 의존성 때문에 버전 설치가 실패합니다. 수정 버전이 발행되기 전에는 `main`을 사용하고 소비 프로젝트의 `Package.resolved`로 커밋을 고정합니다. 이 브랜치도 개발·검토 중이며, 기존 태그를 강제로 변경하지 않습니다.

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

한영 혼합 문서에는 `options: .init(performOCR: true, ocrLanguage: .koreanAndEnglish)`, 영어 전용 자료에는 `.english`를 지정할 수 있습니다. 기본 `.automatic`은 기존 동작을 유지합니다. 모드별 정확도·메모리 절충과 배치 적용 방식은 [요청별 OCR 언어](Documentation/API.md#요청별-ocr-언어)를 확인하세요.

기존 초기화와 새 옵션의 소스 호환성은 고정 로컬 미러를 사용한 arm64·x86_64 Simulator 외부 모듈 컴파일로 확인했습니다. 공개 태그 설치·앱 링크·외부 호출의 런타임 검증은 별도이며, [검증 범위](Documentation/IMPROVEMENT_LOOP_2026-10-28.md#외부-소비자-검증의-환경-제약)에 구분했습니다.

## 형식과 처리 경로

| 형식 | 구현 경로 |
| --- | --- |
| TXT·CSV·JSON·XML | Foundation 및 형식별 구조 추출 |
| HTML | SwiftSoup DOM의 본문·제목·목록·표와 내장/로컬 참조 그림. CSS 조판·스크립트 실행 제외 |
| Markdown | 줄 단위 제목·본문·파이프 표와 인라인 그림 참조. CommonMark 전체 방언·참조형 그림은 미지원 |
| RTF | 문단·표·병합·중첩 표 경로·헤더/푸터·내장 OLE 문서. 래스터·무압축 DIB·WMF/EMF 그림과 선택적 OCR. 미지원 그리기 명령은 부분 이미지·위치 경고 |
| JPEG·PNG·HEIC·TIFF·CGImage | ImageIO·Vision, 다중 프레임과 방향 처리 |
| PDF | 페이지 좌표·선/정렬 기반 표 추정·표시된 그림 영역의 래스터 추출·선택적 OCR. 원본 이미지 스트림 반환은 아님 |
| DOC·PPT | OfficeOxide, OfficeArt 그림 보완 |
| DOCX·XLS·XLSX·PPTX | OpenDocument.core |
| HWP·HWPX | CoreHwp 본문·표·문단/셀 그림 앵커. 지원 래스터 BinData 추출·OCR, 페이지 조판 순서는 경고 |

인코딩 판별은 BOM·UTF-16 패턴과 레거시 문자셋 휴리스틱을 사용합니다. JSON 객체 키는 정렬하며 XML은 엔티티 확장을 허용하지 않습니다. Office는 백엔드가 제공하는 문서 요소를 추출하며, 제공하지 않는 헤더·각주·도형 앵커·좌표까지 완전하게 복원하지 않습니다.

표는 기존 구현의 처리 경로를 나타내며 모든 문서의 완전한 복원을 보장하지 않습니다. 위치를 복원하지 못하거나 일부 요소가 실패하면 경고를 반환합니다. 이미지 속 표의 셀 구조 복원, 암호 해제, 파일 형식 변환은 제공하지 않습니다. 구체적인 옵션·위치·읽기 순서 제약은 [API 문서](Documentation/API.md)를 확인하세요.

통합한 코드는 iPhone 17 Simulator의 **Debug 회귀 171개 통과**로 확인했습니다. 아래 실기기 163개 결과는 병합 전 코드의 검증이며 이번 통합 상태의 실기기 검증과 구분합니다. 작은 숫자 그림의 오인식·페이지 OCR 중복·작은 배치의 추가 peak 메모리 절감은 남아 있습니다. 자세한 범위와 이전 결과는 아래 검증 이력에 구분했습니다.

## 빌드

CI의 Simulator 회귀·일반 빌드는 Debug 설정을 사용합니다. 로컬에서도 설정을 명시합니다.

```bash
xcodebuild build -configuration Debug -scheme OmniParser \
  -destination 'generic/platform=iOS Simulator' -skipMacroValidation

xcodebuild build -configuration Debug -scheme OmniParser \
  -destination 'generic/platform=iOS' -skipMacroValidation CODE_SIGNING_ALLOWED=NO

swiftlint lint --strict
```

XCTest 타깃 `OmniParserTests`와 출처·고지가 포함된 회귀 샘플을 추가했습니다.

```bash
xcodebuild test -configuration Debug -scheme OmniParser \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -skipMacroValidation -parallel-testing-enabled NO -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=NO
```

최적화된 Release 설정을 검증하려면 다음 명령을 사용합니다.

```bash
xcodebuild test -configuration Release -scheme OmniParser \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -skipMacroValidation -parallel-testing-enabled NO -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES
```

검사를 선택하는 방법과 샘플 제출 기준은 [기여 안내](CONTRIBUTING.md)를 확인하세요. CI 설정은 `.github/workflows/verification.yml`에 있으며, 실제 통과 여부는 해당 커밋의 GitHub Actions 실행 결과로 확인합니다.

<details>
<summary>검증 이력과 실험 자료</summary>

병합 전 `089ead2` 작업 브랜치에서는 Debug 회귀 107개를 확인했습니다. 이번 통합 상태의 171개에는 원격 main의 RTF·OLE·DIB·벡터·PNG 회귀와 해당 작업 브랜치의 회귀를 함께 포함합니다.

기본 의존성은 XLS 중첩 차트 수정을 포함한 OpenDocument.core 포크 `7.5.2-omni.1`의 exact 버전이며 기존 b302cc 커밋을 유지합니다. 앞선 `33991ef` 기준의 **Release 회귀 99개가 iPhone 17 Simulator에서 실패·skip 없이 통과**했고, xcresult 런타임 경고 0건·SwiftLint strict 67파일·위반 0건·generic Simulator 빌드 통과를 확인했습니다. 요청별 언어·동시 호출·PDF·TIFF·HWPX 회귀에 OCR 좌표 경계와 정방향으로 표시되는 PDF의 0/90/180/270도 페이지 좌표 검사를 포함합니다.

기본 의존성은 XLS 중첩 차트 수정을 포함한 OpenDocument.core 포크 `7.5.2-omni.1`의 exact 버전이며 기존 b302cc 커밋을 유지합니다. 병합 전 main의 **Release 회귀 159개가 iPhone 17 Simulator에서 실패·skip 없이 통과**했고, xcresult 런타임 경고 0건·SwiftLint strict 84파일·위반 0건을 확인했습니다. RTF 헤더·푸터·중첩 표·내장 OLE·DIB·WMF/EMF와 옵션·자원 제한·WebKit 실행 중 취소 회귀를 포함합니다. [통합 검증](Documentation/INTEGRATION_VERIFICATION_2026-10-30.md)에 최신 실행과 과거 결과를 구분했습니다. 요청별 언어·동시 호출·PDF·TIFF·HWPX 회귀에 OCR 좌표 경계와 정방향으로 표시되는 PDF의 0/90/180/270도 페이지 좌표 검사를 포함합니다.

앞선 65문서 비교에서 본문·2,709개 블록의 문구·순서·신뢰도·이미지 픽셀은 유지됐고, 범위 밖 OCR 좌표 1개를 보정했습니다. PNG 원시 바이트는 64/65 일치하며 나머지는 색상 프로필 날짜·시각 필드 두 바이트만 달랐습니다. 엄격 비교의 차이 상태를 보존했습니다. 작은 숫자 그림의 오인식·페이지 OCR 중복과 추가 peak 메모리 절감은 남아 있습니다. 범위·실행 명령·단계별 시간은 [최신 수정·검증 기록](Documentation/IMPROVEMENT_LOOP_2026-10-28.md#ocr-좌표-경계-보정과-99개-회귀)에 구분했습니다.

병합 전 `df6b502` 기준 iPhone 17 / iOS 27.2 실기기에서 **163/163 PASS**, xcresult 런타임 경고 0건을 확인했습니다. 벡터 오류 종료의 JSContext 참조를 정리하고 HEIC PNG 인코딩을 동시성 2의 default-QoS 큐로 옮겼습니다. [메모리·QoS 수정 검증](Documentation/DEVICE_OPTIMIZATION_2026-10-30.md)에 5쌍 비교를 기록했습니다. 앱 자체 peak 중앙값은 **60.85→57.86 MiB(-4.9%)**, 반복·배치 시간 중앙값은 약 0.4~1.6% 증가했습니다. 관측 최고 peak는 줄지 않았으며 모든 실행의 메모리 개선이나 속도 무저하를 보장하지 않습니다. WebKit 별도 프로세스의 peak 메모리는 무선 Instruments 연결 중단으로 미관측입니다.

[앞선 실기기 검증](Documentation/DEVICE_VERIFICATION_2026-10-30.md)은 당시 159개 회귀와 공유 WebKit 저장소 전후 결과로 보존했습니다.

실기기 32개 통과와 과거 대용량 기록은 이전 동기 OCR 코드의 결과입니다. [Release 배치·URL/Data·QoS 검증](Documentation/RELEASE_MEMORY_2026-10-28.md)에 앞선 메모리·QoS 비교를 기록했습니다. 대용량 URL 입력의 footprint 절감은 확인했지만 작은 배치의 추가 메모리 절감은 확보하지 못했습니다. [입력 Reader의 앞선 Debug 검증](Documentation/BATCH_MEMORY_2026-10-28.md), [오픈소스 후속 검증과 65문서 대조](Documentation/OPEN_SOURCE_FIXES_2026-10-27.md), 과거 [대용량 기록](Documentation/LOCAL_REVIEW_2026-10-27.md)·[RTF 검증](Documentation/RTF_COMPLETION_VERIFICATION.md)·[XLS 전환](Documentation/XLS_CHART_FIX.md)은 당시 결과로 보존합니다.

[Vision 단독 메모리 재현 예제](Documentation/VISION_MEMORY_REPRODUCTION.md)는 자체 생성 이미지로 OCR 동시성 1·2를 비교합니다. 별도 XCTest 타깃에 복사해 실행하며 제품이나 기본 CI 테스트에는 포함하지 않습니다.

[OCR 정확도·PDF 중복 개선 기록](Documentation/IMPROVEMENT_LOOP_2026-10-28.md)에 요청별 언어 옵션, 같은 위치의 중복 그림 OCR 수정, 실제 시간·메모리 비교를 정리했습니다. 기본 언어 정책은 유지하며, 동일 영역 OCR을 생략한 시간 개선과 추가 peak 메모리 절감 여부를 구분합니다.

PR·main 푸시의 자동 검사에는 `.github/workflows/verification.yml`을 사용합니다. 실제 실행 결과는 GitHub Actions의 해당 커밋과 각 검증 기록을 기준으로 확인합니다. [기여 안내](CONTRIBUTING.md)와 [보안 제보](SECURITY.md)에 검증·샘플 제출 기준을 적었습니다.

WMF·EMF는 RTF 안 그림만 처리합니다. [벡터 검증 기록](Documentation/VECTOR_VERIFICATION_2026-10-30.md)에 실제 지원·미지원 명령 경고, 한영 OCR, 취소·세션 수명, Simulator 메모리 전후 비교를 구분했습니다. 새 런타임 자산은 JS 322,772바이트와 MIT 원문 1,080바이트이며 네이티브 바이너리를 추가하지 않았습니다. 이 크기를 앱 다운로드·설치 용량 증가량으로 환산하지 않습니다.

</details>

## 의존성과 라이선스

**OmniParser 자체 Swift 코드와 자체 문서는 MIT입니다. 외부 의존성·바이너리·고지 파일은 각각의 원래 라이선스를 따릅니다.** 모든 구성요소를 MIT로 재라이선스한 패키지가 아닙니다.

| 의존성 | 고정 버전 | 라이선스 |
| --- | --- | --- |
| SwiftSoup | 2.14.3 | MIT |
| OLEKit | 0.3.1 | Apache-2.0 |
| wmf-emf-renderer 소스 자산 | 0.2.1, 제한 패치 | MIT |
| OpenDocument.core 포크 | v7.5.2-omni.1 / b302cc85 | MPL-2.0, 네이티브 전이 의존성의 별도 조건 |
| hwp-swift / CoreHwp | 0.19.0 | LGPL-2.1 |
| OfficeOxide | 0.1.15, 고정 커밋 | MIT 선택, 전이 의존성의 별도 조건 |

현재 단일 제품은 CoreHwp·OdrCore·OfficeOxide를 필수 의존성으로 연결합니다. PDF만 사용하는 런타임 옵션으로 HWP·Office 의존성을 제외할 수는 없습니다.

소스 패키지를 사용하는 앱의 바이너리를 배포할 때에는 MPL·LGPL 등 해당 조건을 별도로 이행해야 합니다. 특히 LGPL의 재링크·소스 제공 조건은 앱의 배포 방식까지 고려해야 합니다. 직접 의존성의 라이선스 대조는 완료했지만 네이티브 바이너리 전체의 재현 빌드·전이 고지 대조는 미완료입니다. 상세 범위와 확인하지 못한 부분은 [라이선스 검토](Documentation/LICENSE_REVIEW.md), 고지·소스 취득 경로는 [서드파티 고지](THIRD_PARTY_NOTICES.md)를 확인하세요.

OfficeOxide의 iOS·Simulator 정적 XCFramework는 `ThirdParty/OfficeOxide`에 포함됩니다. 약 84MiB로 초기 저장소 크기가 크며, Git LFS나 GitHub Release를 통한 배포로 전환하지 않은 초기 구성입니다. 변경한 소스의 재현 경로·호환 패치·아카이브 해시와 원래 고지를 함께 보존했습니다.

## 공개 초안 검토

최신 상태는 [후속 수정·검증](Documentation/OPEN_SOURCE_FIXES_2026-10-27.md), 최초 검토 이력은 [공개 초안 검토](Documentation/OPEN_SOURCE_REVIEW.md)에 정리했습니다.
