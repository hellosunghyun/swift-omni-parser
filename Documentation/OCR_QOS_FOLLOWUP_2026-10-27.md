# OCR QoS 원인 조사·행 순서 보완·재현 계획

2026-10-27. 이전 [32개 테스트·대용량 측정](LOCAL_REVIEW_2026-10-27.md)의 후속 작업이다. 아래 확인 사실, 시제품 결과와 운영 변경을 구분한다. 푸시·PR·외부 문서 전송·유료 서비스 호출은 하지 않았다.

## 현재 확인 상태

| 요청 | 진행 상태 |
| --- | --- |
| QoS 경고의 원인 조사와 비동기 변경안 | 실기기 LLDB의 Vision 내부 대기 스택 확보. 새 async API 3입력 대조 완료. 운영 전환은 아래 조건 검증 전 보류 |
| 같은 발열 조건의 3회 반복 | 4조건×3회, 각 시작 전 nominal 연속 유지 검사 하네스 준비. 기기 잠금으로 실행 대기. 기존 한 번 측정을 3회 중앙값으로 재사용하지 않음 |
| 기울기·저해상도·복잡한 표 | 자체 생성·실기기 초기 측정 완료. 행 순서 문제를 찾고 보완, 새 34개 전체 테스트 Simulator PASS. 보완 후 실기기 실행 대기 |
| 재현 가능한 하네스 보존 | 저장소 밖 키트 준비·실제 Simulator 빌드/준비 경로 검증. 원문 fixture는 패키지에서 복사하며 생성 성능 자산·바이너리는 제품에 넣지 않음 |

실기기는 iPhone 17 / iOS 27.2다. 최초 조사와 시제품은 실행했지만 이후 잠겨 후속 실기기 테스트가 대기 중이다. 새 변경을 실기기 검증 완료나 속도 동등성 입증으로 표시하지 않는다.

## QoS: 확인된 스택과 남은 추론

Xcode 결과 번들에는 높은 우선순위 스레드가 Default 작업을 기다린다는 메시지와 테스트 호출 위치만 있었다. standalone 검증 앱에서 LLDB의 dispatch semaphore/group wait 진입점을 추적해 다음 스택을 확보했다.

```text
com.apple.root.user-initiated-qos.cooperative
  dispatch_semaphore_wait
  VisionCoreCIContextsHandler.waitAndGetAvailableContextReturnError
  VisionCoreCIContextManager.waitAndGetAvailableContextForMetalDevice
  VisionCoreImageBuffer._cropCIImage
  VNCRImageReaderDetector.createRegionOfInterestCrop
  VNRequest.performInContext
  VNSequenceRequestHandler.performRequests
  DocumentOCRSessionPool.Session.perform

com.apple.VNRecognizeTextRequestRevision3
  semaphore_wait_trap
  _dispatch_semaphore_wait_slow
  VNRequest.performInContext block

com.apple.root.user-initiated-qos.cooperative
  dispatch_group_wait
  VNDetector.runSuccessReportingBlockSynchronously
```

위는 대기 **진입 스택**이며 각 호출이 오래 대기했다는 시간 계측은 아니다. 앱은 세션을 유휴 풀에서 배타적으로 대여하고 세션 잠금을 잡은 상태로 Vision을 실행한다. 관찰한 기다림은 앱의 세션 대여 잠금 획득이 아니라 Vision/Core Image 컨텍스트·검출기 내부의 동기화 경로다. 내부 작업의 어느 producer가 Default로 실행돼 경고를 발생시켰는지까지는 이 스택만으로 확정할 수 없다. 특정 모든 semaphore 호출이 곧 경고 원인이라는 단정도 하지 않는다.

처음에는 LLDB에 UDID를 넘겨 기기 선택이 안 됐다. `lldb device list`가 표시하는 CoreDevice UUID로 선택한 뒤 실제 원격 PID에 붙여 스택을 얻었다. 이 과정의 이름/PID 탐색 실패와 진단 비용은 벤치마크에 포함하지 않는다. 스택 추적용 프로세스만 종료했으며 앱이나 자료는 삭제하지 않았다. 재현용 XCTest issue observer도 준비해 다음 실기기 실행에서 경고의 sourceCodeContext를 함께 저장하도록 했다.

운영 요청의 언어·accurate·언어 보정·가속기 설정·우선순위는 바꾸지 않았다. 앞선 `preferBackgroundProcessing` 실험은 경고가 남고 이득이 확인되지 않아 계속 미적용이다. 경고 억제, 호출자 QoS 강제 하향, CPU 전용 강제 사용은 해결책으로 적용하지 않는다.

## 비동기 OCR 변경안

공개 `parse`/`parseBatch` API는 이미 async이므로 호출 방법을 유지할 수 있다. 다음 후보를 비교한다.

