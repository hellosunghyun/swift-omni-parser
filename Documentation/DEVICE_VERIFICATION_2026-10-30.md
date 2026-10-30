# iPhone 17 실기기 회귀와 벡터 메모리 전후 검증

2026-10-30. 제품 소스 `45efbf7`을 iPhone 17에서 검증했다. 이 기록의 검증 당시 제품 코드는 수정하지 않았다. 후속 수정·163개 회귀와 최종 전후 비교는 [메모리·QoS 수정 검증](DEVICE_OPTIMIZATION_2026-10-30.md)에 별도로 기록했다. 아래 QoS·미관측 상태와 수치는 당시 결과로 보존한다. 앞선 [Simulator 벡터 검증](VECTOR_VERIFICATION_2026-10-30.md)과 실행 환경·메모리 지표를 구분한다.

## 전체 회귀

| 항목 | 실제 결과 |
|---|---|
| 기기 | 물리 iPhone 17, arm64, iOS 27.2 / 24B119 |
| 빌드 | Xcode 27.1 / iOS SDK 27.1, Release, 최소 iOS 27.0·Swift 언어 모드 5 유지 |
| 전체 XCTest | **159/159 PASS**, 실패·skip·expected failure 0 |
| XCTest 본문 | **21.735초**, 빌드·설치·연결 대기 제외 |
| WebKit 시작 후 취소·다음 렌더 | **PASS**, 0.084초 |
| 런타임 경고 | **QoS 경고 1건**, 아래에 미해결 사항으로 구분 |

로컬 검증 호스트에는 저장소 테스트 Swift 29개를 원본 바이트 그대로 복사하고 Bundle.module 접근 어댑터만 추가했다. 기존 HWP 회귀의 메타데이터 링크를 위해 같은 고정 버전 CoreHwp를 테스트 타깃에 연결했다. 개발 팀은 CLI에만 적용했고 저장소의 서명·OS·언어 설정을 바꾸지 않았다. Simulator에서 통과한 수치를 실기기 결과로 사용하지 않았다.

## 메모리·시간 측정 조건

공개 API만 호출하는 외부 `VectorMemoryHost`를 기기용으로 빌드했다. baseline은 `b281a1b`(작업별 nonpersistent 저장소), current는 `45efbf7`(공유 저장소·1초 idle 해제)다. 제품 소스의 차이는 `DocumentVectorWebView.swift` 한 파일뿐이며 두 호스트의 App·측정 테스트 파일 4개는 바이트가 같다. bundle ID는 설치를 구분하기 위해 다르게 사용했다. 서명 검증도 통과했다.

자체 생성 WMF·EMF의 같은 RTF 입력을 사용했다. **OCR은 꺼 벡터 변환 비용을 분리**했고, 옵션 off → 새 프로세스의 첫 WMF/EMF → 20회 직렬 → 8문서 배치(동시성 2) → 초기 취소 → 진행 중 취소 → 취소 후 20회 재시도 → 5초 idle 순서다. 장비 재부팅을 뜻하는 cold start가 아니라 각 앱 프로세스에서 첫 렌더다.

실행 순서는 baseline/current/current/baseline/baseline/current(**ABBAAB**)이며 각 버전 3회다. 제품 소스 manifest는 각 빌드 전후 같았다. baseline SHA-256은 `c766bdb6eb8a68f951a539f4a4b810100ff3e7b8c78b58c587d8b960b2667db4`, current는 `0ff2760e9b777b0c39e7f0f8c5189dacc57545feec302cedaf7791aa5be3efde`다. 각 실행의 source revision도 해당 빌드와 일치한다.

메모리는 **앱 자체 `task_vm_info.phys_footprint`**만 측정했다. 표본은 10ms 간격이고 peak는 표본 peak 대신 OS lifetime peak를 사용한다. WebContent/GPU/Networking 등 별도 프로세스는 포함하지 않는다. 이 값을 전체 앱 생태계·OS RAM으로 합산하거나 Simulator RSS와 비교하지 않는다. 3회는 제한된 관찰이며 통계적 보편 성능 보장이 아니다.

## 실측 결과

아래 값은 버전별 3회 중앙값이다.

| 항목 | baseline | current |
|---|---:|---:|
| 옵션 off, 2문서 | 1.704 ms | 1.661 ms |
| 새 프로세스의 첫 WMF | 155.060 ms | 130.059 ms |
| 이어지는 첫 EMF | 106.414 ms | 66.487 ms |
| 20회 직렬 | 1,620.868 ms | 1,319.307 ms |
| 8문서 배치, 동시성 2 | 666.029 ms | 516.439 ms |
| 취소 후 20회 재시도 | 1,668.478 ms | 1,336.967 ms |
| 진행 중 취소 요청→반환 | 0.521 ms | 2.076 ms |
| 앱 자체 OS peak footprint | **57.861 MiB** | **60.768 MiB** |
| 5초 idle 후 앱 자체 footprint | 51.893 MiB | 53.643 MiB |

