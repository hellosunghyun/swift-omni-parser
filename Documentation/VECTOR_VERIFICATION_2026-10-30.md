# WMF·EMF 온디바이스 변환 검증

2026-10-30. `wmf-emf-renderer 0.2.1` 소스 자산 추가를 승인받아 RTF pict·OLE native/미리보기 경로에 연결했다. 최초에는 사용자 요청에 따라 Simulator만 검증했다. 이후 같은 제품 소스로 [iPhone 17 실기기 후속 검증](DEVICE_VERIFICATION_2026-10-30.md)을 수행했으며, 두 환경의 수치와 제약을 구분한다.

## 구현과 범위

- 로컬 JavaScriptCore에서 WMF·EMF를 SVG로 변환하고 정적 SVG를 detached WKWebView의 PDF로 만든 뒤 CoreGraphics PNG·기존 Vision OCR에 연결한다. 앱 window/view controller에 붙이지 않는다.
- `extractImages`·`performOCR`은 독립적이며 기본값 false를 유지한다. 둘 다 꺼지면 벡터의 JS/WebKit 작업을 시작하지 않는다. 기존 공개 API·iOS 27.0·Swift 언어 모드 5·tools 6.2는 유지한다.
- 원본·호환본의 한 번 처리 규칙, 취소 전파, 바깥 본문·표·정상 그림 보존, OLE 객체 경로를 유지한다. 미지원 명령은 가능한 그림을 보존하면서 `unsupportedElement` 위치 경고를 반환한다.
- 고정 라이브러리의 WMF CP949 TextOut 누락과 홀수 바이트 WORD 패딩에 의한 좌표 오류를 실제 재현 후 보완했다. 홀수 ASCII/DBCS 원본은 x=10240/y=15360으로 잘못 읽혔고 수정 후 x=40/y=60을 확인했다.
- 독립 WMF·EMF·SVG 파일의 문서 형식 지원, 모든 EMF+ 명령의 완전한 재현은 이번 구현에 포함하지 않는다. 소스 파서의 미지원 drawing stub·unknown record는 감지하지만 모든 시각적 오차를 자동 검출하는 것은 아니다.

## 제한과 오프라인 정책

벡터 8 MiB·record 10,000개, 단일 JS typed-array 16 MiB·누적 64 MiB, 루프 500,000회·변환 10초, SVG 출력 16 MiB·노드 50,000개, SVG root 400만 픽셀·내장 이미지 누적 400만 픽셀과 요청 픽셀 한도 중 작은 값을 적용한다. WebKit 단계도 10초 제한·취소·단일 작업 gate를 사용한다. 연속 작업은 nonpersistent 데이터스토어를 재사용하며 마지막 작업 뒤 1초 idle이면 앱의 저장소 참조를 해제한다. 작업별 WebView는 매번 해제하고, 정리 Task의 취소 경계도 검사한다. OS 프로세스의 즉시 종료를 보장하는 API로 간주하지 않는다. 상한은 유효한 대형 문서도 제한할 수 있으며 전체 앱/OS 메모리 상한이나 모든 동기 SDK 호출의 실시간 중단을 보장하지 않는다.

SVG 허용 목록·엔티티 차단·외부 URI 차단·중복 ID/순환 참조 거부·내장 PNG/JPEG/BMP ImageIO 메타데이터 검사를 거친다. WebKit은 nonpersistent 저장소, 스크립트 비활성화, CSP와 about:blank 외 탐색 차단을 사용한다. 변환 로그·문서 본문은 제품 로그에 출력하지 않는다.

## 실제 검증

| 대상 | 상태 |
|---|---|
| 벡터·안전 후속 검사 | **24/24 PASS**, iPhone 17 Simulator / iOS 27.0, Release, 23.696초 |
| 전체 통합 Release 회귀 | **159/159 PASS**, 실패·skip·expected failure 0, XCTest 본문 103.264초, xcresult 런타임 경고 0 |
| strict lint | **84파일·위반 0** |
| generic Simulator Release 빌드 | **PASS**, arm64·x86_64 |
| 실기기 후속 실행 | **159/159 PASS**, [기록](DEVICE_VERIFICATION_2026-10-30.md). QoS 경고 1건·WebKit 별도 메모리 미관측 |

