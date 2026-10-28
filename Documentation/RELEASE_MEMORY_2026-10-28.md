# Release 배치·입력 메모리와 QoS 검증

2026-10-28. 실기기 없이 Mac mini M4·16GiB, Xcode 27.1, iPhone 17 / iOS 27.0 Simulator에서 확인했다. Swift 언어 모드 5, `-O`·WMO·테스트 활성화 설정을 실제 컴파일 로그로 대조했다.

기존 URL 스냅샷 Reader의 대용량 메모리 절감은 Release에서도 관측했다. 작은 배치의 추가 최적화 후보 7개는 속도·추출 결과·메모리 조건을 함께 충족하지 못해 적용하지 않았다. 별도로 발견한 동기 파일 조정의 QoS 경고는 `f41da5d`에서 수정했다. 공개 API·의존성·바이너리·OCR 설정·동시성 옵션은 유지한다.

## 같은 입력의 Release 비교

시간은 파싱 구간 중앙값, 메모리는 각 조건에서 관측한 최대 표본이다. `task_info(TASK_VM_INFO)`의 footprint와 RSS를 20ms마다 함께 읽었으며 두 최대값의 발생 시점은 다를 수 있다. MiB는 1,048,576바이트다. 자산 생성·예열·빌드·해시 대조는 파싱 시간에서 제외했다.

`64d3a66`은 스냅샷 Reader 전, `19952e1`은 Reader 적용 후, `f41da5d`는 I/O 실행기까지 적용한 코드다. 앞의 두 버전은 A→B→B→A 순서로 비교했다. 최종 I/O 수정본은 이후 별도 시점에 측정했으므로 그 차이를 수정만의 인과 효과로 해석하지 않는다.

| 조건 | Reader 전 64d | Reader 후 19952 | 최종 I/O 수정본 |
| --- | ---: | ---: | ---: |
| 작은 PDF·JPEG·DOCX 3문서 표본 수 | 10 | 10 | 5 |
| 작은 배치 시간 | 1.380초 | 1.391초 | 1.205초 |
| 작은 배치 최대 footprint | 214.94MiB | 208.63MiB | 197.47MiB |
| 작은 배치 최대 RSS | 532.83MiB | 532.47MiB | 534.33MiB |
| 80페이지 혼합 배치 표본 수 | 6 | 6 | 3 |
| 대용량 배치 시간 | 62.222초 | 62.428초 | 59.862초 |
| 대용량 최대 footprint | 564.27MiB | 503.71MiB | 512.35MiB |
| 대용량 최대 RSS | 945.30MiB | 936.73MiB | 844.58MiB |

대용량은 자체 생성한 200dpi 한영 스캔 PDF 60·20페이지, XLS·DOCX·RTF·PNG·손상 입력의 7문서다. OCR·PNG 추출을 켜고 동시 문서 2개와 기존 PDF 작업 설정을 유지했다. 모든 비교에서 2,495블록·84이미지·경고 1개·PNG 91,049,403바이트와 마지막 입력의 개별 실패를 보존했다. semantic SHA와 PNG 바이트 해시도 같았다. semantic은 텍스트·블록·읽기 순서·위치·신뢰도·원래 OCR 텍스트·경고·그림 메타데이터·canonical 픽셀을 포함한다.

Reader의 대용량 ABBA 비교는 최대 footprint −10.73%, 시간 +0.33%였다. 최종 I/O 수정 후 대용량 footprint는 그보다 1.72% 높게 관측됐다. RSS와 footprint, 실행 중 최고치와 결과 해제 후 메모리를 구분하며 모든 지표가 함께 줄었다고 표현하지 않는다.

작은 배치만 같은 프로젝트·패키지 경로에서 `19952e1`→`f41da5d`→`f41da5d`→`19952e1`로 추가 확인했다. 각 실행은 예열 1회와 측정 5회이며, 짧은 peak를 더 자주 읽도록 양쪽 모두 5ms 샘플러를 사용했다. 앞의 20ms 자료와 합산하지 않았다.

| 작은 배치 교차 확인·각 10표본 | 기준 19952 | 최종 f41da5d |
| --- | ---: | ---: |
| 시간 중앙값 | 1.2303초 | 1.1405초 |
| footprint peak 중앙값 | 194.03MiB | 199.46MiB |
| 최대 footprint | 204.58MiB | 203.60MiB |
| 최대 RSS | 531.69MiB | 541.31MiB |

20표본의 semantic과 69블록·경고 0개가 같고, 모든 실행의 runtimeWarnings는 비어 있었다. 최대 footprint 차이는 −0.48%지만 peak 중앙값은 +2.80%, 최대 RSS는 +1.81%였다. 따라서 **작은 배치의 추가 메모리 절감은 확인하지 못했다.** 이번 교차 확인에서 시간 중앙값은 −7.30%였으나, 공유 Mac의 한 체인이므로 모든 환경의 속도 향상으로 일반화하지 않는다. QoS 수정과 메모리 절감 판단을 구분한다.

## URL과 Data 입력 비용

