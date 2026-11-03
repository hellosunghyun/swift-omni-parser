# PDF OCR 남는 작업 슬롯 활용과 메모리 재평가

## 결정

iPhone 17을 대상으로 메모리 증가를 허용하는 절충을 재평가한 뒤, 기존 작업 풀의 남는 슬롯에서만 이미지 OCR을 병렬화하는 변경을 채택한다. 앱의 원격 parser revision은 `af1293b74a990f1b164df8ffa79851de79e35fbc` 그대로 두며, 이 로컬 변경은 별도 통합 제안이다. push나 PR은 하지 않았다.

기본 256MiB PDF 작업 예약, 최대 동시 페이지 설정, 자동 한영 OCR, 원본 해상도와 전체 페이지/그림 인식 경로를 유지한다. FIFO 대기자를 추월하지 않고 기존 활성 페이지가 있을 때만 예산 안에서 추가 예약한다. 페이지/추가 작업을 합친 활성 슬롯은 설정값과 3 중 작은 값으로 제한한다. 결과는 완료 순서와 관계없이 원래 그림 순서로 합친다. 같은 bounds의 성공 결과 재사용과 빈 결과/오류 뒤 재시도, 이미지 placeholder·좌표·경고를 유지한다. 이미지/스캔/화학식/숫자/단위를 제외하거나 문자열을 보정해 속도를 숨기지 않는다.

## 1차 판정과 재평가

`PDF_PROFILE_2026-11-03.md`는 최초 메모리 증가를 보수적으로 본 미채택 판정이다. 원본과 실패 기록은 보존했다. 사용자가 iPhone17에서는 메모리 증가를 허용할 수 있다고 요청해, 메모리 증가 자체를 탈락 조건으로 삼지 않고 실제 파싱→R117 선정→분류 흐름을 추가 측정했다. 잠정 추가 physical 128MiB 및 프로세스 physical 1GiB 목표는 프로젝트 검증 예산이며 Apple의 권장 상한이나 기기 안전 보증이 아니다.

## 측정과 동일성

고정 SHA PDF4개, 자동 한영 OCR, 기본 옵션, Release iPhone17/iOS27.0 Simulator다. 앱은 R117 최종 `8c9c9b3cae3ac626321a55419e425638a5860f5c`의 동일한 격리 스냅샷 두 개이며 parser만 baseline/3슬롯으로 다르다. parser 외 원격20pin이 원본과 같다. 공유 앱 저장소·분류 코드·R117 코드·lockfile을 수정하지 않았다.

이전 parser-only A B B A B A 각3회(24표본)는 본문·전체 구조가 같았고 아스피린 중앙값15.424→14.586초, 완충8.499→8.031초였다. 완충 physical 표본peak 중앙값은 약58.75MiB 증가했다.

후속 전체 흐름은 버전마다 새 프로세스1개 안에서4문서×3회(12+12)를 수행했다. 문서별 파싱 API 중앙값은 다음과 같다.

| 문서 | 기준 초 | 후보 초 |
| --- | ---: | ---: |
| 아스피린 | 15.631 | 15.050 |
| 기상측기 | 2.762 | 2.493 |
| 완충용액 | 8.760 | 8.372 |
| 전도도 | 2.930 | 2.886 |

버전 순서가 A12회→B12회이고 초기 로딩과 후속 상태가 달라, 모든 차이를 인과 효과로 주장하지 않는다. 특히 이미지 OCR이 없는 기상 문서의 차이는 병렬 이미지 OCR 이득이라고 해석하지 않는다. 단계 시간 합을 앱 전체 wall time으로 부르지 않는다.

24회 모두 입력SHA/fullText/format/순서 있는 전체 blocks·bbox·표셀·OCR confidence와 원문·경고·이미지, 선정 집합·순서, 네 분류 그룹과 fallback이 같았다. 완충/전도도는 양쪽 모두 fallback=true이며 정상 모델 분류 성공을 입증하지 않는다.

## 메모리

