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
- DOCX·PPTX는 OpenDocument.core를 사용한다. 구형 OfficeArt 내장 그림 복구도 수행한다. 서로 다른 원본 그림 위치의 같은 문구는 각각 OCR 블록으로 남기며, 같은 위치·텍스트가 겹친 추출만 중복으로 제거한다. 이미지·OCR이 모두 꺼져 있으면 그림 복구용 CFB 스트림을 다시 읽지 않는다.
- 라이브러리 소스·라이선스·재빌드와 바이너리 해시는 저장소의 `ThirdParty/OfficeOxide/`에 있다. 앱·CI 빌드에서 Rust를 설치하거나 문서를 외부로 전송하지 않는다.

## 텍스트·PDF의 복원 범위

- TXT·CSV 등의 인코딩은 BOM·UTF-16 패턴과 레거시 문자셋 휴리스틱을 사용한다. CSV는 빈 인용 필드·후행 빈 셀을 보존한다. JSON 객체 키는 정렬하므로 원본 키 순서와 다를 수 있다. 불리언은 `true/false`로 보존해 숫자 `1/0`과 구분한다.
- HTML은 DOM의 본문·제목·목록·표를 읽지만 CSS 시각 조판과 병합 셀의 모든 span을 복원하지 않는다. Markdown은 제목·줄 단위 본문·파이프 표·인라인 그림 참조 범위이며 CommonMark 전체 렌더러가 아니다.
- 독립 SVG 문서는 지원하지 않는다. HTML 안의 SVG 아이콘은 본문 추출을 막지 않으며 `html/svg[n]` 위치의 `unsupportedElement` 경고를 반환한다. Markdown의 SVG 코드 예제는 텍스트로 유지한다.
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

OCR과 PDF는 페이지를 우선한 뒤, 세로 영역이 충분히 겹치는 텍스트를 같은 행으로 묶어 왼쪽부터 정렬한다. 글자 높이 차이로 표 그림의 열 순서가 뒤섞이는 문제를 보완하는 휴리스틱이며, 다단 조판 전체나 스캔 표의 셀 구조 복원은 아니다. 위치·인식 신뢰도·숫자 보정 결과는 정렬에서 바꾸지 않는다.

## 비동기 OCR과 자원 수명

URL 입력은 로컬 파일만 허용하며, 보안 접근과 원본 기준 디렉터리는 전체 파싱 동안 유지한다. 파일 조정은 동기 읽기 구간에서 수행한다. 복제 가능한 일반 파일은 열린 FD에서 비공개 COW 스냅샷을 만들고 `mappedIfSafe`로 읽어 큰 입력의 힙 복사를 줄인다. 스냅샷 경로는 읽기 뒤 제거하지만, 반환한 Data가 매핑을 사용하는 동안 backing 파일의 수명은 유지된다. 원본 변경·교체가 이 스냅샷의 내용을 바꾸지 않는다.

복제를 지원하지 않는 파일시스템, 심볼릭 링크, 파일 플래그 또는 허용하지 않는 보호 등급은 크기 제한이 있는 복사 경로로 처리한다. 원본 보호 속성을 변경하지 않으며, 보호 정책은 잠금 후 접근이 만료되는 등급과 알 수 없는 명시 값을 매핑에서 제외한다. Foundation이 실제 매핑을 선택한다고 보장하지는 않는다. `.data`·CGImage 입력은 기존 경로를 유지한다.

Vision revision 3의 비동기 요청을 사용한다. 기존 한영·정확도·언어 보정과 최소 글자 높이 0을 명시하며, 숫자 보정도 같은 비동기 경로를 사용한다. 호출 중인 요청은 다른 OCR 작업과 공유하지 않고, 실패·취소한 요청은 풀에 보관하지 않는다. 완료한 유휴 요청은 각 parse/parseBatch 호출의 범위 안에서 최대 두 개만 보관한다. 실행 동시성은 문서·PDF 작업창이 제한하며 유휴 요청 수와 구분한다.

작업 전후와 구조 순회·ZIP 해제 중에 취소를 확인한다. 취소와 native 오류가 겹치면 취소를 우선한다. 외부 프레임워크 내부 작업을 일정 시간 안에 강제 중단하거나 프로세스 메모리의 절대 상한을 보장하지는 않는다.

OOXML·HWPX는 native 백엔드 진입 전에 ZIP의 모든 항목을 64KiB 버퍼로 읽어 실제 해제량·CRC·local/central 헤더·descriptor를 확인한다. stored/DEFLATE를 지원하며 컨테이너의 압축·CRC 손상은 문서 오류로 거부한다. 정상 컨테이너 안에서 특정 그림의 디코딩이 실패하는 경우에는 다른 본문·표를 보존하는 부분 복구를 유지한다.

배치의 동시 문서 수와 진행 중 PDF 작업 예산은 결과 전체의 메모리 상한이 아니다. 반환 PNG가 많은 배치는 입력을 작은 묶음으로 나눠 소비하고, PNG가 필요 없으면 `extractImages: false`를 유지한다. 결과의 `fullText`·`blocks`를 호출자가 변경한 경우에는 두 값의 일관성도 호출자가 유지해야 한다.

## 오류 반환

단일 `parse`는 외부 백엔드 오류를 포함해 `DocumentParsingError`로 정규화한다. 이미 분류된 열기·형식·크기·암호화 오류는 유지하고, 분류되지 않은 백엔드 오류는 `malformedDocument`, 취소는 `cancelled`로 반환한다. 원문을 포함할 수 있는 외부 오류 메시지를 그대로 노출하지 않는다.

`parseBatch`의 개별 failure도 같은 분류를 사용한다. 배치 전체 취소는 `CancellationError`를 던질 수도 있다. 실패·취소 진행 이벤트는 해당 문서의 최종 상태로 한 번 전달하며, 다른 문서의 결과는 입력 순서대로 보존한다.
