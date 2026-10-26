# Office 텍스트 차이 11건 원본 대조

> 개인 절대 경로는 [로컬 검증 경로 별칭](RESEARCH_PATHS.md)으로 표기했다. 원시 로그·진단 덤프는 저장소에 포함하지 않는다.

> 후속 작업: [운영 회귀 테스트 반영](REGRESSION_TESTS.md), [Ream/OdrCore XLS 수정 검증](ODR_XLS_FIX_VALIDATION.md). 아래는 이전 단계 기록이며, Ream 수정 후 기존 앱 크기·성능을 다시 측정한 결과는 아닙니다.

2026-10-26. Draft 실험. 현재 운영 엔진과 Ream 교체안의 fullText가 다른 11파일을 대조했다. **단순 공백 3건, 표시 방식 3건, 각주 추가 1건, 목록 표시 1건, 상속 레이아웃 문구 2건, 실제 셀 해석 결함 1건**으로 분류했다. 마지막 결함은 기존 엔진과 Ream 모두에 존재하며 양상이 다르다.

## 방법과 근거 수준

- 두 iOS 패키지의 공개 parse API를 iPhone 17/iOS 27.0 Simulator에서 다시 호출했다. 진단 XCTest는 각각 1개 PASS. 원문은 로그 대신 별도 로컬 JSON에만 저장했다.
- DOCX/XLSX/PPTX 6파일은 원본 ZIP/XML·관계 파일·셀 서식·각주 참조를 직접 확인했다.
- DOC/XLS/PPT 5파일은 설치된 LibreOfficeDev 26.8.0.0.alpha0로 별도 OOXML 사본을 생성해 보조 근거로 사용했다. macOS sandbox-exec에서 네트워크를 금지했고 원본 SHA-256은 전부 보존됐다. 변환본 자체를 절대적인 정답으로 취급하지 않았다.
- XLS 차트와 통화 값은 원본 Workbook BIFF 레코드도 직접 대조했다. CFB stream 접근은 기존 Ream 컨테이너 reader를 사용했지만, BOF/EOF·숫자·FORMULA·FORMAT 순회 코드는 별도로 작성했다.
- 텍스트 차이가 있다는 사실과 원문 누락이라는 판정은 구별했다. 실기기·렌더링 화면·모든 도형/표 정답의 수동 검수는 수행하지 않았다.

## 파일별 판정

| 파일 | 실제 차이 | 원본 근거와 판정 |
|---|---|---|
| `real-doc-03-pictures_escher.doc` | 공백 4개 | 공백을 정규화하면 fullText가 같음. 독립 변환본의 7개 비어 있지 않은 문단은 양쪽에 포함. 텍스트 누락 근거 없음 |
| `real-docx-03-VariousPictures.docx` | 공백·줄 구분 | 공백 정규화 후 같음. 원본 document.xml의 비어 있지 않은 2문단은 양쪽에 포함 |
| `real-xlsx-02-AverageTaxRates.xlsx` | 공백·빈 셀 보존 | 공백 정규화 후 같음. Ream이 원본의 빈 셀 250개와 공백만 있는 셀 2개를 추가 보존. 1,108 → 1,360셀을 본문 추가 추출로 해석하지 않음 |
| `real-xls-01-mortgage-calculation.xls` | 숫자 캐시와 통화 표시 | 원본 B4 FORMULA 캐시 790.7936267415464, FORMAT `"$"#,##0.00`. 기존은 수치 문자열, Ream은 `$790.79`. 표시 정책 차이이며 숫자 손실로 단정하지 않음 |
| `real-xls-02-sumifs.xls` | 17셀의 백분율 표시 | 기존은 소수 값, Ream은 1%·0.50% 등의 표시 문자열. 독립 변환본의 0%/0.00% 서식과 부합. 원시 값과 표시 값 중 계약을 정해야 함 |
| `real-xlsx-01-DataTableCities.xlsx` | 회계 패딩 28셀과 정밀도 1셀 | PivotTable!D18 원본 캐시 845.60000000000014, 기존 845.6, Ream 845.6000000000001. 원문 누락이 아니라 General 표시·부동소수 문자열 정책 차이 |
| `real-docx-02-table_footnotes.docx` | 각주 추가, run 공백·빈 셀 | 원본 footnoteReference id=1과 footnotes.xml의 대응 내용을 Ream이 반환. 표는 실제 6셀 중 3셀만 비어 있지 않음. 기존 3 → Ream 6셀은 빈 셀 보존이며, 본문 한 문구는 누락이 아니라 run 사이 공백 차이 |
| `real-pptx-01-SampleShow.pptx` | 글머리 기호와 탭 3개 | 기존 평문과 Ream의 목록 마커 표현 차이. 마커를 제외하면 내용 같음. 마커를 fullText에 포함할지 계약 필요 |
| `real-pptx-03-WithMaster.pptx` | 상속 레이아웃 문구 2회 추가 | 두 슬라이드가 같은 slideLayout1을 참조하고, 그 레이아웃에 placeholder가 아닌 텍스트 도형이 존재함을 원본 XML에서 확인. 각 슬라이드에 반환하는 것은 구조 근거가 있음. 기존은 해당 문구를 반환하지 않음 |
| `real-ppt-03-WithMaster.ppt` | 마스터 문구 포함 횟수·순서 | 기존 1회, Ream 2회. 독립 변환본에서 두 슬라이드의 공유 레이아웃을 확인해 상속 표현 차이로 분류. 구형 원본의 모든 표시 조건과 픽셀 일치까지 입증한 것은 아님 |
| `real-xls-03-testEXCEL-charts.xls` | 실제 셀과 차트 캐시 혼입 | **두 엔진 모두 오류.** 실제 A1:A3 문자열에 대해 기존은 차트 숫자 1/2/300을 반환. Ream은 실제 문자열과 숫자를 같은 주소에 각각 반환. 좌표 3개가 중복됨 |

