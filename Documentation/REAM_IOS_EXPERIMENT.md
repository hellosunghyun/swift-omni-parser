# Ream iOS 연결 실험

> 개인 절대 경로는 [로컬 검증 경로 별칭](RESEARCH_PATHS.md)으로 표기했다. 원시 로그·진단 덤프는 저장소에 포함하지 않는다.

> 후속 구현·최종 앱 크기·Release 비교는 [Ream 교체 검증 결과](REAM_REPLACEMENT_RESULTS.md)를 참고한다. 아래는 앞선 어댑터 실험 기록이며 현재 전체 상태를 나타내지 않는다.

2026-10-26. 운영 의존성과 소스를 바꾸지 않고, 기존 연구용 OmniProbe의 XCTest 타깃에서 실행했다. 공개 DocumentParser API의 Office 백엔드는 아직 교체하지 않았다.

## 결론

- 실험 패치로 구형 PPT 자체 샘플의 표 0셀 → 2셀, 행/열·슬라이드·정규화된 사각형을 반환했다.
- 기존 작은 OfficeArt 추출기를 연결해 Ream이 놓친 DOC 그림 2개를 복구했다.
- iPhone 17 iOS 27.0 Simulator의 JavaScriptCore에서 Office 21개 문서가 열렸고, 기존 확인 문구 26/26이 일치했다. 전체 텍스트·블록의 결합 일관성과 0부터의 읽기 순서도 문서별로 assertion했다. 전체 내용·원본 읽기 순서의 정답 검증은 아니다.
- 기본 이미지/OCR false, OCR만 true, 이미지 true를 시험했다. 영어 이미지 OCR 마커를 인식했다. 한영 혼합 OCR 및 모든 이미지 형식의 정확도 검증으로 확대 해석하지 않는다.
- 이 결과로 기존 OfficeOxide/OdrCore를 제거할 수 있다고 결론내리지 않는다. 남은 교체 기준은 [회귀 기준](REPLACEMENT_REGRESSION_CRITERIA.md)을 따른다.

## PPT 패치 범위

Ream 1.33.1 / `253cb67f1f7f8d3f7493f4f2ba09a8855fe16d24`의 연구용 clone에만 적용했다.

- 그룹 자신의 OfficeArt `tableProperties`를 확인한 뒤 셀 도형의 좌표로 행·열을 구성한다. 임의로 정렬된 텍스트 상자를 표로 추정하지 않는다.
- 행·열 재구성은 최대 10,000칸으로 제한한다. 겹치는 앵커·그림 포함 그룹·복잡한 중첩 그룹은 원래 도형 경로를 보존한다. 이것은 표 복원을 보장한다는 뜻이 아니다.
- 표 전용 슬라이드가 텍스트 fallback으로 중복되는 것을 막았다. 원래 95개 테스트와 추가 4개(역순 셀, 일반 그룹, 충돌 앵커, 표 전용 슬라이드 다음 페이지)가 통과했다.
- 빈 셀·병합 셀·복잡한 중첩 표는 미검증이다. 현재 패치로 텍스트 없는 셀이나 span을 완전하게 보존한다고 말할 수 없다. 패치의 FlowDoc 렌더링 위치 보존도 별도 확인이 필요하다.

## iOS 연결 구성

- `reamkit/ios-experiment.ts`: DOC/DOCX/XLS/XLSX/PPT/PPTX reader를 직접 호출하고 텍스트·셀·이미지 바이트·경고를 JSON으로 매핑한다. PDF 변환·원격 폰트 공급 경로를 가져오지 않는다.
- PPT는 패치된 원본 도형 모델에서 셀 좌표를 읽는다. XLS/XLSX는 인쇄용 FlowDoc 대신 SheetDoc 원본 셀을 읽는다.
- `OmniProbe/Tests/LegacyProbe/ReamOfficeExperiment.swift`: JavaScriptCore와 Foundation 인코딩 연결, 기존 공통 결과 모델, ImageIO·Vision과 OfficeArt 보완을 연결한다.
- `ReamIOSExperimentTests.swift`: 본문 확인 문구, 표/그림 개수, 위치 일부, fullText 일관성, 옵션, 입력 제한, 손상 입력 다음 문서 보존, 시작 전 취소를 검증한다.
- JavaScriptCore에는 TextEncoder/TextDecoder/atob/btoa가 없어 연구용 호스트 구현을 연결했다. UTF-8 한영 왕복, UTF-16LE, Windows-1252를 확인했다. WHATWG 인코딩 API 전체 호환·스트리밍·fatal 옵션·CP949는 미검증이다. 모르는 인코딩을 빈 문자열로 바꾸지 않고 오류로 처리한다.
- fetch는 차단하고 호출 수가 0임을 assertion했다. 테스트 입력은 모두 기존 로컬 샘플이며 업로드하지 않았다.

## 실제 결과