사용자가 승인한 자체 생성 12페이지 연구 보고서다. 실제 출판 논문은 사용하지 않았다. 일반 자료는 2,374,173바이트, 그림 많은 자료는 25,187,698바이트다. 각 조건을 URL→Data→Data→URL로 실행해 입력 방식별 10표본, 전체 60표본을 보존했다. 기준 코드는 `19952e1`이다.

| 조건 | 준비 포함 시간 중앙값 URL / Data | 최대 footprint URL / Data | 최대 RSS URL / Data |
| --- | ---: | ---: | ---: |
| 일반 보고서·기본 옵션 | 0.02057 / 0.01520초 | 19.38 / 20.91MiB | 231.22 / 232.89MiB |
| 그림 많은 보고서·기본 옵션 | 0.02188 / 0.01763초 | 18.66 / 42.81MiB | 231.25 / 254.66MiB |
| 일반 보고서·PNG+OCR | 6.91287 / 6.95773초 | 463.71 / 469.94MiB | 820.67 / 823.55MiB |

Data는 계측을 시작한 뒤 로드하고 결과 측정까지 보유했다. URL의 파일 조정·스냅샷 준비는 파서 구간에 포함된다. 각 쌍의 원본·추출 결과 SHA는 같았다. 기본 옵션은 이미지 추출·OCR이 꺼져 있으므로 그림을 읽는 속도의 비교가 아니다. 작은 파일의 수십 ms 차이를 모든 문서의 속도 우열로 일반화하지 않는다. 이미 파일이 있으면 URL로 큰 힙 복사를 줄일 수 있으며, 이미 보유한 Data를 다시 파일로 쓸 필요는 없다.

최종 I/O 수정본으로 같은 25MB URL 입력을 5회 재확인한 값은 0.01887초, 최대 footprint 18.36MiB·RSS 224.89MiB였다. 결과 SHA는 기존과 같았다.

## 작은 배치 후보의 판단

기준과 후보를 포함해 14회·70표본과 별도 숫자 호출 진단을 보존했다. 후보 통과와 기준 결과와의 동등성은 별도다. XCTest exit 0이어도 semantic이 달라지면 채택하지 않았다.

| 후보 | 관측과 판단 |
| --- | --- |
| VN sequence handler·전용 큐 | 최대 footprint 199.46→166.58MiB지만 시간 1.326→1.809초. HWP/HWPX 세로 한글을 확인하는 한 테스트의 assertion 2개 실패. 미채택. |
| VN image handler·전용 큐 | 시간 1.798초, 최대 footprint 181.00MiB. 같은 세로 한글 회귀 실패. 미채택. |
| 모든 OCR 입력을 BGRA로 변환 | 69→71블록·SHA 변경, 시간·메모리 증가. 미채택. 추가 블록의 정확도 향상을 검증한 결과는 아니다. |
| 불투명 8비트 RGB·1MP 이하만 BGRA | HWP 테스트는 통과했지만 69→71블록·SHA 변경. 시간 1.439초, 최대 footprint 214.53MiB로 이득도 없어 미채택. |
| 비동기 요청을 단일 자식 작업으로 분리 | 추가 ABBA 20표본에서 메모리 중앙값 차이가 일관되지 않았다. 기준 A2의 중앙값이 후보 B2보다 낮았다. 최댓값 하나만 고르지 않고 미채택. |
| 유휴 요청 캐시 제거 | 최대 footprint 199.96MiB로 감소 근거 부족. 미채택. |
| 첫 OCR만 독점하는 준비 장벽 | 최대 footprint 142.89MiB지만 시간 1.900초로 약 43% 증가. 초기 실제 OCR 병렬성이 줄어드는 절충이어서 미채택. |

숫자 보완 OCR은 작은 배치의 여섯 호출에서 대상 0개·cutoff 요청 0회였다. 이 배치의 원인 후보로 더 진행하지 않았다. 앞선 [진단](BATCH_MEMORY_2026-10-28.md)은 높은 메모리 시점에 CoreML→Espresso 모델 준비·CPU blob의 97.16MiB 스택 그룹을 확인했다. 이것이 제거 가능한 메모리량이나 동기→비동기 전환 증가량 전체를 뜻하지 않는다. 공개 요청 재사용으로 내부 모델 공유를 보장할 수 없으며, 이번 실험에서 속도와 결과를 보존한 작은 배치의 확실한 추가 절감은 확보하지 못했다.

## 발견해 수정한 QoS 대기

수정 전 Release 56개 테스트는 통과했지만 xcresult에 런타임 경고가 1개 있었다. 사용자 우선순위 OCR 배치 테스트의 `DocumentInputReader.swift:19`, 동기 `NSFileCoordinator.coordinate`가 높은 QoS에서 Default QoS 작업을 기다리는 지점이었다. 저장된 27개 스택 프레임은 주소뿐이어서 내부 서비스 큐의 이름까지 확정하지 않았다.

