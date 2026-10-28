# Vision 메모리 최소 재현 XCTest

[VisionMemoryReproduction.swift](VisionMemoryReproduction.swift)를 기존 iOS XCTest 타깃에 복사해 사용한다. Apple 프레임워크와 Swift 표준 라이브러리만 필요하다. OmniParser, 외부 패키지, 네이티브 바이너리, 다운로드 자산을 추가하지 않는다. 자체 예제 코드는 MIT다.

## 설정

최소 iOS 27.0과 Swift 언어 모드 5.0을 사용한다. SPM tools 6.2는 언어 모드와 다르며 이 예제 자체에는 `Package.swift`가 없다. 기존 타깃의 구조나 저장소 설정을 바꾸지 않고, 아래 명령의 임시 빌드 설정으로 Release를 확인한다.

테스트 파일의 타깃 멤버십과 공유 scheme의 Test action에 기존 XCTest 타깃이 포함되어 있어야 한다. 다음 두 메서드를 각각 별도 테스트 실행으로 선택한다.

- `VisionMemoryReproductionTests/testConcurrencyOne`
- `VisionMemoryReproductionTests/testConcurrencyTwo`

## 실행 명령

`YOUR_APP`, `YOUR_APP_TESTS`, `SIMULATOR_UDID`를 실제 기존 프로젝트·scheme·테스트 타깃·Simulator ID로 바꾼다. workspace를 쓰는 프로젝트라면 `-project`를 `-workspace`로 바꾸고 `.xcworkspace` 경로를 지정한다. Simulator ID는 `xcrun simctl list devices available`에서 확인할 수 있다.

결과 폴더에는 새 이름을 사용한다. 같은 xcresult가 이미 존재하면 삭제하거나 덮어쓰지 말고 폴더 이름을 바꾼다. 아래 함수는 기본 macOS zsh와 bash에서 사용할 수 있다.

```bash
vision_project='YOUR_APP.xcodeproj'
vision_scheme='YOUR_APP'
vision_target='YOUR_APP_TESTS'
vision_destination='platform=iOS Simulator,id=SIMULATOR_UDID'
vision_output='./VisionMemoryResults-NEW_RUN'
mkdir -p "$vision_output"

vision_case() {
  if xcodebuild test \
    -project "$vision_project" -scheme "$vision_scheme" \
    -configuration Release -destination "$vision_destination" -jobs 2 \
    -parallel-testing-enabled NO -collect-test-diagnostics never \
    "-only-testing:$vision_target/VisionMemoryReproductionTests/$1" \
    -resultBundlePath "$vision_output/$2.xcresult" \
    SWIFT_VERSION=5.0 SWIFT_OPTIMIZATION_LEVEL=-O \
    SWIFT_COMPILATION_MODE=wholemodule ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
    > "$vision_output/$2.log" 2>&1; then
    vision_exit=0
  else
    vision_exit=$?
  fi
  printf '%s\n' "$vision_exit" > "$vision_output/$2.exit"
  return "$vision_exit"
}

vision_case testConcurrencyOne A1 &&
vision_case testConcurrencyTwo B1 &&
vision_case testConcurrencyTwo B2 &&
vision_case testConcurrencyOne A2
```

이 순서는 동시성 1 → 2 → 2 → 1이다. 각 실행은 준비 1회와 측정 5회이며, 준비 실행을 제외한 표본은 총 20개다. 한 실행이 실패하면 먼저 로그와 xcresult를 확인한다. 실패 기록은 보존하고, 임의로 일부 표본을 제외하지 않는다. 추가로 실행할 때에는 새 결과 폴더를 사용한다.

실제 컴파일 로그에서 `-O`, `-swift-version 5`, 전체 모듈 최적화를 확인한다. 테스트 성공 여부만 보지 말고 xcresult의 runtime warning도 확인한다. Xcode 27에서는 각 결과의 요약을 다음처럼 보존할 수 있다.

```bash
xcrun xcresulttool get test-results summary \
  --path "$vision_output/A1.xcresult" > "$vision_output/A1.summary.json"
```

같은 방법으로 B1·B2·A2도 확인한다. 네 실행의 `inputSHA256`과 이미지별 `fingerprints`가 모두 같은지 별도로 대조한다. 테스트 코드가 검사하는 것은 한 실행 내부의 반복 일치다. 성공한 테스트 수만으로 네 실행 사이의 출력 일치나 warning 0을 단정하지 않는다.

## 입력과 인식

