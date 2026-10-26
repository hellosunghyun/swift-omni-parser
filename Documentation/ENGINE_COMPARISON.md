# Ream·JDoc 동일 샘플 비교 및 추가 대체 경로

> 개인 절대 경로는 [로컬 검증 경로 별칭](RESEARCH_PATHS.md)으로 표기했다. 원시 로그·진단 덤프는 저장소에 포함하지 않는다.

후속: [Ream iOS 연결 실험](REAM_IOS_EXPERIMENT.md)에서 PPT 패치·그림 보완과 iOS 실행을 추가 검증했다. 아래 내용은 패치 전 비교 결과다.

검증일: 2026-10-26. 운영 패키지의 소스·의존성·LICENSE는 변경하지 않았다.
외부 테스트 문서를 새로 다운로드하거나 문서를 업로드하지 않았다. 기존 원본 29개를 재사용하고 모든 입력 SHA-256을 확인했다.

## 결론

- Ream과 JDoc 중 Office 구조를 그대로 매핑하는 후보는 Ream이 상대적으로 유리했다. DOC 표와 XLS 원본 셀 모델·그림·좌표에 접근했다. 그러나 DOC OfficeArt 그림, 구형 PPT 표, iOS 실행·취소·자원 제한은 남아 있다.
- JDoc은 HWP/HWPX까지 열지만 structured tables와 일부 이미지 누락이 있었다. Markdown의 표 보존과 구조화 API 보존을 구분해야 한다.
- 현재 구현도 전체 정답이 아니다. DOCX 표 원본 XML에는 6셀이 있는데 현재 API는 3셀, Ream/JDoc은 6셀이다.
- 현재 66줄의 DocumentLegacyImageExtractor와 기존 OLEKit 기반 컨테이너 읽기를 재사용하면, 확인된 DOC 그림 누락을 보완할 수 있다. 파서 전체 교체 또는 OfficeOxide 전체 fallback과는 다른 방법이다. PPT 표는 이 코드로 복구되지 않는다.
- 추가로 Xberg와 unhwp를 실행했다. Xberg 배포 WASM은 완전 대체도 용량 절감도 입증하지 못했다. unhwp는 HWP/HWPX 소스 기반 후보로 추가 검증할 가치가 있다.

## 환경·고정 버전

| 엔진 | 버전/리비전 | 실제 실행 환경 |
|---|---|---|
| 현재 OmniParser | ddc987b24e5489e633188db03c7028bb8c3a9bfe | iPhone 17 iOS 27.0 Simulator, Xcode 27.1, Swift 언어 모드 5.0 |
| Ream | 1.33.1 / 253cb67f1f7f8d3f7493f4f2ba09a8855fe16d24 | macOS Node 26 / tsx |
| JDoc | 1.6.3 / 4a08dc73ac07755308a3f2222d11c57f2ef54120 | macOS arm64 C++17 Release |
| Xberg 배포 WASM | @xberg-io/xberg-wasm 1.3.10 | macOS Node 26 WebAssembly |
| Xberg 소스 확인만 | 1.4.0 / fed42bd967ec022688a5563c56a47f7b7c2986ce | 소스·manifest 검토, 빌드 미실행 |
| unhwp | 0.23.0 / a061e12ab6d03d66dc717d4bc4f797f42243a747 | macOS Rust dev |

OmniProbe의 Sources 42개는 현재 운영 Sources와 바이트 단위로 동일함을 확인했다. 테스트만 별도 캐시에 추가했다.
플랫폼·언어·출력 모델이 달라 이번 실행 시간을 엔진 간 성능 우열로 비교하지 않았다.

## 동일 문서 결과

29개 = 구형 Office 12개 + OOXML 9개 + HWP 5개 + HWPX 3개.
표기: 표 / 셀 / 그림. Ream XLS·XLSX는 인쇄용 FlowDoc의 빈 셀을 포함하는 수 대신 원본 SheetDoc의 비어 있지 않은 셀 수를 표시한다. 다른 엔진의 표 셀 수에는 빈 패딩 셀·병합 정책 차이가 있어 수가 크다는 이유로 정확하다고 판정하지 않는다.