URL 읽기를 구조화된 자식 작업으로 만들고 Default QoS의 전용 concurrent 실행기에서 수행한다. 호출자는 비동기로 기다린다. 기존 동기 읽기 본문·FD·크기 제한·보호 정책·COW·cleanup helper는 유지했다. Task 취소 컨텍스트도 보존하며 상위 parse는 자식 읽기가 끝날 때까지 security scope를 유지한다. `.data`·CGImage 입력에 별도 I/O 작업을 만들지 않는다. 파일 조정 내부의 즉시 강제 취소는 보장하지 않는다.

후보 파일 입력·사용자 우선순위 8개 테스트와 최종 제품의 전체 57개 Release 테스트에서 런타임 경고는 0건이었다. 읽기 전 취소의 원본·임시 항목 보존 회귀를 추가했다. 최종 성능 재확인의 세 테스트도 경고 0건·결과 동등성을 확인했다.

## 최종 검사와 시간

| 검사 | 결과 | 명령 전체 경과 |
| --- | --- | ---: |
| 최종 제품 Release XCTest | 57통과·실패/skip 0, 본문 47.365초, runtimeWarnings 0 | 111.84초 |
| CI 기준 generic Simulator build | arm64·x86_64 통과 | 6.48초 |
| SwiftLint 0.65.1 strict | 55파일·위반 0 | 0.35초 |
| Reader 전후 작은 배치 ABBA | 4실행·20표본·동일 semantic | 약 335초 |
| URL/Data 정순·역순 | 12실행·60표본·각 쌍 결과 동일 | 약 441초 |
| Reader 전후 80페이지 ABBA | 4실행·12표본·동일 semantic/PNG | 약 1,056초 |
| 최종 I/O 수정 후 성능 재확인 | 작은 배치 5·URL 5·대용량 3표본 | 345.36초 |
| 최종 작은 배치 5ms 교차 확인 | 4실행·20표본·결과 동일, runtimeWarnings 0 | 135.92초 |

벽시계에는 빌드·설치·예열·XCTest·결과 검증이 포함된다. `전체−본문`을 순수 빌드 시간으로 계산하지 않았다. 처음 최종 성능 호스트의 코어가 incremental로 컴파일된 중간 13표본은 보존하고 위 비교에서 제외했다. 이후 코어·테스트 모두 동일한 `-O`·Swift 5·WMO로 다시 실행한 결과만 사용했다.

```bash
xcodebuild test -configuration Release -scheme OmniParser -jobs 2 \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -skipMacroValidation -packageAuthorizationProvider netrc \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath /새로운/OmniParser-Release.xcresult \
  CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES
xcrun xcresulttool get test-results summary --path /새로운/OmniParser-Release.xcresult --compact
xcodebuild build -scheme OmniParser -jobs 2 \
  -destination 'generic/platform=iOS Simulator' \
  -skipMacroValidation -packageAuthorizationProvider netrc CODE_SIGNING_ALLOWED=NO
swiftlint lint --strict
```

실제 명령에는 고정 캐시 경로·업데이트 금지·고유 결과 경로를 지정했다. 코드와 생성 샘플·원시 로그는 외부로 전송하지 않았다. 파서에 측정 API·새 의존성·생성 바이너리는 추가하지 않았다.

## 근거와 제약

로컬 기준 경로는 `~/Developer/Codex/OmniParserVerification/2026-10-28/`다. 원시 본문 대신 해시·수치로 대조했으며 모든 실패·미채택·비교 불가 기록을 보존했다.

- `SmallBatchMemory/`: `commands.json`, `ReleaseSmallResults.md`, `URLDataCounterbalancedResults.json`, `ReleasePNG80Results.json`, `CANDIDATE_RESULTS.json`, `ChildGroupComparison/confirmation-result.json`.
- `SmallBatchMemory/QoSReadInvestigation/`: 최초 경고의 정확한 위치·시간·원시 스택과 기본 QoS 실행기 진단.
- `QoSReadFix/`: 후보 8개·제품 57개 xcresult, summary·실행 명령·build·lint와 원본 helper 보존 증거.
- `SmallBatchMemory/QoSReadFix/WMOComparableRun/`: 최종 source·kit·host·97개 자산·60/20페이지 원본 해시 대조, 컴파일 필드, 전체 성능 표본·환경·wall 기록.
- `SmallBatchMemory/PairedQoSSmall/`: 5ms 교차 확인의 `PairedResults.json`, `SourceAndCompilerProof.json`, `RunSnapshots/`, `commands.json`, `stage-wall.json`.

80페이지 ABBA와 최종 성능 재확인 중 다른 Simulator 재기동은 관측되지 않았지만 공유 Mac의 swap 보유량은 약 8GiB였다. 앞선 URL/Data 정순 단계의 다른 Simulator 관측·종료 기록도 제외하지 않았다. Simulator 한 대라는 사실이 시스템 무부하를 뜻하지 않는다. 실기기·발열·모든 입력의 최대 메모리나 속도를 보장하는 결과가 아니며, 짧은 순간의 최고치는 샘플링에서 놓칠 수 있다.
