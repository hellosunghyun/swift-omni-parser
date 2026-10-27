# URL 입력과 배치 메모리 검증

2026-10-28 · 기준 `64d3a66` → 비공개 입력 스냅샷 Reader · iPhone 17 / iOS 27.0 Simulator

큰 URL 입력의 힙 복사를 줄였다. 문서·PDF 페이지 동시성, 작업 예산, OCR 언어·해상도, PNG encoder와 공개 API는 유지했다. `.data`·CGImage 입력은 기존 경로다. 아래 수치는 Debug 테스트 호스트의 관측값이며 실기기·Release 결과가 아니다.

## 원인 조사와 선택

작은 PDF/JPEG/DOCX 배치의 vmmap 진단에서 큰 live malloc이 확인됐다. 한 snapshot의 현재 footprint는 193.6MiB였고, `Malloc Large` dirty 127.5MiB, `Malloc Small` dirty 55.8MiB였다. 같은 실행은 반환 이미지가 0개여서 반환 PNG 누적으로 이 증가를 설명할 수 없다. 해당 범주와 allocator zone은 중복되므로 합산하지 않는다. vmmap 수집은 2.4~5.9초 걸려 여러 작업 전환을 포함했으며 이 자료만으로 특정 Vision 모델·tensor·캐시의 정확한 소유량은 확정하지 못했다.

추가로 전용 Simulator 호스트를 시작할 때만 `MallocStackLogging=1`을 설정하고 live 스택 조회를 시도했다. 테스트 1개와 두 스택 조회는 성공했지만 조회가 각각 7.5·9.3초 걸렸고, 얻은 snapshot은 OCR 최대 할당을 포착하지 못했다. 초기 ICU·폰트 할당을 OCR peak의 원인으로 해석하지 않는다. 권한·보안 설정을 바꾸지 않았으며 이 진단의 시간·메모리는 아래 비교에 섞지 않았다.

그다음 같은 호스트·바이너리의 새 실행을 `proc_pid_rusage`로 관찰했다. 첫 배치 시작 약 1.04초 뒤 footprint 178.6MiB에서 해당 진단 PID만 잠시 정지해 스택을 수집하고 재개했다. CoreML 모델 로드 → `MLNeuralNetworkEngine` → Espresso plan 준비 → `blob_cpu::resize` → `kern_alloc_uninitialized` 경로의 가장 큰 스택 그룹은 28개 할당·97.16MiB였다. 이 시점의 큰 live 할당에 모델 준비·CPU blob이 포함됨을 확인했다. 이는 실행 전체의 최고 시점이나 옛 동기 엔진 대비 증가량을 직접 측정한 결과가 아니며, allocator 집계와 footprint 기여량도 동일하지 않다. 조회 5.99초 후 재개했고 테스트는 정상 종료했다.

PDF crop은 원본 raster를 보유하고 그 raster가 fallback에도 필요했다. 작은 숫자 OCR의 threshold 세 장은 순차 처리된다. 임시 객체 수명·executor·codec pool 후보는 유의미한 이득을 입증하지 못해 되돌렸다. PDF 예약량을 48→64MiB로 높이면 실제 병렬 페이지 창이 좁아지고 추가 OCR 비교에서 시간 중앙값이 26% 늘어 채택하지 않았다.

대용량에서는 URL의 `Data(contentsOf:)`가 입력 전체를 힙에 복사하는 성분을 분리했다. 57,333,902바이트 PDF의 macOS 독립 read+SHA 진단은 footprint 57.016→2.375MiB, RSS 61.531→61.594MiB였다. 이 진단의 매핑 경로는 더 느렸으므로 전체 파서 속도는 아래에서 별도로 비교했다. 작은 배치의 작업 버퍼 문제를 입력 복사 하나로 모두 해결했다는 의미는 아니다.

## 적용한 Reader

- 로컬 파일 URL을 동기 `NSFileCoordinator` 읽기 구간에서 열고, 일반 파일 여부와 크기를 FD로 확인한다. NUL 경로와 FIFO 등 일반 파일이 아닌 입력을 거부한다.
- 복제 가능한 일반 파일은 같은 FD에서 비공개 0700 디렉터리에 COW 복제하고 `mappedIfSafe`로 읽는다. 원본 쓰기·truncate·교체와 독립된 입력을 유지한다. 실제 매핑 여부는 Foundation이 결정한다.
- source·clone 보호 등급을 확인한다. 잠금 후 접근이 만료되는 등급, 알 수 없는 명시 값, 파일 플래그, symlink, 복제 미지원 파일시스템은 64KiB 청크·누적 크기 제한이 있는 복사 경로를 사용한다. 원본 속성을 바꾸지 않는다.
- 읽기 후 자체 clone과 디렉터리를 정리하고 정리 실패를 보고한다. 매핑이 사용되는 동안 backing 파일 수명은 커널이 유지한다. security scope와 로컬 참조 이미지의 기준 디렉터리는 기존처럼 전체 parse 동안 유지한다.
- 취소·읽기 전후 크기 제한을 확인한다. 동기 파일 조정이나 native 내부 작업을 즉시 강제 중단한다고 보장하지 않는다. 문서 내용·경로를 제품 로그에 추가하지 않았다.