LibreOffice는 mortgage 수식을 재계산하며 #VALUE!로 바꿨다. 따라서 그 변환본 값을 원본 캐시의 정답으로 사용하지 않고 원본 BIFF의 캐시와 FORMAT을 직접 읽었다. 독립 변환을 무조건 정답으로 사용하면 잘못된 결론이 나온다.

## 확인한 XLS 결함

원본 Workbook에서 문제 숫자 1/2/300은 worksheet BOF(0x0010) 안에 중첩된 chart BOF(0x0020)의 NUMBER 레코드다. Ream readSubstream은 중첩 레코드까지 반환하고 readSheet의 셀 순회가 chart 깊이를 구별하지 않아 이를 실제 셀 배열에 추가한다. 단순 Set 중복 제거는 어느 값이 실제 셀인지 판정하지 못하므로 해결책이 아니다. **셀 생성에서 차트 substream을 제외하되, 별도의 차트 처리에서는 그 레코드를 유지해야 한다.**

기존 OdrCore 경로는 잘못된 숫자가 실제 셀 좌표의 최종 값으로 나타났다. Swift 경로는 셀 좌표 조회 결과를 그대로 읽으므로 백엔드 안에서 혼입되는 지점은 추가 추적이 필요하다. Ream과 내부 원인이 완전히 같다고 확정하지 않는다.

동일 원본 정답 테스트 `OfficeSourceTruthTests.testChartCachesDoNotReplaceWorksheetCells`를 양쪽에 실행했다.

| 검사 | 기존 엔진 | Ream |
|---|---|---|
| 셀 좌표 유일성 | PASS | FAIL: 3개 좌표 중복 |
| A1:A3가 원본 문자열과 정확히 일치 | FAIL: 3개 assertion | FAIL: 각 주소에 결과 2개 |
| 전체 테스트 판정 | BASELINE_FAIL | FAIL |

앞선 83건 비교 PASS는 두 구성의 동등성/확인 문구에 관한 것이다. 원본 정답 검증 PASS를 의미하지 않는다. 실패 테스트를 expected-failure로 감싸거나 기대값을 잘못된 결과로 바꾸지 않았다. 실제 실패 로그를 별도로 보존했다.

## 재현·보존

연구 폴더: `${OMNI_RESEARCH_ROOT}/OfficeContractAudit`.

- `audit-summary.json`: 파일별 입력 SHA-256·분류·근거 수준. 원문 미포함.
- `native-diagnostics.json`, `ream-diagnostics.json`, `source-evidence-private.json`: 로컬 원문/구조 진단용. 공개 저장소에 포함하지 않음.
- `inspect_source.py`, `convert_references.py`, `raw-biff-audit.ts`, `raw-biff-evidence.json`: 원본/독립 변환 대조와 BIFF 근거.
- `contract_checks.py`, `contract-checks.json`: 셀 좌표 중복·양수 인덱스·유한 좌표 검사. 11문서에서 Ream 중복 3개, 나머지 위치 형식 검사는 통과.
- 인접 `SplitParity/after` 및 `ream`의 진단·정답 XCTest와 `*-diagnostics.log`, `*-source-truth*.log`: 실제 실행 근거.

원본과 운영 패키지 소스는 수정하지 않았다. 커밋·푸시는 하지 않았다. 정답 테스트 중 최초 기존 엔진 실행은 assertion 3건 실패 후 Xcode 진단 수집이 지연돼 해당 xcodebuild만 중단하고 `-collect-test-diagnostics never`로 재실행했다.

정답 테스트 실행 명령(운영 엔진 기준)은 다음과 같다. 실제 실행은 exit 65와 assertion 3개 실패로 끝났고, Ream에서는 같은 테스트에 assertion 4개가 실패했다.

```bash
cd ${OMNI_RESEARCH_ROOT}/SplitParity/after
xcodebuild test -scheme SplitParity-Package \
  -destination 'platform=iOS Simulator,id=46BECA1F-89C4-42E2-B9DD-5F6CB316E62B' \
  -derivedDataPath ../AfterDerivedData \
  -clonedSourcePackagesDirPath ${OMNI_CACHE_ROOT}/SourcePackagesOriginal \
  -skipMacroValidation -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:ParityTests/OfficeSourceTruthTests CODE_SIGNING_ALLOWED=NO
```

Ream 재현은 인접 ream 폴더에서 같은 scheme/테스트를 사용하고 DerivedData를 ../ReamDerivedData, 캐시를 SourcePackagesReam으로 지정한다. 진단 추출은 only-testing을 ParityTests/ParityTests/testOfficeDiagnostics로 바꾼다. 이 진단 테스트는 양쪽 모두 PASS이며 원본 정답 합격을 뜻하지 않는다.
