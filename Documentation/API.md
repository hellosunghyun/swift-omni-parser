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
- PDF·Office·HWP·RTF의 내장 그림과 HTML·Markdown의 내장·로컬 참조 그림에 적용한다. 각 형식이 제공하는 요소와 위치 정보의 범위 안에서 처리한다.
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

## RTF 추출 경로

```swift
let result = try await DocumentParser.parse(
  .data(rtfData, fileName: "report.rtf"),
  options: .init(extractImages: true, performOCR: true)
)
let cells = result.blocks.filter { $0.kind == .tableCell }
let images = result.images
```

- 시스템 RTF importer가 제공한 본문·표·셀과 병합 범위를 읽는다. 표와 셀은 `table`·`tableCell` 블록이며 행·열 번호는 1부터 시작한다.
- `location.part`의 `rtf/table[n]`은 문서 안에서 만난 표의 식별자다. `paragraph`는 importer가 읽은 문단 순서이며, 원본 파일의 줄 번호나 페이지 번호가 아니다. 페이지 좌표를 임의로 생성하지 않는다.
- 내장 `pict`의 hex·`bin` 데이터를 분리해 ImageIO로 디코딩하고 Vision으로 OCR한다. 그림의 `part`에는 원본 그룹의 바이트 위치가 들어가며 제공 가능한 문단·셀 위치도 함께 보존한다.
- 본문의 그림 위치에 OCR 블록을 넣는다. 셀 텍스트는 한 셀 블록으로 묶기 때문에 셀 안 텍스트와 그림의 세부 인라인 순서는 `uncertainReadingOrder` 경고와 함께 반환할 수 있다.
- 인접한 Word `shppict`/`nonshppict` 원본·호환 그림 쌍은 한 번 처리한다. 그림을 생략하더라도 RTF 그룹 경계를 유지해 인접 제어어와 본문이 합쳐지지 않게 한다.
- PNG·JPEG 등 디코딩 가능한 래스터를 대상으로 한다. 단독 WMF·EMF, OLE 객체, 중첩 표 계층, 헤더·푸터의 완전한 복원을 보장하지 않는다. 시스템이 본문 위치를 제공하지 않은 그림은 `unsupportedElement` 경고로 식별한다.

부분 실패·제한과 실제 검증 범위는 [RTF 지원 문서](RTF_SUPPORT.md)에 있다.

## 오류 반환

단일 `parse`는 외부 백엔드 오류를 포함해 `DocumentParsingError`로 정규화한다. 이미 분류된 열기·형식·크기·암호화 오류는 유지하고, 분류되지 않은 백엔드 오류는 `malformedDocument`, 취소는 `cancelled`로 반환한다. 원문을 포함할 수 있는 외부 오류 메시지를 그대로 노출하지 않는다.

`parseBatch`의 개별 failure도 같은 분류를 사용한다. 배치 전체 취소는 `CancellationError`를 던질 수도 있다. 실패·취소 진행 이벤트는 해당 문서의 최종 상태로 한 번 전달하며, 다른 문서의 결과는 입력 순서대로 보존한다.

구조 일부를 읽지 못했어도 복구 가능한 텍스트·그림은 결과에 남긴다.

- JSON·XML·RTF 구조 해석 실패 후 원문 텍스트로 복구하면 위치가 있는 `malformedContent` 경고를 반환한다. 복구 텍스트에는 원래 형식의 제어어가 남을 수 있다.
- XML 외부 엔티티는 해석하지 않는다. 내부 엔티티 선언을 만나면 확장 전에 구조 해석을 중단하고 원문과 `unsupportedElement` 경고를 반환한다.
- Office·RTF 그림이 정상 디코딩되고 PNG 보관이 성공했다면 OCR 실패 후에도 PNG를 유지하고 `imageOCRFailed` 경고를 반환한다. 그림 보관 한도 때문에 PNG가 남지 않은 경우까지 보존을 보장하지 않는다.
- RTF 그림 손상·디코딩 실패는 해당 그림 위치의 경고로 남기고 뒤의 본문·표·그림 처리를 계속한다. 잘못된 binary 길이 등 안전하게 처리할 수 없는 입력은 `malformedDocument`, 구조·자원 상한 초과는 `inputTooLarge`로 종료할 수 있다.