## 전후 비교

Mac mini M4, 16GiB, Xcode 27.1 / Swift 컴파일러 6.4, Swift 언어 모드 5, 동일 캐시·호스트·입력·옵션이다. 각 조건은 예열 1회 제외 후 3회다. 시간은 `parseBatch` 구간의 중앙값, 메모리는 `task_info(TASK_VM_INFO)`를 20ms마다 읽은 3회의 최댓값이다. MiB는 1,048,576바이트다. 자산 생성·빌드·fingerprint 계산은 계측에서 제외했다. 순간 최고치를 놓칠 수 있으며 파서만의 순수 할당량도 아니다.

모두 `performOCR: true`, 동시 문서 2개와 기본 PDF 작업 설정이다.

| 입력 | 이미지 반환 | 시간 중앙값 초: 기준 → 수정 | 최대 footprint MiB: 기준 → 수정 | 최대 RSS MiB: 기준 → 수정 |
| --- | --- | ---: | ---: | ---: |
| 작은 스캔 PDF·JPEG·DOCX 3문서 | 끔 | 1.471 → 1.434 | 205.67 → 202.92 | 523.97 → 542.03 |
| 20페이지 PDF를 독립 URL 입력 2개로 반복 + XLS·DOCX·RTF·PNG·손상 입력, 7문서 | 끔 | 35.444 → 34.125 | 476.97 → 448.00 | 699.52 → 744.92 |
| 60·20페이지 PDF + 같은 나머지 5입력, 7문서 | 켬 | 71.120 → 70.261 | 581.16 → 503.83 | 761.47 → 842.58 |

스캔 PDF는 자체 생성한 200dpi 한영 혼합 이미지이며 텍스트 레이어가 없다. 60·20페이지 원본은 각각 57,333,902·19,109,969바이트다. 마지막 시나리오는 2,495블록·84이미지·91,049,403 PNG바이트·경고 1개이며 마지막 손상 입력의 개별 실패를 보존했다.

이 첫 비교 중 다른 작업이 Simulator 4대를 다시 켠 상태가 관측돼 허용된 범위에서 종료했다. 약 12GiB의 호스트 swap도 남아 있었다. 각 표본의 정확한 경합 시간은 미확정이므로 이 차이를 변경의 단독 효과나 모든 문서의 속도 유지 보장으로 해석하지 않는다. 원시 값은 좋은 표본만 고르지 않고 모두 보존했다.

같은 소스·호스트로 대용량 사례를 추가 비교했다. 10초마다 Simulator 상태·swap 보유량을 기록했고, 다른 Simulator 재부팅을 기준 2회·수정 1회 감지해 종료했다. 따라서 이 재확인도 완전한 독점 실험은 아니다. swap 보유량은 실제 swap 입출력 속도를 측정한 값이 아니다.

| 대용량 재확인 | 기준 | 수정 | 변화 |
| --- | ---: | ---: | ---: |
| 시간 중앙값 | 66.105초 | 66.015초 | −0.13% |
| 최대 footprint | 544.38MiB | 484.67MiB | −10.97% |
| 최대 RSS | 988.78MiB | 911.16MiB | −7.85% |

대용량 두 비교에서 footprint는 11~13% 낮았고 시간 중앙값은 비슷했다. RSS는 첫 비교에서 늘고 재확인에서 줄었다. 매핑은 큰 dirty 힙 복사를 파일에 의해 뒷받침되고 회수 가능한 페이지로 바꾸지만, 읽은 clean 페이지도 상주할 수 있다. 따라서 RSS 감소가 항상 보장된다는 의미는 아니다. 작은 배치의 footprint 차이도 1.3% 수준이어서 유의미한 개선 근거로 보지 않는다. 큰 입력 외의 Vision 작업 버퍼와 반환 결과의 보유 메모리는 남는다.

## 결과 보존과 검사

- 세 시나리오의 기준·수정 각 3회, 총 18개 표본에서 각 시나리오 안의 semantic SHA-256과 별도 PNG 바이트 해시가 정확히 같았다. 추가 대용량 6개 표본도 앞선 대용량 6개와 같았다. 입력 순서·개별 실패, 전체 텍스트, 블록 종류·읽기 순서·위치·신뢰도·원래 OCR 텍스트, 경고, 그림 메타데이터와 canonical 8비트 sRGB 픽셀을 비교했다.
- 별도 65문서 corpus의 블록 내용·위치·신뢰도·원래 OCR 텍스트 및 경고 payload는 65/65 동일하다. PNG 바이트를 포함하는 그림·순서 합성 해시는 64/65 동일하다. 기존 baseball PNG 1건은 양쪽 총 8회 반복에서 컨테이너 바이트 변동이 있지만 크기·픽셀·방향·위치·텍스트는 같았다. 이 합성 해시를 독립적인 읽기 순서 해시로 표현하지 않는다.
- 새 회귀는 URL 원본 truncate·교체 후 결과 보존, symlink·immutable 원본과 보호 정책, NUL·크기·손상·읽기 실패, 취소·임시 항목 정리, 작은 PDF 작업 예산의 배치·단독 결과 동등성을 확인한다.
- CoreVideo `CVPixelBufferCreate -6680` 경고는 첫 비교의 기준·수정에서 작은 배치 각각 4회, 나머지 각각 16회로 크기·RGBA 형식·옵션별 횟수까지 같았다. 결과 동등성으로 시스템 경고의 원인이나 일반적 무해성까지 증명하지는 않는다.