| 문서 | 현재 | Ream | JDoc | Xberg WASM |
|---|---:|---:|---:|---:|
| LegacySample.doc | 1 / 2 / 1 | 1 / 2 / 1 | 0 / 0 / 1 | 0 / 0 / 0 |
| real-doc-01-SampleDoc.doc | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| real-doc-02-simple-table.doc | 1 / 6 / 0 | 1 / 6 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| real-doc-03-pictures_escher.doc | 0 / 0 / 2 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| LegacySample.xls | 1 / 2 / 1 | grid 2 / 그림 1 | 1 / 2 / 0 | 1 / 2 / 0 |
| real-xls-01-mortgage-calculation.xls | 1 / 7 / 0 | grid 7 / 그림 0 | 1 / 8 / 0 | 1 / 8 / 0 |
| real-xls-02-sumifs.xls | 5 / 195 / 0 | grid 195 / 그림 0 | 5 / 246 / 0 | 5 / 246 / 0 |
| real-xls-03-testEXCEL-charts.xls | 2 / 12 / 0 | grid 15 / 그림 0 | 3 / 42 / 0 | 3 / 40 / 0 |
| LegacySample.ppt | 1 / 2 / 1 | 0 / 0 / 1 | 0 / 0 / 1 | 0 / 0 / 1 |
| real-ppt-01-SampleShow.ppt | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| real-ppt-02-pictures.ppt | 0 / 0 / 2 | 0 / 0 / 4 | 0 / 0 / 4 | 0 / 0 / 2 |
| real-ppt-03-WithMaster.ppt | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| real-docx-01-SampleDoc.docx | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| real-docx-02-table_footnotes.docx | 1 / 3 / 0 | 1 / 6 / 0 | 1 / 6 / 0 | 1 / 6 / 0 |
| real-docx-03-VariousPictures.docx | 0 / 0 / 2 | 0 / 0 / 5 | 0 / 0 / 5 | 0 / 0 / 5 |
| real-xlsx-01-DataTableCities.xlsx | 3 / 185 / 0 | grid 185 / 그림 0 | 3 / 306 / 0 | 3 / 234 / 0 |
| real-xlsx-02-AverageTaxRates.xlsx | 3 / 1108 / 0 | grid 1110 / 그림 0 | 3 / 1768 / 0 | 3 / 1690 / 0 |
| real-xlsx-03-ExcelPivotTableSample.xlsx | 3 / 50 / 0 | grid 50 / 그림 0 | 3 / 68 / 0 | 3 / 60 / 0 |
| real-pptx-01-SampleShow.pptx | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| real-pptx-02-table-with-different-font-colors.pptx | 2 / 32 / 0 | 2 / 32 / 0 | 2 / 32 / 0 | 0 / 0 / 0 |
| real-pptx-03-WithMaster.pptx | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| real-hwp-01-noori.hwp | 5 / 36 / 4 | 미지원/오류 | 0 / 0 / 4 | 5 / 42 / 4 |
| real-hwp-02-space-width.hwp | 0 / 0 / 0 | 미지원/오류 | 0 / 0 / 0 | 0 / 0 / 0 |
| real-hwp-03-gonggongnuri.hwp | 0 / 0 / 1 | 미지원/오류 | 0 / 0 / 1 | 0 / 0 / 1 |
| real-hwpx-01-space-width.hwpx | 0 / 0 / 0 | 미지원/오류 | 0 / 0 / 0 | 0 / 0 / 0 |
| real-hwpx-02-noori.hwpx | 5 / 36 / 4 | 미지원/오류 | 0 / 0 / 1 | 5 / 40 / 1 |
| real-hwpx-03-column.hwpx | 0 / 0 / 0 | 미지원/오류 | 0 / 0 / 0 | 0 / 0 / 0 |
| BinarySample.hwp | 1 / 2 / 1 | 미지원/오류 | 0 / 0 / 0 | 1 / 2 / 1 |
| BinaryCompressed.hwp | 1 / 2 / 1 | 미지원/오류 | 0 / 0 / 0 | 1 / 2 / 1 |

- 열기: 현재 29/29, Ream 21/29(한글 8개 미지원), JDoc 29/29, Xberg WASM 29/29.
- 기존 본문 확인 문구: 현재 30/30, Ream 지원 문서 26/26, JDoc 30/30, Xberg 30/30. 확인 문구가 없는 문서도 있다. 전체 텍스트 정확도나 모든 위치·순서 검증 결과가 아니다.
- DOCX VariousPictures 원본에는 WMF 1개, EMF 2개, JPEG 1개, PNG 1개가 있다. 현재 2개와 후보 5개는 지원 이미지 유형 차이가 있어 곧바로 추출 정확도 차이로 해석하지 않는다. 벡터 bytes 반환과 iOS 래스터화·OCR 성공도 다르다.
- XLS sumifs는 Ream 원본 셀 모델에서 195개이며 row/column을 가진다. 종전 FlowDoc 226개를 원본 사용 셀 수로 비교하면 안 된다.
- JDoc DOC 표는 Markdown에는 남지만 PageChunk.tables는 비어 있다. 공개 PageChunk는 기존 DocumentLocation과 동일한 셀 좌표·이미지 사각형 계약을 제공하지 않는다.
- Ream·Xberg의 global fetch를 실패시키고 실행했으며 이번 parse/Markdown/bytes extraction에서는 네트워크 호출 0회였다. 다른 변환 API의 오프라인 동작까지 보장하지 않는다.

