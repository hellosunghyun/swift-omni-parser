# 로컬 최종 리뷰와 실기기 대용량 검증

2026-10-27. 이관된 저장소의 로컬 `origin/main` 이후 10개 커밋과 후속 작업 트리를 검토했다. 원격 ref는 이번 작업에서 갱신하지 않았다. 제품 소스 변경, 테스트·자산·고지, 의존성 고정, 문서의 과거/현재 구분을 확인했다. 사용자의 지시에 따라 푸시·PR·외부 문서 업로드·파일 삭제는 하지 않았다.

## 수정과 확인

| 항목 | 판단과 조치 | 검증 |
| --- | --- | --- |
| CSV 빈 인용 필드 | `""`가 마지막 필드일 때 실제 셀이 누락됐다. 빈 입력과 빈 인용 필드를 구분하도록 상태를 보존 | 단독 빈 인용 필드·개행 종료·후행 쉼표의 셀 수/열 주소 검사 |
| HTML/Markdown 그림 순서 경고 | 문서 위치가 없었다. 형식 part를 포함해 출처를 식별하게 수정 | 원격 그림을 건너뛰어도 본문·위치가 있는 경고 보존. 다운로드하지 않음 |
| PDF 반복 그림 | 같은 비트맵을 두 위치에 그렸을 때 원래 스캐너가 배치 인덱스로 ID를 구분했다. 제품 수정 불필요 | 서로 다른 위치·고유 ID 두 개와 fullText 일관성 검사 추가 |
| 높은 우선순위 병렬 OCR | 결과 보존을 확인하되 QoS 경고 해소와 구분 | userInitiated 요청의 3개 이미지, 동시 문서 2개, 같은 인식 결과·입력 순서·기본 PNG 미보관 검사 |
| README/API | 실제 처리 경로에 맞게 복원 범위를 명시 | Markdown 제한, RTF 래스터 그림, PDF 표시 영역 래스터와 원본 스트림의 차이, Office/HWP 앵커·조판 제약 대조 |

새 의존성·제품·모듈·폴더 구조·공개 API·OS/언어 설정 변경은 없다. 계측 API를 제품에 다시 넣지 않았다. RTF 마커 제거와 binary 길이 제한, XML 내부 엔티티 중단, Office OCR 실패 시 PNG 보존은 기존 후속 테스트와 함께 재검증했다. 실패 정답을 바꾸거나 기능 테스트를 skip하지 않았다.

## 최종 기능·빌드·린트

| 검사 | 결과 |
| --- | --- |
| iPhone 17 / iOS 27.2 (24B119), Debug 호스트 | **32/32 PASS**, skip 0, 테스트 본문 7.912초 |
| iPhone 17 Simulator / iOS 27.0 | **32/32 PASS**, skip 0, 테스트 본문 24.422초 |
| generic iOS Simulator / arm64·x86_64 | **BUILD SUCCEEDED** |
| SwiftLint 0.65.1 / 기존 규칙 strict | 53파일·위반 0건, exit 0 |
| Swift·테스트 코드/README/일반 문서 공백 검사 | PASS |
| 전체 `git diff origin/main --check` | 원본 샘플·라이선스·패치 문맥 10파일의 공백 진단 111건 유지 |

전체 diff의 공백 진단은 외부 원문/기존 해시를 보존한 fixture 7파일과 공백 한 칸도 문법인 패치 문맥 3파일에서 나왔다. 자산·라이선스를 정규화하거나 해시를 바꿔 없애지 않았다. `review-all-whitespace.log`에 보존했다. 코드·테스트 Swift·README·일반 Markdown 문서를 선택한 `git diff origin/main --check -- Sources Package.swift README.md 'Documentation/*.md' Tests/OmniParserTests/*.swift`는 통과했다. 전체 diff 공백 검사를 통과했다고 표시하지 않는다.

실기기는 저장소 밖 `DeviceHost`에 같은 테스트를 연결했다. 리소스 Bundle 어댑터와 대용량 계측용 테스트 1개는 호스트 전용이다. 기능 검증에서는 호스트 전용 계측 테스트만 선택에서 제외해 제품의 32개 테스트가 모두 실행되게 했다. 계측 테스트는 별도 실행에서 검사한다. 실기기 팀/서명은 명령행에만 적용하며 저장소에 반영하지 않았다.