문서 형태 1240×1754 이미지와 영수증 형태 780×326 이미지를 서로 다른 자체 문구로 만든다. 한글과 영문은 같은 이미지 안의 별도 행에 그린다. 원본 small3의 실제 PDF·JPEG·DOCX와 동일한 입력이나 메모리 특성을 보장하는 샘플은 아니다. 글꼴·렌더링은 OS에 따라 달라질 수 있어 원본 픽셀 해시와 OS 버전을 남긴다.

`RecognizeTextRequest(.revision3)`에 accurate, 한·영, 최소 글자 높이 0, 자동 언어 감지, 언어 보정을 설정한다. 각 이미지에 새 요청을 생성한다. OmniParser의 세션 캐시·PDF 래스터·숫자 보완은 재현하지 않는다. 동시성 1은 하나씩, 동시성 2는 두 요청을 병렬로 실행한다. 구조적 취소를 사용하고 결과는 입력 순서대로 반환한다.

이미지 생성과 원본 픽셀 SHA 계산은 OCR 계측 전에 끝낸다. 준비 실행도 `warmup: true`로 남기지만 통계에서는 제외한다. 원래 인식 문자열·좌표·신뢰도를 정규화나 반올림 없이 JSON으로 직렬화한 SHA를 이미지별로 기록한다. 자체 마커는 boolean assertion으로 확인하고 인식 본문은 출력하지 않는다.

## 로그와 메모리 지표

`VISION_MEMORY` JSON에는 개수·해시·바이트·시간·OS·인식 설정만 기록한다. 자체 로거는 본문을 출력하지 않는다. framework 자체 시스템 메시지는 별도로 보존한다.

- `beforeBytes`, `sampledPeakBytes`, `withResultsBytes`, `afterResultReleaseBytes`는 `[phys_footprint, RSS]`이며 단위는 바이트다.
- `timelineMicrosecondsFootprintRSS`의 각 행은 `[시작 후 마이크로초, phys_footprint, RSS]`다. 5ms 간격으로 표본을 기록한다.
- `seconds`는 OCR 작업 그룹 시작부터 두 결과를 받을 때까지다. 이미지 생성·원본 해시·결과 assertion·지문 계산·로그 직렬화는 제외한다.
- 결과 지문과 marker 검사는 타이밍과 peak 계측을 종료한 뒤 실행한다.

기준 메모리는 sampler 할당 전 값이므로 sampler·timer·시계열 보관 비용이 측정에 포함된다. 결과 폐기 후에도 원본 이미지 두 장은 유지한다. `afterResultReleaseBytes`는 관찰 배열을 비운 뒤의 값이며 allocator arena나 Vision cache의 완전 해제, 누수 부재를 뜻하지 않는다. 결과 확인에 사용한 임시 할당도 이 값에 영향을 줄 수 있다.

sampler는 정상 종료·오류·취소 때 종료한다. 중복 finish는 같은 표본을 반환한다. 5ms 표본은 순간 최고점을 놓칠 수 있고, 주기적인 `task_info`·잠금·시계열 보관 자체가 실행에 간섭한다. footprint와 RSS의 최대 시점도 다를 수 있다.

## 연산 장치 진단

지원 장치 목록은 각 실행의 모든 준비·측정 루프가 끝난 뒤에만 조회한다. 측정 중이거나 측정 전에 조회하지 않으며 `setComputeDevice`도 호출하지 않는다. CPU·GPU·neuralEngine enum 이름과 명시적 지정 상태만 기록한다.

`unassigned`는 명시적으로 장치를 지정하지 않았다는 뜻이다. CPU 실행의 증거가 아니다. 새 요청의 지원 목록, 명시적 지정, 실제 요청의 연산 장치는 서로 다른 정보다. 이 진단만으로 실제 OCR이 어느 장치에서 실행됐는지 확정할 수 없다.

같은 프로세스에서 두 테스트 메서드를 연속 실행하면 Vision·CoreText와 장치 진단의 초기화가 다음 테스트에 영향을 줄 수 있다. 그래서 위 명령은 메서드마다 별도 실행을 사용한다. 별도 실행도 호스트 부하와 OS cache를 완전히 격리하지는 않는다.

## 해석과 검증 상태

이 예제는 framework 작업 중 메모리 변화를 관측하기 위한 것이다. 계측 없는 성능, 실기기, 특정 문서, Core ML 모델별 소유 메모리로 일반화하지 않는다. 97MiB 모델 준비 할당을 정확히 재현하거나 이 표본만으로 모델에 귀속시킨다고 주장하지 않는다. 일반 CI에 성능 벤치를 추가하지 않는다.

### 2026-10-28 Simulator 관측