- 25ms 간격으로 관측한 단계 physical 최고값 전체 표본 최대: 기준568,282,616B, 후보575,622,648B(약542/549MiB). 단계별 peak를 합하지 않았다.
- 같은 관측의 RSS 전체 최대: 기준1,005,797,376B, 후보993,804,288B. RSS를 dirty나 iOS 앱 한도로 해석하지 않는다.
- 문서별 파싱 physical 표본peak 중앙값 증가 최대는 완충액 약14.2MB(약13.6MiB)였다. 전체 흐름 종료2초 후 current physical 중앙값 증가는 약0.6~1.0MB였다. 초기 모델 로딩, XCTest 첨부 유지, 3회 반복의 한계가 있어 누수 부재를 증명하지 않는다.
- 별도 결과 보유 후 dirty snapshot은 아스피린 기준182,307,912B/후보182,897,736B, 완충 기준210,160,880B/후보210,832,576B였다. 이는 특정 시점 값이며 실행 중 dirty peak가 아니다. 완충은 같은 프로세스에서 앞선 문서와 모델 예열이 남은 상태다.
- OS 생애 누적 RSS/physical peak는 원시 자료에 별도로 보존했다. sampled maximum과 혼합하지 않는다. 파서 전용 수치와 전체 흐름 수치는 시작 상태가 달라 직접 같은 값으로 비교하지 않는다.

메모리 비용은 이 워크로드에서 수용 가능한 범위로 판단했다. Simulator는 실제 기기의 메모리 한도·압박·jetsam을 재현하지 않고, XCTest PID에는 별도 Vision/FM 서비스나 앱 UI 프로세스의 모든 비용이 포함되지 않는다. 실제 iPhone17 안전성과 성능은 미검증이다.

## 최종 소스 검증

추가 lint 예외를 제거하기 위해 측정 후보의 병합 코드를 private helper/상태로만 정리했다. 예약·인식·병합 순서를 바꾸지 않았다. 전체 흐름 메모리 실측은 정리 전 source이며 두 소스의 diff와 SHA를 연결해 보존했다.

- 최종 Release Simulator 183/183, 실패·skip·expected failure0: 원본171 + 신규 동시성8 + QA 전용 실제PDF4. dirty 대기형 QA4만 이 회귀 실행에서 제외했다.
- 신규8개는 입력 순서, 추가 예약, 중복 영역의 성공/빈 결과/오류 재시도, 경고 위치, 부모/자식 취소 시 슬롯 회수, 예산 부족 시 순차 처리와 FIFO를 확인한다.
- 최종4PDF 입력SHA와 본문·전체구조·좌표·경고·이미지는 기준과 같다. 이 회귀의 단일 메모리 표본은 성능 반복 증거가 아니다.
- 최종 소스 연결 앱 Release live4/4: 진행 순서, 취소 후 복구, 실제 PDF 결과 저장/복원/재개 시 parser 호출1회 확인. 선정·분류는 해당 테스트에서 통제했다. Vision 요청 내부 즉시 취소나 실제 OS background scheduling의 증거는 아니다.
- 전체 흐름 취소/정상 복구24회도 통과했다. extracting 경계 취소와 실제 OCR 내부 취소를 구분한다.
- 제품 Swift88파일 strict SwiftLint0건. QA 벤치마크와 원본PDF는 제품 커밋에 포함하지 않았다.

10분/600초·85% 인산·전기/기상 단위의 기존 downstream4문서 검증과 본문/구조 동일성 근거를 보존했다. 용어 필터나 타이머 수정은 없다. 현재 UI 앱 전체를 최종 parser와 다시 빌드한 증거, CI, 실기기 검증은 없으며, 앱 경계 증거는 LabcordiOSTests Release compile/live4다.

## 자료

QA 루트 `/Users/hellosunghyun/Documents/Codex/2026-11-03/labcord-parser-optimization-qa`의 `continued-analysis/pipeline-memory-source-8c9c9b3`에 고정 소스/manifest/lock/명령/원로그/전체 흐름·dirty 결과를 보존했다. `offline-analysis/results-validated/analysis.json`, `results-validated.sha256`, `offline-analysis/dirty-summary.*`가 후속 근거다. `continued-analysis/final-regression-comparison.json`, `final-regression.log`, `final-live.log`, `final-candidate-changes.patch`가 최종 정리 소스와 검증의 연결 근거다. 초기 실패/경고 로그도 삭제하지 않았다.
