# iPhone 17 메모리·QoS 수정 검증

2026-10-30. 앞선 [공유 WebKit 저장소 검증](DEVICE_VERIFICATION_2026-10-30.md)의 제품 소스 `45efbf7`을 기준으로, 오류 종료 시 JSContext 참조와 HEIC PNG 변환의 QoS 경고를 수정했다. 최소 iOS 27.0, Swift 언어 모드 5, 의존성·공개 API·벡터 자원 제한은 유지했다.

## 원인과 변경

- JavaScriptCore 예외의 JSValue가 context를 보관하는 경로가 있었다. `defer { context.exception = nil }`로 변환 종료 시 예외 참조만 해제한다. 강제 GC·공유 VM·임의 callback 해제는 하지 않는다.
- 별도 macOS 공개 API 재현에서 오류·예산 초과·취소를 각 30회 호출했다. 호출별 autoreleasepool을 비워도 기존 경로는 context 30개가 살아 있었고, 예외 참조 해제 후에는 각각 0개였다. 취소 30회도 모두 취소 오류로 반환했다. 이 객체 수 검사는 iPhone footprint 수치를 대신하지 않는다.
- 정상 변환은 바깥 autoreleasepool이 비워지면 기존 context도 해제됐다. 동기 변환·SVG·PDF 단계에 pool을 더하는 후보는 실제 기기에서 일관된 이득을 보이지 않아 철회했다. pool과 예외 정리를 함께 적용한 3쌍 비교는 peak 약 3.9% 감소와 반복 처리 약 2% 지연을 보였으므로 최종 결과로 사용하지 않았다.
- QoS 경고는 65문서 회귀 중 HEIC의 `CGImageDestinationFinalize`에서 발생했다. 같은 실행의 dyld 이미지 범위·UUID·dSYM으로 raw stack을 심볼화했고 ImageIO·CMPhoto 호출을 확인했다. 경고 stack에는 Vision·WebKit이 없었다. 지연 디코딩이 원인일 가능성은 소스·스택을 토대로 한 추론이다. PNG 인코딩을 default-QoS OperationQueue(최대 2개)에서 처리해 호출 Task를 suspend한다.
- 대기 중 취소는 인코딩을 생략하고 실행 중 취소는 native ImageIO 호출이 끝난 뒤 전달한다. 실행 중 native 호출의 강제 중단이나 전체 배치 메모리 상한을 보장하지 않는다. 대기 중 취소도 큐에서 자기 차례가 올 때까지 CGImage를 보유할 수 있다. 큐의 2개 제한은 실행 중 인코딩 수이며 대기 요청 수의 전역 상한은 아니다. PNG 바이트 한도는 기존처럼 인코딩 후 검사한다. 완료 PNG는 기존과 동일하게 방향 메타데이터를 보관한다.

## 회귀와 추출 결과

최종 제품 소스 `df6b502`를 iPhone 17 / iOS 27.2(24B119), Xcode 27.1 / SDK 27.1, Release로 실행했다. **163/163 PASS**, 실패·skip·expected failure·xcresult runtimeWarnings 모두 0이다. XCTest suite wall time은 21.087초(테스트 합계 21.053초)이며 빌드·설치·무선 연결 대기는 제외한다. 기존 159개와 PNG 방향별 원본 바이트·동시성 2·대기/진행 중 취소 회귀 4개를 포함한다.

외부 호스트의 HEIC 옵션 4조합과 신규 PNG 테스트 4개를 묶은 5개 테스트도 실제 기기에서 모두 통과했고 runtimeWarnings는 0이었다. 이미지 추출을 켠 두 조합의 PNG는 각각 12,592,943바이트, SHA-256 `3806e1089a1517c8f7277c3b1e66bc851c54d404296c9b3b52aac0238d4b2b9f`로 같았다. 일반 회귀가 모든 실문서의 완전 복원을 보장하지는 않는다.

## 최종 실기기 전후 비교

control은 `45efbf7`, final은 `df6b502`와 제품 파일 59개가 모두 같은 고정 소스 `f261552`다. 차이는 Encoder·RasterParser·VectorScript 3개이며 App·측정 테스트 4개와 입력은 바이트가 같다. 서명된 Release 호스트를 **ABBAABBAAB 순서로 각 5회**, 새 앱 프로세스에서 실행했다. 정상 벡터 처리와 취소·재시도 9단계를 모두 포함하며 OCR은 꺼 변환 비용을 분리했다. 이는 OCR·대용량 스캔 PDF의 전후 성능 측정이 아니다.

메모리는 앱 자체 `task_vm_info.phys_footprint`의 **OS lifetime peak**다. 10ms 표본 peak와 구분하며 WebKit·GPU·Networking 프로세스를 포함하지 않는다. 시간은 해당 단계의 wall time이고 빌드·설치·연결 대기를 제외한다.

| 항목 | control 중앙값 | final 중앙값 |
|---|---:|---:|
| 앱 자체 OS peak | 60.846 MiB | **57.861 MiB** |
| 5초 idle 후 footprint | 53.783 MiB | 51.252 MiB |
| 옵션 off 2문서 | 1.248 ms | 1.252 ms |
| 첫 WMF | 114.547 ms | 115.696 ms |
| 이어지는 첫 EMF | 65.054 ms | 62.245 ms |
| 20회 직렬 | 1,265.476 ms | 1,279.294 ms |
| 8문서 배치, 동시성 2 | 490.376 ms | 498.449 ms |
| 취소 후 20회 재시도 | 1,315.724 ms | 1,321.316 ms |
| 진행 중 취소 요청→반환 | 2.008 ms | 0.951 ms |

