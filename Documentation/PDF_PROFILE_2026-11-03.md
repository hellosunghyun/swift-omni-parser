# PDF 페이지별 계측과 OCR 개선 후보 검증 — 2026-11-03

> 이 문서는 최초 판정 기록입니다. 사용자 메모리 절충 요청 후의 최종 재평가와 채택 근거는 [PDF OCR 동시성 재평가](PDF_OCR_CONCURRENCY_2026-11-03.md)를 참조하세요.

## 판단

안전한 처리 시간 개선을 확인하지 못해 OCR 캐시와 병렬화 후보를 모두 제외했다.
제품의 기본 256 MiB 작업 목표, 자동 한영 OCR, 렌더 해상도, 본문·표·좌표 및
페이지/그림 OCR 정책을 유지한다. 남기는 변경은 기본 비활성인 단계별 계측뿐이다.
앱의 `af1293b74a990f1b164df8ffa79851de79e35fbc` revision 유지가 권고안이다.
이 계측 커밋을 성능 개선 revision으로 소개하지 않는다.

## 재현 조건

- 기준: 위 revision에 계측만 추가한 고정 소스. Release, iPhone 17 / iOS 27.0 Simulator.
- 앱 경계와 같은 `DocumentParser.parseBatch([.url])`, `performOCR: true`, 나머지는 기본값.
- 같은 원본 PDF SHA-256, 같은 Simulator lease, 각 invocation은 새 XCTest 프로세스.
- 문서별 A B B A B A 순서, 버전별 3회. 첫 탐색 실행은 아래 중앙값에서 제외했다.
- 모델 선정·분류·UI 시간과 실제 기기는 범위 밖이다. 다른 담당 측정과 독점 슬롯을 교대했다.
- 구조 비교는 fullText, format, 순서 있는 모든 blocks, 위치·표 row/column/span,
  OCR confidence/original text, warnings와 images까지 포함한다.
- 네 기준 문서의 입력 SHA와 본문은 이전 앱 QA와도 일치했다.

## 반복 결과: 기준 → 미채택 3슬롯 후보

24개 결과의 입력·본문·전체 구조는 모두 동일했다. 아래 메모리는 각 실행 중 25ms 샘플
최댓값의 3회 중앙값이며 단위는 MiB다. RSS와 physical footprint는 서로 다른 값이다.

| 문서 | 파싱 중앙값 초 | 샘플 RSS 최대 MiB | 샘플 physical footprint 최대 MiB |
| --- | ---: | ---: | ---: |
| 아스피린 17쪽 | 15.424 → 14.586 | 629.3 → 679.0 | 309.2 → 333.8 |
| 기상측기 5쪽 | 2.452 → 2.355 | 616.0 → 621.4 | 328.0 → 333.2 |
| 완충용액 5쪽 | 8.499 → 8.031 | 625.3 → 695.8 | 288.5 → 347.3 |
| 전도도 5쪽 | 2.956 → 2.875 | 662.5 → 653.9 | 344.6 → 334.9 |

전체 평균이나 타이머/용어 필터로 차이를 숨기지 않았다. 완충용액의 메모리 증가는 세 반복에서
일관되었고, 기본 메모리 목표를 유지했다는 이유만으로 안전하다고 판단하지 않았다.
작업 목표는 OS가 강제하는 프로세스 메모리 상한이 아니다.

## 제외한 후보

1. 동일 픽셀 OCR 캐시: 문서별 최대 4 MiB 계산 예산, 성공한 nonempty 결과만 재사용.
   네 PDF 첫 비교는 동일했으나 cache hit 0건이어서 추가 복잡성과 비용을 채택하지 않았다.
2. 남는 슬롯의 이미지 OCR 병렬화: 기존 풀/바이트 예산과 FIFO를 유지하고 결과를 원래
   순서로 합쳤다. 반복에서 일부 시간이 줄었지만 위 메모리 증가로 제외했다.
3. 추가 슬롯을 1개로 제한: 완충용액 첫 실행 8.819초, sampled physical 360.2 MB,
   RSS 714.7 MB로 메모리 개선을 확인하지 못했다. 이 문장의 MB는 원시 decimal 단위다.