후속 검사는 생성 WMF·EMF의 실제 도형 색상·텍스트·한영 OCR·홀수 텍스트 좌표, 기존 RTF 안 WMF 호환본 2개, 옵션 4조합, RTF/OLE 그림·경고 위치, 원본/호환본 중복, 손상 후 본문 보존, 픽셀·record·byte·point 한도, 취소·재사용·배치 순서를 포함한다. 안전 검사는 스크립트·외부/파일/data-SVG 참조·DTD/엔티티·CSS URL·중복/순환 ID·거대 압축 이미지 메타데이터·내장 이미지 누적 픽셀·unknown/stub의 부분 결과를 확인한다.

최초 통합 probe의 SVG validator 컴파일 범위 오류는 수정했다. 이후 첫 실행의 부분 실패 검사 1건은 생성 RTF의 제어어 경계를 바로잡았고, WMF 한글은 실제 라이브러리 디코딩 누락을 보완했다. WMF·EMF 렌더 PNG에서 `VECTOR 한글 TEST`를 직접 확인했다. 자동 언어 OCR이 영문을 선택한 결과와 분리해 한영 OCR 회귀는 기존 `.koreanAndEnglish` 옵션으로 실행하며 기본 언어 정책을 바꾸지 않았다.

```bash
xcodebuild test -scheme OmniParser -configuration Release \
  -destination 'platform=iOS Simulator,name=OmniParser-Vector-Memory' \
  -skipMacroValidation -parallel-testing-enabled NO -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES
swiftlint lint --strict
```

## 메모리 측정 방법

외부 `VectorMemoryHost`에서 공개 API만 호출해 옵션 off·초회 WMF/EMF·20회 직렬·8문서 배치(동시성 2)·초기 취소·진행 중 배치 취소·취소 후 20회 재시도·5초 idle을 측정한다. 자체 생성 문서만 사용하고 OCR을 꺼 벡터 변환 비용을 분리한다. 원본 블록 일관성·배치 순서·PNG SHA-256도 함께 검사한다.

앱의 `task_vm_info.phys_footprint`는 10ms 표본·OS 누적 peak를 기록한다. WebKit은 별도 프로세스이므로 이 값을 전체 렌더링 메모리로 표시하지 않는다. 전용 Simulator launchd의 자식 프로세스만 host ps로 200ms 표본 추출해 WebContent/GPU/Networking RSS를 별도로 기록한다. RSS는 공유 페이지를 포함하며 phys_footprint와 합산하거나 실기기 메모리로 환산하지 않는다. 시점이 다른 peak도 단순 합산하지 않는다.

첫 측정은 하네스가 기존 parseBatch의 raw `CancellationError`를 분류하지 못해 실패한 기록이다. 제품 취소 동작을 바꾸지 않고 측정기가 기존 `.cancelled`와 `CancellationError`를 구분 기록하도록 수정 후 다시 실행한다. 실행 전후 소스·리소스 SHA-256 manifest가 같아야 유효한 측정으로 취급한다.

## 반복 처리 전후 측정

같은 iPhone 17 / iOS 27.0 Simulator의 Release 빌드를 재부팅 후 실행한 단일 전후 쌍이다. OCR은 껐으며 측정 중 다른 XCTest를 실행하지 않았다. 서버/실기기 성능이나 일반적인 개선율로 확대하지 않는다. `source-before/after.json`의 제품 소스 manifest는 각 유효 실행에서 같았다.

| 단계 | 작업별 저장소 | 공유 저장소 + 1초 idle 해제 |
|---|---:|---:|
| 옵션 off, 2문서 | 6.60 ms | 7.47 ms |
| 초회 WMF | 1,723.92 ms | 2,280.65 ms |
| 이어지는 첫 EMF | 794.74 ms | 477.20 ms |
| 20회 직렬 | 29,255.18 ms | 9,562.48 ms |
| 8문서 배치, 동시성 2 | 15,886.58 ms | 2,961.20 ms |
| 취소 후 20회 재시도 | 21,344.37 ms | 8,653.73 ms |
| 진행 중 취소 요청→반환 | 12.61 ms | 30.17 ms |
| 앱 자체 OS peak footprint | 39.97 MiB | 34.16 MiB |
| 5초 idle 후 앱 자체 footprint | 34.80 MiB | 29.27 MiB |