OS peak 3회 원시값은 baseline **57.674 / 58.971 / 57.861 MiB**, current **60.768 / 61.189 / 57.689 MiB**다. 중앙값은 약 **2.906 MiB, 5.0% 증가**했다. 반복 처리는 빨라졌지만 실기기 자체 peak 메모리 감소는 확인하지 못했다. 앞선 Simulator footprint 감소를 실기기 개선으로 확대하지 않는다. 취소 지연도 이 관찰에서 개선되지 않았다.

6개 벤치 XCTest는 모두 **1/1 PASS**다. 실행별 phase_end 9개·run_end 1개를 확인했으며, 파싱 실패·PNG 일관성·본문 일관성·배치 순서 실패는 모두 0이다. 모든 단계의 PNG·본문 SHA-256 배열이 6회 전체에서 정확히 같았다. 초기 취소와 public extracting 이후 미완료 Task를 취소하는 경우도 모두 전파됐고 후속 20회 재시도가 성공했다. 배치 취소는 기존 `CancellationError` 계약을 유지한다.

## WebKit 별도 메모리: NOT_OBSERVED

Instruments Activity Monitor의 프로세스 footprint·resident-size·responsible-process 필드를 확인했지만 실제 기기 기록은 시작하지 못했다. UDID 지정은 `Timed out waiting for device to boot`, CoreDevice UUID 재시도는 `No devices found matching`으로 종료됐다. 같은 시점 devicectl과 XCTest에서는 기기가 부팅·잠금 해제·개발 서비스 연결 상태였고 테스트가 실행됐다. 따라서 기기가 꺼졌다고 결론 내리지 않는다.

설치된 Instruments는 27.1, 기기는 iOS 27.2이지만 버전 차이를 원인으로 확정하지 못했다. Xcode/기기/네트워크 설정을 바꾸지 않았고 trace·WebKit 메모리 샘플은 수집되지 않았다. 별도 WebKit 메모리를 0이나 앱 자체 값으로 대체하지 않는다. 모든 벤치 6회는 Instruments 기록 없이 같은 조건으로 수행했다.

## 남아 있는 QoS 경고

159개 회귀의 xcresult에는 User-initiated QoS 스레드가 Default QoS 작업을 기다린다는 경고 1건이 남았다. 위치는 65개 실제 샘플을 순회하는 `FormatRegressionTests`의 `await DocumentParser.parse` 호출부다. 55개 raw stack 주소는 있지만 함수·모듈·이미지 load 주소가 없어 정확한 심볼화·원인 귀속이 불가능했다. 특정 문서 형식·Vision·WebKit·백엔드 중 하나를 원인으로 단정하지 않는다. 이 경고는 기능 테스트 통과와 별도이며 해결됐다고 표시하지 않는다.

## 재현과 증거

원시 xcresult·기기 로그·임시 앱·서명 자료는 제품 저장소에 포함하지 않는다. 로컬 루트는 `~/Documents/Codex/OmniParserVerification/2026-10-30/`다.

- `device-159-current.log`와 동명 xcresult: 159개 실제 실행.
- `device-memory-{baseline,current}{,-2,-3}.log`와 동명 xcresult: 6회 벤치 원문.
- `device-memory-three-pair-summary.json`: 단계별 수치·PNG/본문 해시의 집계.
- `DeviceHost/`, `VectorMemoryDeviceHost/`, `VectorMemoryBaselineDeviceHost/`: 저장소 밖 검증 호스트.
- `CI/DEVICE_WEBKIT_MEMORY_METHODS.md`: Instruments 조사·실패 기록.

실행 명령은 서명 완료된 호스트의 xctestrun을 사용한다. 실제 기기 ID·절대 경로는 로컬 환경에 맞게 지정한다.

```bash
xcodebuild test-without-building -xctestrun /path/to/VectorMemoryHost_iphoneos27.1-arm64.xctestrun \
  -destination 'platform=iOS,id=DEVICE_UDID' -destination-timeout 45 \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath /path/to/unique-device-result.xcresult
```

제품 코드 변경·의존성 추가·공개 API 변경은 없다. 미지원 WMF·EMF 명령의 부분 이미지·위치 경고, 기존 라이선스와 자원 제한도 유지한다.