## 확인된 보완 경로

### 기존 OfficeArt 추출기 재사용

iPhone 17 Simulator에서 DocumentCompoundFile.streams → DocumentLegacyImageExtractor.extract를 직접 호출했다. OfficeOxide/OdrCore 파싱 API를 호출하지 않는 테스트다. 테스트 바이너리에는 기존 의존성이 링크돼 있으므로 해당 소스만으로 별도 패키지를 빌드했다는 의미는 아니다.

- real-doc-03-pictures_escher.doc: 이미지 2개, 원본 바이트 합계 105,446.
- LegacySample.xls: 이미지 1개, 원본 바이트 13,771.
- 기대 개수 assertion 2/2 통과. DocumentCompoundFile의 바이트·항목 제한과 OLEKit은 함께 필요하다.
- Ream 결과와 합치는 중복 제거·앵커·경고 연결 및 실제 OCR은 아직 통합하지 않았다.

### Ream 구형 PPT 표 보완

PPT reader는 도형 텍스트·그림을 FlowDoc으로 구성하지만 이번 표 샘플을 table로 만들지 않았다. 공개 API 결과 매핑만으로 해결된다고 판단하지 않는다. 기존 OfficeOxide PPT 처리를 유지하거나 reader를 수정해야 한다. Xberg 최신 소스에는 OfficeArt group/tableProperties 기반 read_table 경로가 있어 참고 가능한 별도 구현을 확인했지만, 이를 Ream에 이식하거나 iOS에서 검증하지 않았다.

## 추가 후보 1: Xberg

- 공식 저장소: https://github.com/xberg-io/xberg
- 공식 Swift manifest: packages/swift/Package.swift. iOS 16 선언과 Rust bridge가 있으나 Cargo 빌드·alef 생성 과정과 정적 라이브러리 연결이 필요하다. 완성된 단일 Swift 소스 패키지 추가와는 다르다.
- 자체 LICENSE는 MIT. 전이 의존성과 선택 기능의 고지는 별도다.
- 배포 WASM 1.3.10은 같은 29개를 모두 열었지만 DOC 표/그림·PPT/PPTX 표 누락이 남았다. HWPX는 application/hwp+zip MIME으로 실행했다. 최초 비등록 MIME으로 발생한 오류는 수정 후 재실행한 결과에서 제외했다.
- 최신 1.4.0 소스는 DOC 표·그림, PPT 표, HWP 표·그림 경로를 갖는다. 배포 WASM 1.3.10 결과를 최신 소스의 결과로 일반화하지 않는다.
- 번들 실측: WASM 38,161,699bytes + JS 1,762,354bytes = 약 38.08MiB. docs/types와 OCR 모델은 제외한 런타임 두 파일이다. 현재 OmniParser 앱 증가량 16.05MiB와 동등 조건의 네이티브 앱 비교가 아니다. 선택 기능으로 축소한 Rust iOS 빌드는 미측정이다.

## 추가 후보 2: unhwp

- 공식 저장소: https://github.com/iyulab/unhwp
- 원문 MIT 확인. HWP/HWPX 구조 API, 메모리 입력, 표 순서·병합과 resource bytes에 접근 가능하다. LGPL CoreHwp 대체 후보이지만 아직 운영 의존성을 제거하지 않았다.
- 0.23.0을 hwp5/hwpx feature로 실행했다. 8/8 열기 성공, 자체 문서 본문/셀 마커 4/4 일치, skipped_sections는 모두 빈 배열이다.

| 문서 | 표 | 셀 | 이미지 |
|---|---:|---:|---:|
| real-hwp-01-noori.hwp | 5 | 40 | 4 |
| real-hwp-02-space-width.hwp | 0 | 0 | 0 |
| real-hwp-03-gonggongnuri.hwp | 0 | 0 | 1 |
| real-hwpx-01-space-width.hwpx | 0 | 0 | 0 |
| real-hwpx-02-noori.hwpx | 5 | 40 | 4 |
| real-hwpx-03-column.hwpx | 0 | 0 | 0 |
| BinarySample.hwp | 1 | 2 | 1 |
| BinaryCompressed.hwp | 1 | 2 | 1 |