| 후보 | 의도와 영향 | 판단 |
| --- | --- | --- |
| 현재 엔진 유지·동기 작업을 별도 executor로 격리 | Swift 협력 스레드의 점유를 줄이지만 Vision의 내부 우선순위 역전 해소를 보장하지 않음. PDF는 이미 별도 executor 사용 | 원인 규명 없이 경고만 없애는 용도로 적용하지 않음 |
| 기존 VN 요청+비동기 브리지 | 요청·세션 재사용과 숫자 보정을 유지하고 handler 작업 완료를 continuation으로 전달. 이미지/텍스트/Office/HWP의 내부 호출 경계를 async로 바꿔야 함 | 엔진 동등성 유지에 유리하나 변경·취소 검증 범위가 큼 |
| Swift Vision `RecognizeTextRequest.perform` | Apple의 async API로 전환. 관찰 타입·숫자 재인식·세션 수명·취소·메모리 예산을 함께 검토해야 함 | 시제품은 통과했으나 운영 전환에 충분한 증거는 아직 아님 |

직접 호출 지점은 공통 래스터 경로, HWP 그림, 구형 Office 그림, PDF 그림·전체 페이지 OCR의 5곳이다. 이들을 호출하는 RTF·HTML/Markdown·Office·HWP의 동기 루프에도 await와 수명 관리가 전파된다. UI·Reducer·공개 모델·OS/Swift 언어 모드를 바꾸는 계획은 아니다.

권장 순서는 경고 sourceCodeContext와 실제 대기 시간 확보 → 브리지와 새 async API를 외부 호스트에서 비교 → 65문서·숫자 보정·방향/TIFF/PDF·부분 실패·OCR/배치 취소·임시 파일 회귀 → 동일 조건의 실기기 시간/메모리 대조 → 검증한 경로만 운영 전환이다. 요청·세션을 사용 중에 풀에 반환하거나 await 동안 Mutex를 잡지 않으며, 취소 후에도 실제 작업/자원 정리가 끝나야 호출이 종료되도록 한다. 새 구조 적용은 별도 검토할 변경안으로 남긴다.

### async API 실기기 시제품

iOS 27.2의 `RecognizeTextRequest(.revision3)`와 기존 `VNRecognizeTextRequest`를 같은 ko-KR/en-US·accurate·자동 언어 감지·언어 보정 설정으로 비교했다. 직접 Vision 입력 비교이며 제품의 숫자 보정·페이지 파이프라인 전체 비교는 아니다.

| 기존 입력 | 관찰 수 구/신 | 텍스트 | 최대 좌표 차이 | async 호출 시간 |
| --- | --- | --- | --- | --- |
| PNG ss-features | 87/87 | 동일 | 0 | 0.252초 |
| JPEG businessplan | 71/71 | 동일 | 0 | 0.769초 |
| HEIC IMG_1034 사진 | 0/0 | 동일 | 0 | 0.549초 |

텍스트 없는 사진 HEIC는 기존 manifest의 최소 텍스트도 0이다. 초기 진단 하네스가 모든 사진에 텍스트를 요구해 실패했던 기록은 보존했고, 기존 manifest의 기대값은 바꾸지 않았다. 이 사진을 텍스트 OCR 정확도 검증의 성공 사례로 세지 않는다. 3입력의 결과 동등성만으로 전체 기능·성능·경고 해소를 주장하지 않는다.

## 어려운 스캔: 찾은 문제와 보완

외부 다운로드 없이 시스템 글꼴로 한영 문구를 그렸다. 7도 기울기, A4 72dpi 상당의 595×842 입력, 9행×4열 표 그림을 PDF에 삽입했다. 원본은 텍스트 레이어가 없는 스캔이다. PDF 메타데이터 때문에 매번 바이트 해시가 같다고 가정하지 않으며, 글꼴·문구·픽셀 크기·입력 작성 코드를 보존한다.

실기기 초기 측정의 CER는 공백을 제외하고 완성형 한글을 한 문자로 세는 Levenshtein 거리다. 인식 문자 자체의 오류뿐 아니라 읽기 순서도 포함한다.

| 입력 | 초기 오류/문자 | 초기 CER | 초기 파싱 시간 |
| --- | --- | --- | --- |
| 7도 기울기 | 5/486 | 1.03% | 0.633초 |
| 72dpi | 9/490 | 1.84% | 0.626초 |
| 표 그림 | 91/243 | 37.45% | 0.871초 |

표는 같은 행 안에서도 한글/숫자의 bbox 높이와 y가 달라 단순 y 정렬이 열을 뒤섞었다. 인식 문자·좌표를 바꾸지 않고 세로 겹침과 행의 고정 기준으로 왼쪽부터 묶는 외부 시제품에서 오류가 26/243, **10.70%**로 줄었다. 남은 문자 인식 오류까지 사라졌다는 의미는 아니다.

운영 보완은 OCR과 최종 PDF 정렬이 같은 내부 행 정렬을 사용하도록 했다. 페이지를 우선하고, 가로 위치가 달라도 세로 영역이 충분히 겹치는 같은 행만 묶는다. 행의 첫 요소를 기준으로 고정해 허용 오차를 sort 비교 함수에 넣을 때 생길 수 있는 비추이적 비교를 피한다. 표·이미지 영역은 텍스트 행의 기준으로 쓰지 않는다. 셀 구조 복원은 하지 않는다.

