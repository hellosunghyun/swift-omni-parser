# 문서 파싱 API

`DocumentParser`는 화면과 독립적으로 로컬 문서를 파싱한다. 이미지 추출과 OCR은 요청별로 선택하며 **둘 다 기본값은 false**다.

```swift
// 기본: PDF·Office·HWP 등의 네이티브 본문과 표만 읽는다.
let textResult = try await DocumentParser.parse(.url(fileURL))

// 그림 PNG와 OCR 텍스트까지 필요할 때 명시한다.
let result = try await DocumentParser.parse(
  .url(fileURL),
  options: .init(extractImages: true, performOCR: true)
)

// 두 설정은 독립적이다. PNG를 보관하지 않고 OCR만 수행할 수도 있다.
let ocrResult = try await DocumentParser.parse(
  .data(data, fileName: "document.pdf"),
  options: .init(performOCR: true)
)

let outcomes = try await DocumentParser.parseBatch(
  inputs,
  options: .init(extractImages: true, maximumConcurrentDocuments: 2)
)
```

| extractImages | performOCR | 처리 범위 |
| --- | --- | --- |
| false | false | 네이티브 본문·표. 그림 PNG 추출·PDF 래스터화·OCR 생략 |
| true | false | 네이티브 본문·표 + 제공 가능한 그림 PNG와 배치 블록 |
| false | true | 네이티브 본문·표 + 이미지·스캔 OCR. PNG 반환 생략 |
| true | true | 본문·표·PNG·OCR 모두 처리 |

- `images`는 추출한 PNG, `image` 블록은 그림 배치, `imageOCR` 블록은 인식 텍스트다. `fullText`에는 본문·제목·셀·OCR 텍스트만 들어간다.
- JPEG·PNG·HEIC·TIFF·CGImage 직접 입력도 같은 설정을 사용한다. 둘 다 false면 이미지의 텍스트·PNG 결과는 비어 있다. TIFF는 프레임별 위치·방향과 페이지 제한을 유지한다.
- 스캔 PDF는 네이티브 텍스트가 없으므로 본문을 읽으려면 `performOCR: true`가 필요하다. `extractImages`만 켜면 그림은 반환하지만 이미지 속 문자는 읽지 않는다.
- PDF·Office·HWP의 기존 그림 처리 경로와 HTML·Markdown의 내장·로컬 참조 그림에 적용한다. 이 옵션이 형식별 미지원 요소를 새로 지원하게 만드는 것은 아니다.
- HTML·Markdown 참조 그림은 본문 뒤에 추가하므로 순서 경고가 남을 수 있다. 외부 이미지 다운로드와 문서 업로드는 하지 않는다.
- 단일 입력과 혼합 배치 모두 `options`로 설정한다. 배치에서는 같은 설정이 모든 입력에 적용된다.
- 암호화·손상·압축·입력 크기 검사와 취소는 설정과 관계없이 적용한다. 그림·OCR을 켜면 해당 작업의 픽셀·개수·보관 바이트 제한도 적용한다.
- 기존 호출에서 이미지·OCR 결과가 필요했다면 두 옵션을 명시해야 한다. 결과를 필터링해서 숨기는 것이 아니라 해당 추출 작업을 생략한다.

## 요청별 OCR 언어

`ocrLanguage`는 OCR을 켰을 때 사용하는 요청별 옵션이다. 기본값 `.automatic`은 기존의 한국어·영어 힌트와 자동 언어 감지를 유지한다. 이 옵션만 지정해도 OCR이 켜지는 것은 아니다.

```swift
let mixed = try await DocumentParser.parse(
  .url(fileURL), options: .init(performOCR: true, ocrLanguage: .koreanAndEnglish)
)
let english = try await DocumentParser.parse(
  .url(englishURL), options: .init(performOCR: true, ocrLanguage: .english)
)
```

| 모드 | Vision 언어 힌트 | 자동 감지 |
| --- | --- | --- |
| `.automatic` | 한국어 → 영어, 기존 기본값 | 켬 |
| `.koreanAndEnglish` | 한국어 → 영어 | 끔 |
| `.english` | 영어 | 끔 |