## QoS 경고 조사

경고는 userInitiated 스레드가 Default 작업을 기다린다는 Thread Performance Checker 진단이다. 이전 실행은 `VNSequenceRequestHandler.perform` 호출 위치를 가리켰고 최신 결과는 corpus 테스트의 호출 위치를 표시한다. 앱의 풀 잠금은 유휴 세션을 대여·반환할 때만 잡으며, 대여한 한 세션을 동시에 두 호출에서 쓰지 않는다. 세션의 Mutex 안에서 Vision 동기 호출을 하지만, 다른 세션은 별도로 실행한다. 이 코드만으로 Default 스레드를 기다리는 내부 원인까지 확정할 수는 없다.

Apple SDK의 `VNRequest.h`에 있는 자원 절약 힌트 `preferBackgroundProcessing = true`를 실제로 시험했다. 한영·accurate 설정과 결과 해시는 유지됐으나 corpus의 QoS 경고가 계속됐고 확실한 시간·메모리 이득도 확인하지 못했다. 따라서 **후보를 되돌리고 기존 OCR 경로를 유지**했다. 후보 실행의 메모리는 전체 corpus를 먼저 실행한 캐시와 발열의 영향을 받아 기준값과 직접 비교하지 않는다. 최종 소스에는 힌트나 경고 억제 설정을 남기지 않았다.

Instruments Time Profiler는 이름/PID attach에서 대상 탐색에 실패했고, 전체 프로세스 기록도 약 1.14초 뒤 device disconnected로 종료됐다. 유효한 OCR 호출 스택·대기 시간 분석을 얻지 못했으므로 프레임워크 내부 원인이나 경고 해결을 주장하지 않는다. 기존 동기 OCR 경계를 비동기로 바꾸는 구조 변경, 호출자 스레드의 QoS 강제 하향, CPU 전용 강제 사용은 적용하지 않았다.

## 대용량 입력과 측정 방법

외부 다운로드 없이 직접 만든 A4 스캔 PDF 두 개를 썼다. 원본은 200dpi 상당의 1654×2339 회색조 래스터다. 약한 스캔 노이즈, 한영 제목, 28줄의 본문, 수치 줄을 페이지별 독립 JPEG로 삽입했다. 텍스트 레이어가 없고 페이지 수가 60/20인지 PDFKit으로 확인했다. **실제 외부 기관 문서가 아닌 자체 생성 스캔 샘플**이며 복잡한 실제 표·손글씨·심한 기울기 정확도를 대표하지 않는다. PDF 표는 일반·스캔·혼합 회귀 샘플의 별도 검사와 구분한다.

| 자산 | 바이트 | SHA-256 |
| --- | --- | --- |
| 한영 스캔 60페이지 | 57,333,902 | `728467c39f23adc718e1bcfe938f11e4c647b43949625c20bde2820d29a293d1` |
| 한영 스캔 20페이지 | 19,109,969 | `dee425ae5c0a82f5a863dd6514156ccb0e8fc2fcd42433e30e393409107a433f` |

혼합 배치는 위 두 PDF, 기존 XLS·DOCX·RTF·PNG 각 1개와 식별 불가 입력 1개, 총 7개다. 기본 PDF 동시 페이지·256MiB 추정 작업 예산은 그대로 두고 문서 동시성만 1/2로 비교했다. 이미지 추출/OCR 옵션 외에 해상도·정답·자원 한도를 바꿔 속도를 맞추지 않았다.