행/페이지/구조 블록의 회귀 검사와 자체 생성 세 샘플을 제품 XCTest에 추가했다. 표는 CER 15% 이하, 다른 두 샘플은 8% 이하와 한영 표식·그림 보존·오류 경고 없음·fullText 일관성을 검사한다. 이는 해당 생성 샘플의 회귀 기준이며 임의의 모든 스캔 정확도 보증이 아니다. 이전 fixture의 정답이나 원본 해시는 바꾸지 않았다.

## 후속 검증 상태와 재현 키트

- Simulator: **34/34 PASS**, 본문 합계 27.605초.
- 일반 Simulator 빌드 arm64·x86_64: PASS.
- SwiftLint strict: 53파일·위반 0건.
- 보완 후 실기기와 65문서 전후 해시: 잠금 해제 대기. 빌드된 전환 전 기준 앱은 별도 보존했다.
- 3회 반복: 각 시나리오 전에 동일 1페이지 warm-up 후 nominal이 연속 유지되는지 확인한다. 10분 내 조건을 만족하지 못하면 실패로 중단한다. 시작/종료 발열, 20ms footprint, 원문 없는 결과 해시를 기록한다. 빠진 회차를 이전 값이나 추정으로 채우지 않는다.

재현 키트는 로컬 검증 폴더의 `ReproducibilityKit-2026-10-27/`에 있다. Python 표준 라이브러리 runner, Xcode 호스트 템플릿, 하네스 소스와 체크섬으로 보존하며 생성 PDF·네이티브 바이너리는 포함하지 않는다. 실제 prepare와 generic Simulator build-for-testing, 준비한 호스트의 Simulator async API 비교 1/1 PASS를 확인했다. Simulator의 JPEG 관찰 수는 64/64로 실기기의 71/71과 달라 기기 간 결과를 동일한 정답으로 취급하지 않는다. 불완전한 1회 로그를 중앙값 결과로 승인하지 않는 것도 확인했다.

최신 소스 ZIP `ReproducibilityKit-2026-10-27-v2.zip`은 24,024바이트, 13파일이며 SHA-256은 `caf03d10b3b8470ef1f2007a108706e71f41029baff627d62585439d778deea1`다. 동명 `.sha256`과 폴더의 `CHECKSUMS.sha256`을 로컬에 보존했다. 이전 v1 ZIP도 삭제하지 않았다. ZIP 무결성과 개별 파일 체크섬을 대조했다. 키트는 제품 소스를 포함하지 않으며 prepare 시 지정한 패키지의 정확한 소스 해시를 기록한다. run 전에 고정 리비전과 checkout의 HEAD·추적 변경 여부, XCFramework 각 플랫폼 경로를 대조해 불완전한 캐시로 다운로드가 시작되는 상황도 방지한다.

이 대조 중 이관된 두 캐시의 Git alternates 8곳에 맥북의 이전 절대 경로가 남아 `bad object HEAD`가 나는 문제를 발견했다. 원래 파일을 백업하고 실제 이관 경로로만 수정했으며 읽기 전용 파일 모드도 복원했다. 의존성 소스·고정 리비전·바이너리는 바꾸지 않았다. 두 캐시 모두 고정 커밋·추적 변경 없음·플랫폼 경로 검사를 통과했다.

| 보존 선택지 | 장점·제약 | 현재 조치 |
| --- | --- | --- |
| 로컬 소스 키트+체크섬 아카이브 | 제품 변경 없이 이동·재실행 가능. 다른 사람이 받으려면 별도 전달 필요 | 지금 구성·검증 |
| 현재 저장소의 검증 도구 폴더에 소스만 편입 | 제품 타깃과 분리해 버전 관리·리뷰 가능. 파일 구조 변경에 대한 별도 결정 필요 | 제안만 함 |
| 별도 verification 저장소 | 제품 소스/샘플 배포 부담 분리. 소스 버전 연결과 유지보수 비용 증가 | 생성·게시하지 않음 |

장기적으로는 소스 전용 검증 도구를 버전 관리하는 방식이 재현성에 유리하다. 현재는 저장소 구조를 임의로 늘리지 않고 첫 번째 방식을 준비했다. runner는 새 출력 폴더만 허용하고, 실행 전 제품/테스트 소스 해시를 대조하며 캐시가 없으면 다운로드 대신 중단한다. 프로비저닝 서버 통신도 명시 옵션 없이는 하지 않는다. 삭제·푸시·PR·업로드·결제를 호출하지 않는다.

주요 로컬 증거: `qos-lldb-v2.log`, `qos-stress-prototypes.log/.xcresult`, `stress-vertical-overlap-prototype.log/.xcresult`, `order-fix-simulator.log/.xcresult`, `qos-followup-build.log`, `order-fix-lint.log`, `kit-build-check-v2.log`. 이전 실패와 중단 로그도 보존한다.