| 검사 | 최종 결과 |
| --- | --- |
| 패키지 XCTest | 리소스 보완 후 재실행도 56개 통과, 실패·skip 0, 테스트 본문 61.525초 |
| generic Simulator build | 통과, exit 0 |
| SwiftLint 0.65.1 strict | 55파일, 위반 0 |
| 65문서 corpus | 2개 검사 통과, 테스트 본문 25.711초 |
| SwiftPM 소비자 앱 | public API 호출 코드 빌드·앱 내 OmniParser manifest 포함 및 값·해시 일치 |
| 의존성·원래 바이너리·라이선스·OS·언어 모드 | 변경 없음 |
| 실기기·전체 파서 Release | 이번 작업에서 미실행 |

메모리 계측 뒤 새 `fstat`·`lstat` 사용에 필요한 privacy manifest를 SDK 리소스로 추가했다. 파일 조회 사유와 범위는 [API 문서](API.md)에 적었다. `Package.swift`의 리소스 등록과 manifest를 제외한 파서·회귀 Swift 소스는 성능 계측 시점과 정확히 같음을 해시로 확인했다. 소비자 앱의 `OmniParser_OmniParser.bundle/PrivacyInfo.xcprivacy`를 직접 읽어 원본과 값·SHA-256 일치를 확인했다. 이는 앱 번들 포함 검사이며 App Store 심사·다른 SDK의 선언 검증을 대신하지 않는다.

## 재실행과 근거

저장소의 기본 검사는 다음과 같다. 실제 로컬 실행은 고정 의존성 캐시에 `-disableAutomaticPackageResolution -skipPackageUpdates -onlyUsePackageVersionsFromResolvedFile`도 적용했다.

```bash
xcodebuild test -scheme OmniParser -jobs 2 \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -skipMacroValidation -packageAuthorizationProvider netrc \
  -parallel-testing-enabled NO -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO
xcodebuild build -scheme OmniParser -jobs 2 \
  -destination 'generic/platform=iOS Simulator' \
  -skipMacroValidation -packageAuthorizationProvider netrc CODE_SIGNING_ALLOWED=NO
swiftlint lint --strict
```

원시 로그·xcresult·모든 회차·진단 후보는 로컬 `~/Developer/Codex/OmniParserVerification/2026-10-28/BatchMemory/`에 보존했다. 공개 저장소에는 측정 API·추가 바이너리·개인 문서·진단 원문을 넣지 않는다.

- 원인: `VMMapSeries-ANALYSIS.md/.json`, `BaselineVMMapSeries/`, `InputSnapshotPrototype/`.
- 추가 스택 진단: `MallocStackLogging64d-20261027T183812Z-8e6b5/`. snapshot 시각과 테스트 처리 구간의 차이를 보존했다.
- 높은 메모리 시점의 스택: 같은 폴더의 `FrozenPeak-184953-17f7/ANALYSIS.md/.json`. PID 경로 검증·관측값·정지·재개·watchdog·테스트 종료 기록을 함께 보존했다.
- 성능 계측 시 소스·호스트 대응: `snapshot-v4-host-preparation-check.json`, `final-source-provenance.json`, 각 호스트의 `SourceSnapshot.json`.
- 첫 성능 비교: `snapshot-final-executed-commands.json`, `snapshot-final-performance-summary.json`, `SnapshotEngineKit/BatchMemorySingleEngineTests.swift`. 각 log·xcresult의 원본 명령과 표본을 함께 보존했다.
- 추가 대용량: `v5-png80-stable-commands.json`, `v5-png80-stable-run.py`, `snapshot-v5-png80-performance-summary.json`, 같은 이름의 environment·interference JSONL 및 원시 log·xcresult·metadata.
- corpus: `SNAPSHOT_V4_CORPUS_COMPARISON.md`, `snapshot-v4-corpus-comparison.json`.
- 기본 검사: `snapshot-regression-56-v2` log·exit·xcresult·command JSON, `snapshot-build-simulator` log·exit·command JSON, `snapshot-lint-encoded-nul.log`.
- 리소스 보완 후 검사: `snapshot-privacy-regression-56` log·exit·xcresult·command·summary JSON, `snapshot-privacy-build-simulator` log·exit·command JSON, `snapshot-privacy-lint.log`.
- 소비자 앱: `privacy-consumer-command.json`, `privacy-consumer-build` log·exit, `privacy-plist-validation.json`, `privacy-consumer-resource-validation.json`.