8개 전체에 대한 셀·원본 위치 정답은 없다. noori 40셀과 현재 36셀의 차이는 병합 및 빈 셀 표현까지 확인해야 한다. 이미지 바이트 보존·실제 디코딩/OCR·원본 좌표·취소·자원 제한·iOS 크로스 빌드와 Swift 연결은 미검증이다. Rust 툴체인 또는 생성 바이너리가 필요하므로 이를 순수 Swift로 설명하지 않는다. 전이 라이선스 감사는 별도다.

## 그 밖의 방법

- officeParser: 브라우저 지원 AST와 OOXML·RTF·HTML 등을 제공하지만 공식 지원 목록에 구형 DOC/XLS/PPT와 HWP가 없어 전체 대체가 아니다. https://github.com/harshankur/officeParser
- SheetJS CE: XLS 값·셀 모델 후보지만 그림 기능은 Pro 영역으로 안내되어 무료 전체 대체로 보지 않는다. https://docs.sheetjs.com/docs/api/parse-options/
- Document Liberation의 libmwaw/libwps는 legacy Mac/Works 중심이므로 Windows DOC97/XLS/PPT 전체 대체로 확대 해석하지 않는다. https://www.documentliberation.org/projects/
- 같은 OfficeOxide를 소스부터 빌드하면 사전 제작 바이너리를 저장소에 둘 필요는 줄일 수 있지만, Rust 제작·Swift/C 연결 관리가 남는다. 같은 코드를 링크하면 최종 앱 용량 감소를 기대할 근거는 없다.

## 추천

1. Office 대체는 Ream + 기존 작은 OfficeArt 추출기 재사용을 검증하고, 구형 PPT 표는 별도 통과 조건으로 둔다. HWP·PDF·Vision·공통 배치/취소/제한은 검증 전 유지한다.
2. HWP 라이선스·소스 배포 부담이 목표라면 unhwp를 별도 iOS 어댑터로 검증한다. Office 교체와 동시에 추진해야만 하는 의존성은 아니다.
3. 전체 Rust 엔진 통합을 검토할 경우 Xberg 최신 native source를 다음 비교 대상으로 삼을 수 있다. 배포 WASM은 현재 용량 목표의 우선 후보로 보지 않는다.
4. JDoc 단독은 이번 누락 수와 API 보완량 기준에서 Ream보다 우선할 근거를 얻지 못했다.

위 조합 중 기능 동등성이 확인된 완전 대체는 아직 없다. 앞서 제시한 4~9MiB/6~15MiB 범위는 이 결과로 검증되지 않았으므로 의사결정의 확정 용량으로 사용하지 않는다.

## 재현·범위

- Ream: reamkit에서 ./node_modules/.bin/tsx comparison-probe.ts.
- JDoc: SameCorpusComparison/jdoc-probe.cpp를 기존 Release libjdoc.a, zlib, libjpeg, libdeflate와 링크 후 inputs.json 29개를 실행.
- Xberg: XbergWasmProbe에서 node probe.mjs. package-lock.json 고정, npm 설치 스크립트 비활성화.
- unhwp: UnhwpProbe에서 cargo run --quiet. Cargo.lock 보존.
- 현재: OmniProbe에서 xcodebuild test -scheme OmniParser -destination 'platform=iOS Simulator,id=46BECA1F-89C4-42E2-B9DD-5F6CB316E62B' -derivedDataPath ../ProbeDerivedData -clonedSourcePackagesDirPath ${OMNI_CACHE_ROOT}/SourcePackages -skipMacroValidation -only-testing:LegacyProbe/SameCorpusProbe CODE_SIGNING_ALLOWED=NO.

SameCorpusProbe의 29문서 수집 XCTest와 별도의 testSupplementRecovery XCTest 모두 TEST SUCCEEDED. 29개의 정확도 테스트가 통과했다는 뜻은 아니다. OCR은 false로 고정했고 PDF·TIFF·암호화·손상/폭탄 입력·배치 취소·기기 메모리 성능은 이번 비교에서 실행하지 않았다. 후보 엔진의 iOS 실행도 미실행이다.

연구 루트: ${OMNI_RESEARCH_ROOT}/
세부 결과: SameCorpusComparison/comparison.json, 각 *-results.json, *-run.log, inputs.json.
생산 소스 변경이 없어 이번에 production build/lint를 다시 실행하지 않았다. 커밋·푸시는 하지 않았다.
