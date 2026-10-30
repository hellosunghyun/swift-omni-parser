# RTF 지원 범위

RTF는 본문 문자열 외에 표·셀 위치·내장 래스터 그림과 선택적 OCR을 반환한다. 본문과 표는 UIKit의 `NSAttributedString` RTF importer가 제공한 속성을 읽고, importer가 버리는 `pict` 데이터만 별도로 분리한다. 새 외부 라이브러리나 런타임 바이너리는 추가하지 않는다.

## 호출

```swift
let result = try await DocumentParser.parse(
  .url(rtfURL),
  options: .init(extractImages: true, performOCR: true)
)

let cells = result.blocks.filter { $0.kind == .tableCell }
let ocr = result.blocks.filter { $0.kind == .imageOCR }
```

`extractImages`와 `performOCR`은 각각 기본값이 `false`다. 두 옵션이 꺼져 있어도 본문과 표를 읽는다. OCR만 켜면 그림의 텍스트를 블록으로 반환하고 PNG는 보관하지 않는다. 두 옵션을 모두 켜면 제공 가능한 PNG와 OCR 블록을 함께 반환한다.

## 구조·위치·읽기 순서

| 요소 | 반환 범위 |
|---|---|
| 본문·유니코드 | 시스템 importer가 읽은 문단 텍스트. 글꼴·페이지 레이아웃 재현 기능은 제공하지 않음 |
| 목록 | importer가 본문 텍스트로 제공한 목록 내용. 사용자 정의 번호·들여쓰기의 완전한 복원은 보장하지 않음 |
| 표 | `table` 블록과 `tableCell` 블록, 1부터 시작하는 행·열 번호 |
| 병합 셀 | importer가 제공한 `rowSpan`·`columnSpan`. 제공되지 않은 병합 범위를 추측하지 않음 |
| 그림 | hex·`bin` 저장 방식의 `pict`에서 추출한 PNG·JPEG 등 디코딩 가능한 래스터 |
| OCR | Vision 온디바이스 인식 텍스트·제공 가능한 신뢰도·그림 안 위치와 문서 내 위치 |

표의 `part`는 `rtf/table[n]` 형태다. 문단의 `paragraph`는 importer 결과의 문단 순서이며 원본 RTF 파일 줄 번호가 아니다. 그림의 `part`는 보통 `rtf/byte[offset]/image[n]` 형태로 원본 그룹의 바이트 위치를 가리킨다. 손상 원본 대신 호환본을 복구하면 `rtf/byte[offset]`로 실제 사용한 호환본 위치를 남긴다. 그림이 셀 안에 있으면 행·열 등 제공 가능한 셀 위치도 함께 남긴다. 페이지 번호나 페이지 기하 좌표는 임의로 생성하지 않는다.

그림 자리의 임시 마커를 본문 순회 중 소비해 OCR 블록을 해당 위치에 넣는다. 마커는 결과에 남기지 않는다. 셀은 여러 텍스트 조각을 한 셀 블록으로 모으므로 셀 안 텍스트와 그림의 세부 인라인 순서에는 차이가 생길 수 있다. 이 경우 셀 위치와 `uncertainReadingOrder` 경고를 반환한다.

Word가 인접한 `shppict`/`nonshppict` 그룹에 같은 그림의 원본·호환본을 기록한 경우 한 번 처리한다. 정상 원본을 우선하며 원본 디코딩이 실패하면 연결된 호환본을 시도하고 원본 위치에 경고를 남긴다. 모든 문서의 비슷한 그림을 내용 비교로 합치는 전역 중복 제거는 아니다.

## 부분 실패와 제한

- 손상된 hex 그림이나 디코딩할 수 없는 그림은 그 위치에 `extractionFailed` 경고를 남기고 다른 본문·표·그림을 보존한다.
- PNG 보관에 성공한 그림은 OCR 실패 후에도 유지되며 `imageOCRFailed` 경고를 반환한다. PNG 보관 한도를 초과한 경우는 별도 `resourceLimitReached` 경고로 알린다.
- 문서 안 그림 개수, 이미지 픽셀 수, 결과 PNG 보관 바이트는 요청의 제한을 따른다. 제한 뒤의 그림 처리는 생략할 수 있지만 이미 읽은 본문과 표는 남긴다.
- RTF 그룹 깊이는 최대 256으로 제한한다. 그림 그룹 수에는 `maximumArchiveEntries` 상한도 적용한다. 이 상한을 넘으면 `inputTooLarge`로 종료한다.
- 구조 손상 경고는 최초 1회로 제한한다. 제어어가 64자, 숫자 인자가 20자를 넘으면 `malformedDocument`로 종료하고, 진행 바이트 수에 따라 취소를 점검한다.
- 음수·범위 초과·잘못된 `bin` 길이는 시스템 importer에 전달하지 않고 `malformedDocument`로 종료한다.
- 불균형·잘린 그룹과 importer 실패는 가능한 경우 원문 텍스트와 `malformedContent` 경고로 복구한다. 이 텍스트에는 RTF 제어어가 남을 수 있으므로 정상 구조 추출과 구분해야 한다.
- importer가 그림의 읽을 수 있는 본문 위치를 제공하지 않으면 원본 바이트 위치와 `unsupportedElement` 경고를 남긴다.

현재 UIKit importer는 `pict`를 버리고, 보완 경로의 ImageIO 디코더로는 단독 WMF·EMF 같은 벡터 `pict`를 래스터화하지 못한다. 별도 온디바이스 벡터 렌더러의 도입은 구현·빌드·의존성 검토가 남아 있어 지원한다고 표시하지 않는다. 원본 래스터와 함께 있는 호환 벡터는 중복 처리를 피하지만, 벡터만 있는 문서에서 같은 그림을 복원할 수 있다는 뜻은 아니다. OLE 객체, 중첩 표의 전체 계층, 헤더·푸터의 완전한 추출도 현재 검증 범위에 포함되지 않는다.

## 검증 범위

`Tests/OmniParserTests/RTFRegressionTests.swift`에서 다음 동작을 검사한다.

- 자체 생성 표·PNG·OCR과 기존 일본어 표·JPEG 이미지 RTF 샘플.
- 이미지/OCR 옵션 네 조합, 원본 위치와 결과 텍스트·블록의 일관성.
- binary 그림, 이스케이프된 본문, Unicode, 제공된 가로·세로 병합 셀 위치, 다중 문단과 별도 표 식별자.
- 손상 그림 뒤 텍스트·그림 보존, 원본·호환 그림 중복 제어 및 손상 원본의 정상 호환본 복구.
- 셀 안 그림의 위치·순서 경고, PNG 보관 예산 초과 시 OCR 보존.
- 그림 생략·치환 뒤 제어어 경계와 본문 보존.
- 그림 개수·픽셀·PNG 바이트 제한과 위험한 binary 길이 거부.

Office와 공유하는 이미지 경로의 OCR 실패 후 PNG 보존은 `ResourceAndCancellationTests`에서 오류를 주입해 검사한다. 테스트 목록은 검사 의도를 나타내며 전체 문서 형식의 완전한 복원 판정이 아니다. 통과 수치·실행 기기·미실행 항목은 [회귀 검증 기록](REGRESSION_TESTS.md)의 해당 실행 결과를 따른다.