- `systemUptime`으로 파싱 API 호출의 시작부터 반환까지 측정했다. 자산 생성·검증·해시 계산은 시간에서 제외한다.
- 같은 프로세스의 `task_info(TASK_VM_INFO).phys_footprint`를 utility 타이머로 20ms마다 읽었다. 값은 **샘플링한 프로세스 전체 물리 footprint 최대값**이며 OS가 기록한 절대 최고치나 파서 단독 할당량이 아니다. 순간 피크를 놓칠 수 있다.
- 각 조건은 같은 순서로 한 번씩 실행했다. 시작/종료 footprint와 thermalState를 원시 JSON에 남겼다. 다른 앱·캐시·발열·계측의 영향을 통제한 통계 실험이나 Release 성능 보증은 아니다.
- 최종 반복은 별도 테스트 프로세스에서 최대 120초 발열 완화를 기다리도록 했다. 기기의 온도가 내려가지 않으면 실제 상태를 기록한 채 실행한다. 대기 시간은 파싱 시간에서 제외한다.
- 모든 스캔 페이지에 OCR 블록이 있고 한영 텍스트가 있으며, 페이지별 `PAGE NNN` 마커가 정확히 한 번 나오는지 검사했다. 전체 텍스트/블록·순서 일관성, 결과 이미지, 개별 실패의 원래 인덱스 보존도 검사했다.
- 결과 해시는 본문·블록 종류·읽기 순서·위치·경고 코드/위치·그림 PNG를 비교한다. OCR 신뢰도 전체와 문서 원문 정답의 완전 일치 평가는 아니다. 자체 샘플의 페이지 마커·한영 인식 조건은 별도 정답 검사다.

## 대용량 실제 측정 결과

| 조건 | 기준 시간 | 최종 반복 시간 | 기준 최대 footprint | 최종 최대 footprint |
| --- | --- | --- | --- | --- |
| 60페이지 / OCR만 | 32.354초 | 29.450초 | 376.6MiB | 365.8MiB |
| 60페이지 / PNG+OCR | 38.149초 | 36.559초 | 408.0MiB | 384.6MiB |
| 혼합 7개 / 문서 동시성 1 | 52.837초 | 52.608초 | 366.3MiB | 359.3MiB |
| 혼합 7개 / 문서 동시성 2 | 52.856초 | 55.183초 | 363.1MiB | 358.3MiB |

네 조건 모두 결과 해시·블록 수·그림 수/바이트·경고 수가 기준과 일치했다. 단일 OCR은 1,800블록/그림 0개, PNG+OCR은 1,860블록/그림 60개·68,238,023바이트다. 혼합 배치는 2,495블록/그림 84개·91,049,460바이트와 마지막 입력의 개별 unsupportedFormat 결과를 보존했다. 혼합 문서의 구형 Office 그림 순서 경고도 유지했다. 스캔 PDF에는 추출/OCR 실패 경고가 없었다.

최종 OCR·PDF 코드는 기준과 같다. 후보 힌트는 되돌렸으며 이 시간·메모리 차이를 코드 최적화 효과로 해석하지 않는다. 기준 실행의 thermalState는 순서대로 0→0, 0→1, 1→1, 1→1이었다. 최종 반복은 아래 원시 상태처럼 발열 조건도 다르므로 통계적 개선율을 주장할 수 없다.

- 60페이지 / OCR만: thermalState 1→1, 시작 92.3MiB, 반환 후 199.6MiB.
- 60페이지 / PNG+OCR: thermalState 1→1, 시작 199.6MiB, 반환 후 212.7MiB.
- 혼합 7개 / 문서 동시성 1: thermalState 1→2, 시작 212.7MiB, 반환 후 168.2MiB.
- 혼합 7개 / 문서 동시성 2: thermalState 2→2, 시작 168.2MiB, 반환 후 214.0MiB.

thermalState 0/1/2는 nominal/fair/serious다. 최종 실행은 120초 완화 대기 후에도 첫 측정이 fair에서 시작했다. 반복된 OCR과 단말 환경의 영향이 있어 Release의 보편적 수치로 사용하지 않는다.

문서 동시성을 2로 바꿔도 공용 PDF 페이지 슬롯·메모리 예산은 그대로다. 따라서 여러 문서를 열었다고 전체 OCR 병렬 작업 수가 두 배가 되지 않는다. 반환 PNG 약 65.1MiB(단일)·86.8MiB(혼합), 읽은 PDF 데이터, PDFKit/Vision의 모델·중간 버퍼·할당기 보유분이 메모리에 더해진다. 이번 결과에서도 PNG를 끄면 보관 결과 크기는 줄지만 OCR 작업 자체의 최대 footprint는 남는다. 프로파일이 유효하지 않아 각 내부 버퍼의 기여량을 정확한 할당 바이트로 분해하지는 못했다.