독립 XCTest 호스트에서 iPhone 17 Simulator, iOS 27.0 (24A434), arm64로 1 → 2 → 2 → 1 순서를 실행했다. 실제 컴파일 로그에서 Release `-O`, Swift 언어 모드 5, 전체 모듈 최적화를 확인했다. 각 실행은 준비 1회와 측정 5회다. 저장소에 포함한 최종 소스를 다시 실행한 전체 벽시계 시간은 **46.92초**이며 빌드·테스트 실행기 비용을 포함한다.

| 요청 동시성 | 준비 제외 표본 | OCR 시간 중앙값 | 표본별 peak footprint 중앙값 | footprint 최대 | RSS 최대 | 결과 폐기 후 footprint 중앙값 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 10 | 1.039초 | 118.79 MiB | 134.28 MiB | 403.75 MiB | 33.61 MiB |
| 2 | 10 | 0.726초 | 156.83 MiB | 157.63 MiB | 466.66 MiB | 31.44 MiB |

20개 측정 표본과 4개 준비 실행 모두 이미지별 인식 개수 `[24, 3]`, 입력 픽셀 SHA, 텍스트·좌표·신뢰도 지문과 인식 설정이 일치했다. 네 invocation은 모두 exit 0, 테스트 실패·건너뜀 0, xcresult runtime warning 0이었다. 동시성 2에서 시간은 짧아졌고 peak footprint와 RSS는 늘었다. 특정 내부 모델의 할당 크기나 단독 원인으로 해석하지 않는다.

모든 루프 후 새 요청에서 조회한 장치 목록은 다음과 같았다.

| 진단 항목 | 실제 관측 |
| --- | --- |
| `MLComputeDevice.allComputeDevices` | GPU, CPU |
| `.main` 지원 목록 | GPU, CPU |
| `.postProcessing` 지원 목록 | 빈 배열 |
| `.main`·`.postProcessing` 명시적 지정 | 모두 `unassigned` |

이 목록은 Simulator의 지원 가능 장치와 설정 진단이다. 실제 OCR이 CPU나 GPU에서 실행됐다는 측정값이 아니며 장치를 강제로 선택하지 않았다. 실기기에서는 검증하지 않았다.

최초 자체 이미지는 한 행에 한글·영문을 함께 그렸고, 한국어 마커 assertion이 실패해 exit 65였다. 렌더링 진단 뒤 **한글·영문을 별도 행으로 생성**하여 위 20개 표본을 얻었다. 최초 실패·마커 진단·이미지 진단은 모두 보존했으며 성공 표본과 합산하지 않았다. 한 행 혼합 문장의 정확도는 이 예제로 검증하지 않았다.

호스트 관측 시 Simulator 한 대가 부팅되어 있었고 기록된 Simulator 재부팅 간섭은 없었다. 최종 실행 중 호스트 swap 사용량은 9559.38M→9463.38M이었다. 이 누적 사용량은 해당 테스트 중 실제 swap 입출력량을 뜻하지 않으며, OS cache·다른 프로세스·계측기의 영향을 배제할 수 없다.

### 원시 기록과 소스 상태

로컬 검증 기록의 루트는 `~/Developer/Codex/OmniParserVerification/2026-10-28/VisionMemoryFollowup/`다. 최종 소스의 원시 xcresult·로그·실행 명령·환경 관측은 `StandaloneVisionFinal/`에, 종합 수치는 그 안의 `VisionReproductionResults.json`에 보존한다. 최초 실패 기록은 `StandaloneVisionResults/`, `StandaloneVisionMarkerDiagnostics/`, `StandaloneVisionImageDiagnostics/`에 별도로 남긴다. 이 경로는 검증 환경의 로컬 산출물이며 패키지 의존성이나 배포 자산이 아니다.

최종 소스의 SHA-256은 `ffdf33479fca1808343d7a31cbc5a18566a0d8594a03e1b91d63bd1bdaaeb166`이며 저장소 파일과 실행 호스트의 파일 바이트를 대조했다. `FinalSourceSnapshot.swift`와 실제 `-O`·Swift 5·WMO 컴파일 로그도 함께 보존했다. SwiftLint strict를 이 예제 파일에도 명시적으로 실행해 위반 0건을 확인했다.

정리 전 성공한 별도 20표본·52.46초 기록은 `StandaloneVisionSeparatedLines/`에 보존했다. 최종 소스에서는 지문·장치 진단 helper와 TaskGroup 작성을 정리했으며, 재실행의 입력 픽셀과 텍스트·좌표·신뢰도 지문은 정리 전과 정확히 같았다. 두 시점의 시간·메모리 차이를 코드 최적화의 인과 효과로 해석하거나 통계를 합산하지 않는다.