한글이 포함된 혼합 행은 `.koreanAndEnglish`, 영어 전용 자료는 `.english`로 명시할 수 있다. 지원 가능한 모든 자료에서 한 모드가 더 정확하다는 뜻은 아니다. 같은 한영 혼합 샘플에서 자동 감지를 끄면 한글 누락이 줄었지만 작은 영어 표에서는 회귀와 메모리 증가도 확인해 기본값을 바꾸지 않았다. 정답·시간·메모리의 적용 범위는 [개선 루프 기록](IMPROVEMENT_LOOP_2026-10-28.md)을 확인한다.

본문 OCR과 작은 숫자 보완은 같은 모드를 사용한다. 언어는 각 파싱 호출의 요청 풀에 고정하고 다른 동시 호출과 섞지 않는다. `parseBatch`에서는 전달한 모드를 모든 입력에 적용한다. 서로 다른 모드가 필요한 입력은 각각 `parse`를 호출하고 호출 측에서 동시 수를 제한한다. 문서의 네이티브 본문·표 추출과 PNG 반환 설정에는 영향을 주지 않는다.

## OCR 신뢰도와 보완 이력

`ocrConfidence`는 Vision이 제공한 점수이며 정답 보증이 아니다. 자체 생성한 `S123.45`를 한영 primary OCR이 `$123.45`로 읽으면서 신뢰도 1.0을 반환한 [실제 사례](IMPROVEMENT_LOOP_2026-10-28.md#공개-숫자-분기와-primary-오독)가 있다. 수치·식별자를 사용할 때는 원본과 대조한다.

`ocrOriginalText`는 라이브러리가 통화 기호를 보완한 경우의 primary 문자열만 기록한다. `nil`은 해당 보완이 없었다는 뜻이며 primary가 정확했다는 뜻은 아니다. 언어 모드가 지원하는 문자와 특정 문서의 인식 정확도도 구분해야 한다.

Vision OCR 좌표는 좌상단 원점의 정규화 영역으로 변환한다. 경계를 조금 벗어난 사각형은 `0...1` 영역과 교차시키고, 기존 유효 좌표는 그대로 보존한다. 비유한 값·빈 사각형·완전히 영역 밖인 위치는 변환 단계에서 `bounds: nil`로 남기며 인식 문구와 신뢰도는 유지한다. PDF 그림의 OCR은 이후 해당 그림의 페이지 위치로 옮긴다. 좌표 보정이 글자 오인식을 고치거나 모든 형식의 페이지 조판 위치를 복원하는 것은 아니다.

## Office 추출 경로

- XLS·XLSX는 OpenDocument.core의 셀 좌표 API로 읽는다. HTML 화면용 행·열 눈금과 인쇄용 중복 출력을 본문에 섞지 않는다.
- 셀 주소와 제공 가능한 병합 범위를 보존한다. 희소 셀 조회는 문서 전체 100,000좌표까지 수행하며, 초과하면 이미 읽은 결과와 중단 위치의 `resourceLimitReached` 경고를 반환한다.
- DOC·PPT 본문과 표는 OfficeOxide 0.1.15로 읽는다. 단일 행·열 및 병합 PPT 표의 기존 판정 기준은 고정된 호환 패치로 유지한다.
- DOCX·PPTX는 OpenDocument.core를 사용한다. 구형 OfficeArt 내장 그림 복구도 수행한다. 서로 다른 원본 그림 위치의 같은 문구는 각각 OCR 블록으로 남기며, 같은 위치·텍스트가 겹친 추출만 중복으로 제거한다. 이미지·OCR이 모두 꺼져 있으면 그림 복구용 CFB 스트림을 다시 읽지 않는다.
- 라이브러리 소스·라이선스·재빌드와 바이너리 해시는 저장소의 `ThirdParty/OfficeOxide/`에 있다. 앱·CI 빌드에서 Rust를 설치하거나 문서를 외부로 전송하지 않는다.

## HWP 그림의 반복 배치

HWP·HWPX에서 같은 BinData를 여러 문단·셀의 그림으로 참조하면 각 논리 앵커에 OCR 블록을 반환한다. 첫 인식이 성공한 경우 텍스트·신뢰도·숫자 보완 원문·그림 내부 좌표를 재사용하고, 문단·셀·control 경로와 읽기 순서만 해당 배치에 맞춘다. 같은 그림을 배치마다 다시 디코딩하거나 인식하지 않는다.

`extractImages: true`이면 PNG는 최초 추출 앵커에 하나만 보관하고 `.image` 블록은 각 배치에 남긴다. 반복 배치는 이미지 시도 횟수나 PNG 보관 바이트를 추가로 쓰지 않는다. OCR의 `bounds`는 그림 내부의 정규화 좌표이며 HWP 페이지 조판 좌표가 아니다. 부동 개체의 페이지 순서는 계속 `uncertainReadingOrder` 경고로 알린다.

첫 그림의 실패·빈 OCR은 성공 결과로 재사용하지 않으며, 같은 BinData 재참조만으로 자동 재시도하지도 않는다. 이미 추출한 본문·표·PNG·다른 그림은 유지한다. 캐시는 문서 파싱이 끝날 때 함께 해제된다.

## 텍스트·PDF의 복원 범위

- TXT·CSV 등의 인코딩은 BOM·UTF-16 패턴과 레거시 문자셋 휴리스틱을 사용한다. CSV는 빈 인용 필드·후행 빈 셀을 보존한다. JSON 객체 키는 정렬하므로 원본 키 순서와 다를 수 있다. 불리언은 `true/false`로 보존해 숫자 `1/0`과 구분한다.
- HTML은 DOM의 본문·제목·목록·표를 읽지만 CSS 시각 조판과 병합 셀의 모든 span을 복원하지 않는다. Markdown은 제목·줄 단위 본문·파이프 표·인라인 그림 참조 범위이며 CommonMark 전체 렌더러가 아니다.
- 독립 SVG 문서는 지원하지 않는다. HTML 안의 SVG 아이콘은 본문 추출을 막지 않으며 `html/svg[n]` 위치의 `unsupportedElement` 경고를 반환한다. Markdown의 SVG 코드 예제는 텍스트로 유지한다.
- HTML·Markdown 그림은 본문 뒤에 붙고 순서 경고에 문서 형식 part를 남긴다. 원격 그림은 요청하거나 내려받지 않으며 skip 경고에 참조를 남긴다.
- PDF 표는 선·텍스트 정렬 기반 추정이다. 그림은 표시된 페이지 영역을 잘라 래스터로 반환하며 원본 압축 이미지 스트림 추출이 아니다. 이미지 속 표는 OCR 문자만 반환하고 셀 구조를 만들지 않는다.
- PDF 그림의 첫 OCR이 비면 같은 언어로 사방 16픽셀의 흰 여백을 추가한 입력을 한 번 더 인식한다. 추가 입력이 실제 페이지 래스터 면적과 100만 픽셀을 모두 넘지 않을 때만 실행한다. 좌표는 여백을 제거해 원래 그림 안으로 제한하며 반환 PNG는 바꾸지 않는다. 해당 그림에는 추가 인식 비용이 들며 모든 빈 OCR의 복구를 보장하지 않는다.
- PDF 작업 예산은 진행 중인 페이지의 추정 래스터/인식 작업을 제한한다. 반환 PNG와 프레임워크 캐시는 별도여서 프로세스 전체 메모리 상한으로 쓰면 안 된다. PNG가 필요 없으면 기본값인 `extractImages: false`를 유지하고 OCR만 켤 수 있다.

## RTF 구조와 부분 복구

- 시스템 RTF importer의 문단·표 속성을 사용한다. `tableCell`은 1부터 시작하는 행·열과 제공 가능한 병합 범위를 담으며, 같은 셀의 여러 문단은 하나의 셀 텍스트로 합친다.
- 내장 PNG·JPEG 등의 그림은 원본 바이트 위치를 `part`에 남기고, 옵션에 따라 PNG·OCR을 반환한다. Word의 인접한 기본 그림과 호환용 그림은 중복 추출하지 않는다.
- 셀 안의 OCR은 셀 좌표를 유지하지만 셀 텍스트를 합치는 과정에서 정확한 교차 순서를 보장할 수 없어 `uncertainReadingOrder`를 반환한다. 페이지 좌표를 복원하는 기능은 아니다.
- 손상된 그림·미지원 WMF/EMF/DIB 등은 위치가 포함된 경고로 남기며 다른 본문·표·그림을 보존한다. 모든 RTF 그림 인코딩을 지원하는 것은 아니다.
- 그림 개수·픽셀·보관 PNG 크기 제한과 취소를 적용한다. 손상된 `bin` 길이는 importer에 넘기기 전에 거부한다.

JSON·XML·RTF의 구조 해석이 실패해 원문 텍스트로 복구하면 `malformedContent` 경고를 반환한다. XML 외부 엔티티를 해석하지 않으며 내부 엔티티 선언도 확장을 시작하기 전에 중단하고 경고와 원문 텍스트를 반환한다. Office 그림의 OCR이 실패하더라도 이미 추출한 PNG는 보존한다.

OCR과 PDF는 페이지를 우선한 뒤, 세로 영역이 충분히 겹치는 텍스트를 같은 행으로 묶어 왼쪽부터 정렬한다. 글자 높이 차이로 표 그림의 열 순서가 뒤섞이는 문제를 보완하는 휴리스틱이며, 다단 조판 전체나 스캔 표의 셀 구조 복원은 아니다. 위치·인식 신뢰도·숫자 보정 결과는 정렬에서 바꾸지 않는다.

## 비동기 OCR과 자원 수명

URL 입력은 로컬 파일만 허용하며, 보안 접근과 원본 기준 디렉터리는 전체 파싱 동안 유지한다. 동기 파일 조정·읽기는 기본 QoS의 전용 I/O 실행기에서 구조화된 자식 작업으로 수행하며 호출자는 비동기로 기다린다. Swift 작업의 취소 컨텍스트와 읽기 완료까지의 보안 접근 수명을 유지한다. 복제 가능한 일반 파일은 열린 FD에서 비공개 COW 스냅샷을 만들고 `mappedIfSafe`로 읽어 큰 입력의 힙 복사를 줄인다. 스냅샷 경로는 읽기 뒤 제거하지만, 반환한 Data가 매핑을 사용하는 동안 backing 파일의 수명은 유지된다. 원본 변경·교체가 이 스냅샷의 내용을 바꾸지 않는다.

복제를 지원하지 않는 파일시스템, 심볼릭 링크, 파일 플래그 또는 허용하지 않는 보호 등급은 크기 제한이 있는 복사 경로로 처리한다. 원본 보호 속성을 변경하지 않으며, 보호 정책은 잠금 후 접근이 만료되는 등급과 알 수 없는 명시 값을 매핑에서 제외한다. Foundation이 실제 매핑을 선택한다고 보장하지는 않는다. `.data`·CGImage 입력은 기존 경로를 유지한다.

SwiftPM 제품 리소스의 `PrivacyInfo.xcprivacy`는 자체 추적·수집 없음과 파일 메타데이터 조회 사유를 선언한다. `0A2A.1`은 앱이 파싱을 요청할 때만 동작하는 SDK 내부 파일 읽기 wrapper, `C617.1`은 앱 컨테이너의 입력·비공개 복제본 조회에 사용한다. 파일 크기·종류·flags는 입력 검증·읽기에만 사용하며 SDK 자체 분석·외부 전송에 쓰지 않는다. 이 판단은 [Apple의 required-reason API 사유](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)에 따른 구현 해석이며 개별 심사 승인 결과는 아니다. SDK 전용 사유를 앱의 선언에 그대로 복사하지 않는다. 외부 의존성과 소비자 앱의 선언·동작은 별도로 확인한다.

Vision revision 3의 비동기 요청을 사용한다. 기존 한영·정확도·언어 보정과 최소 글자 높이 0을 명시하며, 숫자 보정도 같은 비동기 경로를 사용한다. 호출 중인 요청은 다른 OCR 작업과 공유하지 않고, 실패·취소한 요청은 풀에 보관하지 않는다. 완료한 유휴 요청은 각 parse/parseBatch 호출의 범위 안에서 최대 두 개만 보관한다. 실행 동시성은 문서·PDF 작업창이 제한하며 유휴 요청 수와 구분한다.

요청 재사용은 Vision 내부 모델·CPU 작업 버퍼의 공유나 프로세스 메모리 상한을 보장하지 않는다. 이미 파일이 있으면 URL 입력으로 큰 입력의 힙 복사를 줄일 수 있지만, 작은 파일은 파일 조정·복제 준비 비용으로 Data보다 느릴 수 있다. 이미 보유한 Data를 이 목적으로 임시 파일에 다시 쓸 필요는 없다. 호출 측에서 보유하는 입력·반환 결과와 Vision 작업 메모리도 전체 사용량에 포함된다.

작업 전후와 구조 순회·ZIP 해제 중에 취소를 확인한다. 취소와 native 오류가 겹치면 취소를 우선한다. 외부 프레임워크 내부 작업을 일정 시간 안에 강제 중단하거나 프로세스 메모리의 절대 상한을 보장하지는 않는다.

OOXML·HWPX는 native 백엔드 진입 전에 ZIP의 모든 항목을 64KiB 버퍼로 읽어 실제 해제량·CRC·local/central 헤더·descriptor를 확인한다. stored/DEFLATE를 지원하며 컨테이너의 압축·CRC 손상은 문서 오류로 거부한다. 정상 컨테이너 안에서 특정 그림의 디코딩이 실패하는 경우에는 다른 본문·표를 보존하는 부분 복구를 유지한다.

배치의 동시 문서 수와 진행 중 PDF 작업 예산은 결과 전체의 메모리 상한이 아니다. 반환 PNG가 많은 배치는 입력을 작은 묶음으로 나눠 소비하고, PNG가 필요 없으면 `extractImages: false`를 유지한다. 결과의 `fullText`·`blocks`를 호출자가 변경한 경우에는 두 값의 일관성도 호출자가 유지해야 한다.

기본 동시 문서 수는 2다. 메모리를 우선할 때만 1로 낮출 수 있다.

```swift
let memoryFirst = try await DocumentParser.parseBatch(
  inputs,
  options: .init(performOCR: true, maximumConcurrentDocuments: 1)
)
```

작은 OCR 배치의 Simulator 교차 비교에서는 동시 1의 최대 footprint가 약 56.14MiB 낮은 대신 시간 중앙값이 약 0.863초 길었다. 20표본의 결과는 같았지만 실기기에서는 검증하지 않았다. 입력별 보장값은 아니며, 설정·환경은 [검증 기록](RELEASE_MEMORY_2026-10-28.md#동시-문서-12의-메모리시간-절충)을 확인한다.

## 오류 반환

단일 `parse`는 외부 백엔드 오류를 포함해 `DocumentParsingError`로 정규화한다. 이미 분류된 열기·형식·크기·암호화 오류는 유지하고, 분류되지 않은 백엔드 오류는 `malformedDocument`, 취소는 `cancelled`로 반환한다. 원문을 포함할 수 있는 외부 오류 메시지를 그대로 노출하지 않는다.

`parseBatch`의 개별 failure도 같은 분류를 사용한다. 배치 전체 취소는 `CancellationError`를 던질 수도 있다. 실패·취소 진행 이벤트는 해당 문서의 최종 상태로 한 번 전달하며, 다른 문서의 결과는 입력 순서대로 보존한다.