4. 단일 작업의 불필요한 child Task 제거: 첫 완충용액 8.756초, physical 332.3 MB,
   RSS 720.3 MB였다. 기준보다 메모리가 높았고 속도 개선도 확인하지 못해 제외했다.
   3·4번은 탐색 단일 표본이며 3회 반복 결과로 표현하지 않는다.

OCR 캐시와 병렬화 코드는 최종 소스에서 제거하고 QA 사본/patch/hash를 보존했다.
반복 빈 영역의 재시도, 오류 경고, 화학식·스캔 페이지는 모두 유지했다.

## 병목과 계측 사용법

`OMNIPARSER_PDF_TIMING=1`일 때만 stderr에 JSONL을 출력한다. 기본값은 비활성이다.
본문·입력 경로는 기록하지 않는다. 문서 식별자가 없으므로 여러 문서를 동시에 호출한
trace는 구분할 수 없다. 이번 측정은 문서별 독립 invocation을 사용했다. `page`, `stage`, `start_ns`, `end_ns`, `elapsed_ns`를
같은 monotonic clock으로 기록한다. page 0은 문서 열기와 마지막 병합이다.

단계: `document_open`, `page_read`, `scanner`, `tables`, `native_text`, `render`,
`image_prepare`, `image_ocr_vision`, `image_ocr_merge`, `page_ocr_vision`,
`page_ocr_merge`, `merge`.

첫 아스피린 탐색에서 image OCR 52구간 합계 29.94초, page OCR 17구간 합계 15.42초,
render 합계 0.46초였다. OCR 구간은 겹치므로 합계를 전체 17.106초와 더하지 않는다.
이름에 vision이 있는 구간은 숫자 재확인·빈 결과 패딩 재시도도 포함한다.
PDFKit의 지연 작업은 호출된 논리 구간에 포함되며 프레임워크 내부 CPU 시간 분해가 아니다.
실패·취소된 OCR 구간은 성공 시점 record에 도달하지 않아 누락될 수 있다.

## 메모리와 검증 경계

- `mach_task_basic_info.resident_size`: 25ms RSS 샘플 최대.
- `task_vm_info.phys_footprint`: 같은 간격의 physical footprint 샘플 최대.
- `task_vm_info.resident_size_peak`: 프로세스 생애 RSS peak. 샘플 최대와 별도 원자료에 보존.
- `footprint` Dirty TOTAL: 별도 진단의 파싱 전·후 snapshot이며 실행 중 dirty peak가 아니다.
  완충용액 기준 전/후 10,586,320/21,105,304 bytes, 미채택 3슬롯 전/후
  10,586,320/20,892,240 bytes였다. 비슷한 종료 값이 실행 중 peak 증가를 부정하지 않는다.
- 이 프로세스는 파서 XCTest 전용이다. R117/FM를 포함한 앱 전체의 이전 메모리와 직접 비교하지 않는다.
- 원본·중간 결과·실패 로그·전체 xcresult를 보존했다. Documents 아래 테스트 번들 open에서
  멈춘 실행은 sample을 남겼고, Developer 디렉터리의 보존 사본으로 정상 실행했다.
  실패/진단 실행은 반복 성능 표본에서 제외했다.

## 재현 자료

로컬 QA: `/Users/hellosunghyun/Documents/Codex/2026-11-03/labcord-parser-optimization-qa`

`balanced-summary.json`, `baseline-per-page-stages.csv`, `baseline-vs-previous-qa.json`,
각 실행 로그/xcresult/attachments, 후보별 source/patch, `rejected-final/`,
`app-candidate-integration/`에 근거를 분리했다. 최종 실행 개수·경고·실패와 앱 경계 검증은
QA의 `verification.md`와 앱 실행 receipt를 확인한다. 이전 성공을 최종 성공으로 대체하지 않는다.

최종 계측 소스의 Release Simulator 회귀는 171/171 통과, 실패·skip 0이며 strict SwiftLint는
86파일 위반 0이었다. 기존 UAFAssetProvider/ProcessSuspension 경고는 로그에 보존했다.
이 로컬 실행은 CI나 실기기 검증이 아니다.