| 문서 | 표 | 셀 | 보관 PNG |
|---|---:|---:|---:|
| LegacySample.doc | 1 | 2 | 1 |
| real-doc-01-SampleDoc.doc | 0 | 0 | 0 |
| real-doc-02-simple-table.doc | 1 | 6 | 0 |
| real-doc-03-pictures_escher.doc | 0 | 0 | 2 |
| LegacySample.xls | 1 | 2 | 1 |
| real-xls-01-mortgage-calculation.xls | 3 | 7 | 0 |
| real-xls-02-sumifs.xls | 5 | 195 | 0 |
| real-xls-03-testEXCEL-charts.xls | 2 | 15 | 0 |
| LegacySample.ppt | 1 | 2 | 1 |
| real-ppt-01-SampleShow.ppt | 0 | 0 | 0 |
| real-ppt-02-pictures.ppt | 0 | 0 | 2 |
| real-ppt-03-WithMaster.ppt | 0 | 0 | 0 |
| real-docx-01-SampleDoc.docx | 0 | 0 | 0 |
| real-docx-02-table_footnotes.docx | 1 | 3 | 0 |
| real-docx-03-VariousPictures.docx | 0 | 0 | 2 |
| real-xlsx-01-DataTableCities.xlsx | 3 | 185 | 0 |
| real-xlsx-02-AverageTaxRates.xlsx | 3 | 1110 | 0 |
| real-xlsx-03-ExcelPivotTableSample.xlsx | 3 | 50 | 0 |
| real-pptx-01-SampleShow.pptx | 0 | 0 | 0 |
| real-pptx-02-table-with-different-font-colors.pptx | 2 | 32 | 0 |
| real-pptx-03-WithMaster.pptx | 0 | 0 | 0 |

표 수에는 빈 워크시트도 포함될 수 있다. PNG 개수는 디코딩 가능한 그림을 PNG로 변환하고 동일 바이트를 중복 제거한 결과다. Ream의 resource 수와 직접 비교하면 안 된다. WMF/EMF 등 디코딩 실패는 경고로 남기고 본문 결과를 유지했다. 픽셀 전체 정답이나 원본 이미지 배치와의 완전 일치를 검증하지 않았다.

## 검증

| 항목 | 결과 |
|---|---|
| iOS XCTest | 5/5 PASS, 그중 하나가 Office 21개 corpus를 순회 |
| Ream PPT 원래+추가 테스트 | 99/99 PASS |
| Ream src TypeScript 타입 검사 | PASS |
| 실험용 Swift 2개 SwiftLint strict | PASS, 위반 0 |
| JS 번들 재빌드 | PASS, 테스트한 번들과 SHA-256 동일 |
| 실기기·중간 취소·대용량 배치·위험 ZIP | NOT_RUN |
| 운영 package build/lint | 생산 소스 변경이 없어 재실행하지 않음 |

Office reader 전용 JS 번들은 464,398bytes(약 0.443MiB)다. 이전 전체 API 번들 1,473,452bytes와 범위가 다르다. 실험 테스트 앱에는 기존 OmniParser 의존성이 그대로 링크돼 있으므로 최종 앱 증가량·의존성 제거·순 코드 감소를 입증한 수치가 아니다. 앞서 제시한 대체 앱 용량 예상은 여전히 미검증이다.

## 재현 및 보존 위치

연구 루트: `${OMNI_RESEARCH_ROOT}`.

```bash
bash ${OMNI_RESEARCH_ROOT}/SameCorpusComparison/reproduce-ream-ios.sh
```

기존 Xcode 27.1/iOS SDK 27.1, iOS 27.0 Simulator, Swift 언어 모드 5.0, Node 26과 현재 캐시 의존성이 필요하다. 스크립트는 의존성을 새로 설치하거나 기기를 부팅하지 않는다. booted Simulator ID는 OMNI_SIMULATOR_ID로 지정할 수 있다. 저장소에 새 생산 의존성을 추가하지 않았다.

- `SameCorpusComparison/ream-ppt-experiment.patch`: upstream 수정과 자체 생성 fixture 옵션 패치.
- `reamkit/tests/ppt-table-experiment.test.ts`, `ios-experiment.ts`, `ios.vite.config.ts`: 실험 소스.
- `OmniProbe/Tests/LegacyProbe/ReamOfficeExperiment.swift`, `ReamIOSExperimentTests.swift`: iOS 실험 구성.
- `SameCorpusComparison/ream-ios-summary.json`, `ream-ios-results.json`: 개수·해시·확인 문구 결과.
- `ream-ios-experiment.log`, `ream-ppt-experiment-tests.log`, `ream-typecheck.log`, `ream-experiment-swiftlint.log`: 실행 근거.

Ream 및 runtime 의존성의 원래 라이선스와 출처는 유지해야 한다. 생성 JS 번들의 고지 배포와 iOS 앱 전이 고지 감사는 아직 준비하지 않았으므로 배포용 구성으로 취급하지 않는다. 커밋·푸시는 하지 않았다.