두 실행 모두 초기/진행 중 취소와 후속 재사용을 통과했고, 정상 처리의 본문·PNG SHA-256·배치 순서가 전후 일치했다. 진행 중 취소는 public `extracting` 관찰과 미완료 Task 상태를 확인했으며 private WebKit 시작 시점으로 주장하지 않는다. WebKit 시작 이후 취소는 별도 `VectorLifecycleTests`에서 MainActor loadHTMLString 장벽 뒤 미완료 조건을 확인해 통과했고 다음 렌더의 성공도 검사했다. 취소 지연·초회 WMF는 이 쌍에서 줄지 않았으며 이를 개선으로 표시하지 않는다.

200ms 표본에서 20회 직렬의 WebKit Networking PID는 18개→1개, GPU PID는 5개→2개였다. WebContent는 20개→19개로 크게 줄지 않았다. WebKit 전체 RSS peak는 약 393.69→392.41 MiB로 유사하고, 직렬 단계 peak는 오히려 283.41→297.59 MiB였다. 최종 idle 직전에는 두 실행 모두 해당 WebKit 프로세스를 관찰하지 못했다. 앱 RSS idle 표본은 177.78→200.78 MiB로 증가했다. 따라서 앱 자체 footprint와 관찰된 처리 시간이 개선됐다고만 결론 내리며, 전체 OS RAM·RSS 또는 실기기 메모리 절감은 주장하지 않는다.

유효 baseline은 `vector-memory-baseline-retry.log`·`vector-processes-baseline-retry.jsonl`, 최종 후보는 `vector-memory-shared-final.log`·`vector-processes-shared-final.jsonl`이다. 제품 manifest는 각각 `c766bdb6…7db4`, `0ff2760e…3efde`다. 최초 하네스 취소 분류 실패, 이후 Simulator 설치/실행 응답 지연으로 중단한 실행, idle 취소 경계 수정 중 source manifest가 달라진 후보 실행은 위 전후 비교에서 제외했다. 응답 지연은 검증용 Simulator 3대만 종료한 뒤 서비스를 재연결해 복구했고, 실기기나 다른 앱 데이터를 변경하지 않았다.

## 라이선스와 원시 증거

MIT 원문은 저장소와 SwiftPM 배포 리소스에 함께 보존했다. 원본 npm integrity·소스 hash, 수정 JS hash와 AST 패치 재생성 명령은 [라이브러리 기록](../ThirdParty/wmf-emf-renderer/README.md)에 있다. 패치는 119개 루프·출력 노드·할당 예산·문자열 이스케이프·미지원 요소 flag·WMF 좌표 보완을 포함한다. Node/Acorn은 개발 시 재생성 도구이며 앱 런타임에 포함하지 않는다. 새 네이티브 바이너리·원격 변환 서비스는 추가하지 않았다.

제품 저장소에는 원시 로그·xcresult·임시 검증 앱을 넣지 않는다. 로컬 증거 루트는 `~/Documents/Codex/OmniParserVerification/2026-10-30/`이며 `vector-fourth.log`/xcresult(후속 24개), `vector-final-159.log`/xcresult(전체), `vector-final-lint.log`, `vector-generic-build.log`, 외부 `VectorMemoryHost/Logs/` 및 `vector-processes-*.jsonl`에서 단계별 실제 기록을 확인한다. 실제 개인 문서 본문은 로그에 넣지 않았다.

후속 [실기기 메모리·QoS 수정 검증](DEVICE_OPTIMIZATION_2026-10-30.md)은 오류 종료의 JSContext 참조 정리와 HEIC PNG 비동기 인코딩, 163개 실제 기기 회귀를 다룬다. 위 Simulator 수치와 앞선 실기기 baseline을 최종 후보 측정에 합산하지 않는다.