4조건을 합쳐 한 번에 280개 스캔 페이지를 검사했다. 기준·최종 계측 XCTest는 각각 1/1 PASS이며 모든 페이지의 마커·한영 인식·순서/중복 검사도 통과했다. 최종 결과 JSON과 비교 검사는 로컬 `benchmark-comparison.json`에 보존했다.


## 재현과 로컬 증거

검증 루트는 `$HOME/Developer/Codex/OmniParserVerification/2026-10-27`이다. 최종 하네스 SHA-256은 `425127fe8b49c704baab1abf573e970791dba327c57b16311b186aca3b2b9994`다. 성능 하네스 `benchmark-harness.swift`와 생성 PDF는 저장소 밖 호스트/기기 Documents에 보존했다. 공개 제품·회귀 fixture에 약 76MB의 성능 샘플이나 측정 코드를 추가하지 않았다. 공개 저장소만으로 해당 성능 하네스가 자동 생성되는 것은 아니다.

```bash
# 패키지 루트, 기존 캐시로 Simulator 전체 테스트
xcodebuild test -scheme OmniParser \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipMacroValidation -parallel-testing-enabled NO -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build -scheme OmniParser \
  -destination 'generic/platform=iOS Simulator' -skipMacroValidation CODE_SIGNING_ALLOWED=NO
swiftlint lint --strict

# 외부 DeviceHost에서 실기기: 팀은 본인의 유효한 값으로 명령행에만 지정
xcodebuild test -project OmniParserVerification.xcodeproj -scheme VerificationHost \
  -destination 'platform=iOS,id=00008150-001D58E23C45401C' \
  -skipMacroValidation -parallel-testing-enabled NO -collect-test-diagnostics never \
  -skip-testing:OmniParserTests/ResourceAndCancellationTests/testDeviceLargeScanAndMixedBatchBenchmark \
  DEVELOPMENT_TEAM="$OMNI_DEVELOPMENT_TEAM" CODE_SIGN_STYLE=Automatic
```

실제 실행에는 이관된 캐시를 사용하도록 `-clonedSourcePackagesDirPath`, `-disableAutomaticPackageResolution`, `-skipPackageUpdates`, `-onlyUsePackageVersionsFromResolvedFile`을 지정했다. 생성물 경로는 로그에 보존했다. 대용량 검증은 같은 호스트에서 위 skip 옵션 대신 해당 테스트 하나를 `-only-testing`으로 선택했다. 기기 앱과 팀이 다른 예전 앱은 보존했다.

| 증거 | 내용 |
| --- | --- |
| `review-final-physical.log/.xcresult` | 제품 기능 32개 실기기 결과 |
| `review-final-simulator.log/.xcresult` | 제품 기능 32개 Simulator 결과 |
| `review-final-build.log`, `review-final-lint.log` | 최종 일반 빌드·strict lint |
| `benchmark-baseline.log/.xcresult` | 기준 대용량 4조건 |
| `review-candidate-physical.log/.xcresult` | 미채택 자원 절약 힌트 후보, 기능 30개 + 계측 1개 |
| `benchmark-final.log/.xcresult` | 최종 코드의 대용량 4조건 반복 |
| `qos-baseline*-trace.log`, `qos-baseline-all.trace` | Instruments 실패·짧게 중단된 기록. 유효한 프로파일로 사용하지 않음 |

## 남은 제약

- QoS 경고의 프레임워크 내부 대기 원인은 미확정이며 경고는 남는다. 기능 검증 통과를 경고 해소로 표시하지 않는다.
- 스캔 속 표의 셀 복원, 모든 RTF 벡터 그림·페이지 조판, CommonMark 전체 방언과 HTML CSS 조판, 백엔드가 주지 않는 Office 위치는 지원 완료로 표시하지 않는다.
- PDF 작업 예산은 프로세스 전체의 강제 메모리 상한이 아니다. 반환 PNG·PDFKit/Vision/가속기 캐시가 별도로 남는다. native ZIP의 모든 실제 해제 경로와 공격 조합의 강제 상한을 입증한 것은 아니다.
- 원시 샘플·LICENSE 원문은 보존했다. 자체 코드는 MIT이고 외부 라이선스 조건은 그대로다. 네이티브 전이 고지/재현 빌드 전체 감사, 자동 CI, 배포용 앱의 안정성 인증은 별도 남은 작업이다.