peak 중앙값은 **2.984 MiB, 약 4.9% 감소**했다. 원시값은 control **61.690 / 60.846 / 58.924 / 61.424 / 58.846 MiB**, final **56.955 / 56.986 / 57.986 / 62.643 / 57.861 MiB**다. final 네 번째 실행의 높은 값을 제외하지 않았다. 관측 최고값은 오히려 61.690→62.643 MiB이므로 모든 실행의 최대 메모리 개선이나 전체 프로세스 메모리 상한을 주장하지 않는다.

20회 직렬은 중앙값 **1.09%**, 배치는 **1.65%**, 취소 후 재시도는 **0.42%** 느렸다. 관측 범위는 직렬 control 1,238.131–1,296.324 / final 1,274.753–1,305.164 ms, 배치 483.060–514.694 / 487.070–517.276 ms, 재시도 1,258.615–1,325.422 / 1,315.091–1,329.820 ms로 모두 겹친다. 이 제한된 5쌍에서 큰 처리 지연은 관찰하지 않았으나 무저하·통계적 동등성의 증명은 아니다.

10개 벤치 XCTest가 모두 통과했고 각 실행의 phase_end 9개·run_end 1개를 확인했다. 파싱 실패·메모리 조회 실패·PNG/본문 일관성·배치 순서 실패는 모두 0이다. **모든 단계의 PNG·본문 SHA-256 배열과 결과 개수가 10회 전체에서 동일**했다. 초기 취소·진행 중 배치 취소·후속 20회 재사용도 통과했다. 앞선 3쌍 후보나 과거 공유 저장소 비교를 이 5쌍에 합산하지 않았다.

control 제품 manifest SHA-256은 `0ff2760e9b777b0c39e7f0f8c5189dacc57545feec302cedaf7791aa5be3efde`, final은 `f0dc962a4d53f54f5145f22724d00162c2b3ac68b953e7e989d7b0e0f4995d68`이다. 빌드 전후 소스가 같고 기존 서명 산출물 192개가 바뀌지 않았음을 확인했다.

## WebKit 별도 메모리

**NOT_OBSERVED**다. iPhone 17은 무선 개발 연결만 가능한 조건이었다. devicectl·XCTest는 정상 실행됐지만 Instruments Activity Monitor는 기록 시작 직후 `Device disconnected`로 끊겼다. XCTest 실행 중 시도와 별도로 디버거·console 연결 없이 서명된 독립 앱을 실행해도 같은 현상이 재현됐다. 독립 앱은 벡터 10개를 모두 처리하고 종료 기록을 남겼으나 trace는 파싱 전 대기 1.077초만 포함했다. 따라서 이 trace에서 앱의 WebContent·GPU peak를 산출하지 않는다.

앞선 1.290초 trace에 나타난 기존 WebContent 프로세스도 responsible PID로 이 앱에 귀속할 수 없어 제외했다. 기기·Xcode·네트워크 설정은 바꾸지 않았다. Xcode 27.1과 기기 27.2의 버전 차이만을 원인으로 확정하지 않는다. 아래 앱 자체 footprint에 WebKit 프로세스 값을 더하거나 미관측 값을 0으로 채우지 않는다.

## 재현과 증거

서명 팀은 CLI에만 지정했다. 로컬 실기기 호스트는 저장소 테스트를 그대로 복사하고 Bundle.module 어댑터만 추가하며 동일 버전 CoreHwp를 테스트 타깃에 연결했다. 원시 기기 로그·xcresult·서명 앱·진단용 호스트는 제품 저장소에 넣지 않는다.

로컬 증거 루트는 `~/Documents/Codex/OmniParserVerification/2026-10-30/`다.

- `device-finalpair-{control,final}-{1..5}.log`와 xcresult, `device-final-five-pair-summary.json`: 최종 10회 전후 비교.
- `device-final-163.log`와 xcresult: 최종 전체 회귀.
- `memory-final-lint.log`: strict lint.
- `MemoryErrorResearch/`: 오류·예산·취소의 context 생존 검사.
- `QoSDeviceHost/Analysis/`: 같은 실행의 stack 심볼화와 HEIC 원인 귀속.
- `PNGQoSDeviceHost/Logs/`: HEIC 4옵션·PNG 테스트.
- `StandaloneVectorProbeApp/`, `CI/DEVICE_WEBKIT_MEMORY_METHODS.md`: 무선 Instruments 중단과 독립 앱 완료 기록.
- `device-pool-*`, `device-cleanup-*`: 철회한 후보의 측정 원문. 최종 후보에 합산하지 않는다.

실행 명령은 [앞선 실기기 검증](DEVICE_VERIFICATION_2026-10-30.md#재현과-증거)의 `test-without-building`을 따른다. 반복 비교는 동일한 App·테스트 입력의 서명된 호스트를 사용하며 프로파일러와 동시에 실행하지 않는다.
