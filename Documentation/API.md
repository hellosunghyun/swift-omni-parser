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

## Office 추출 경로

- XLS·XLSX는 OpenDocument.core의 셀 좌표 API로 읽는다. HTML 화면용 행·열 눈금과 인쇄용 중복 출력을 본문에 섞지 않는다.
- 셀 주소와 제공 가능한 병합 범위를 보존한다. 희소 셀 조회는 문서 전체 100,000좌표까지 수행하며, 초과하면 이미 읽은 결과와 중단 위치의 `resourceLimitReached` 경고를 반환한다.
- DOC·PPT 본문과 표는 OfficeOxide 0.1.15로 읽는다. 단일 행·열 및 병합 PPT 표의 기존 판정 기준은 고정된 호환 패치로 유지한다.
- DOCX·PPTX는 OpenDocument.core를 사용한다. 구형 OfficeArt 내장 그림 복구는 기존 구현을 유지한다.
- 라이브러리 소스·라이선스·재빌드와 바이너리 해시는 저장소의 `ThirdParty/OfficeOxide/`에 있다. 앱·CI 빌드에서 Rust를 설치하거나 문서를 외부로 전송하지 않는다.

## 텍스트·PDF의 복원 범위

- TXT·CSV 등의 인코딩은 BOM·UTF-16 패턴과 레거시 문자셋 휴리스틱을 사용한다. CSV는 빈 인용 필드·후행 빈 셀을 보존한다. JSON 객체 키는 정렬하므로 원본 키 순서와 다를 수 있다.
- HTML은 DOM의 본문·제목·목록·표를 읽지만 CSS 시각 조판과 병합 셀의 모든 span을 복원하지 않는다. Markdown은 제목·줄 단위 본문·파이프 표·인라인 그림 참조 범위이며 CommonMark 전체 렌더러가 아니다.
- HTML·Markdown 그림은 본문 뒤에 붙고 순서 경고에 문서 형식 part를 남긴다. 원격 그림은 요청하거나 내려받지 않으며 skip 경고에 참조를 남긴다.
- PDF 표는 선·텍스트 정렬 기반 추정이다. 그림은 표시된 페이지 영역을 잘라 래스터로 반환하며 원본 압축 이미지 스트림 추출이 아니다. 이미지 속 표는 OCR 문자만 반환하고 셀 구조를 만들지 않는다.
- PDF 작업 예산은 진행 중인 페이지의 추정 래스터/인식 작업을 제한한다. 반환 PNG와 프레임워크 캐시는 별도여서 프로세스 전체 메모리 상한으로 쓰면 안 된다. PNG가 필요 없으면 기본값인 `extractImages: false`를 유지하고 OCR만 켤 수 있다.

## RTF 구조와 부분 복구

- 시스템 RTF importer의 문단·표 속성을 사용한다. `tableCell`은 1부터 시작하는 행·열과 제공 가능한 병합 범위를 담으며, 같은 셀의 여러 문단은 하나의 셀 텍스트로 합친다.
- 내장 PNG·JPEG 등의 그림은 원본 바이트 위치를 `part`에 남기고, 옵션에 따라 PNG·OCR을 반환한다. Word의 인접한 기본 그림과 호환용 그림은 중복 추출하지 않는다.
- 셀 안의 OCR은 셀 좌표를 유지하지만 셀 텍스트를 합치는 과정에서 정확한 교차 순서를 보장할 수 없어 `uncertainReadingOrder`를 반환한다. 페이지 좌표를 복원하는 기능은 아니다.
- 손상된 그림·미지원 WMF/EMF/DIB 등은 위치가 포함된 경고로 남기며 다른 본문·표·그림을 보존한다. 모든 RTF 그림 인코딩을 지원하는 것은 아니다.
- 그림 개수·픽셀·보관 PNG 크기 제한과 취소를 적용한다. 손상된 `bin` 길이는 importer에 넘기기 전에 거부한다.

JSON·XML·RTF의 구조 해석이 실패해 원문 텍스트로 복구하면 `malformedContent` 경고를 반환한다. XML 외부 엔티티를 해석하지 않으며 내부 엔티티 선언도 확장을 시작하기 전에 중단하고 경고와 원문 텍스트를 반환한다. Office 그림의 OCR이 실패하더라도 이미 추출한 PNG는 보존한다.

## 오류 반환

단일 `parse`는 외부 백엔드 오류를 포함해 `DocumentParsingError`로 정규화한다. 이미 분류된 열기·형식·크기·암호화 오류는 유지하고, 분류되지 않은 백엔드 오류는 `malformedDocument`, 취소는 `cancelled`로 반환한다. 원문을 포함할 수 있는 외부 오류 메시지를 그대로 노출하지 않는다.

`parseBatch`의 개별 failure도 같은 분류를 사용한다. 배치 전체 취소는 `CancellationError`를 던질 수도 있다. 실패·취소 진행 이벤트는 해당 문서의 최종 상태로 한 번 전달하며, 다른 문서의 결과는 입력 순서대로 보존한다.
