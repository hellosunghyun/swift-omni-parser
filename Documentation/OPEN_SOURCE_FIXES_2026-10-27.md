# 오픈소스 검토 후속 수정·검증

2026-10-27~28. 공개 `v0.1.0-alpha.1`의 기준 소스는 `eb13cb5`다. 설치·정확성·자원 제한·OCR·제작 절차 문제를 수정했다. iOS 최소 27.0, tools 6.2, Swift 언어 모드 5.0, 공개 파싱 API와 이미지/OCR 기본값 false를 유지한다. 새 런타임 의존성이나 바이너리 파일을 Git에 추가하지 않았다.

## 수정한 내용

| 항목 | 수정·검증 |
| --- | --- |
| 버전 설치 차단 | OdrCore를 같은 b302cc 커밋의 `exact: 7.5.2-omni.1`로 변경. 새 SemVer 소비 프로젝트에서 해석·공개 자산 다운로드·generic Simulator 빌드 통과 |
| JSON 의미 손실 | 불리언을 CFBoolean으로 구분해 true/false 보존. 숫자·null 혼합 공개 API 회귀 추가 |
| 인라인 SVG 오판 | 독립 XML 루트만 판별. HTML 본문·Markdown 예제 보존, HTML SVG에는 위치 경고 |
| Legacy Office 중복 | 문구·PNG가 같아도 원본 위치가 다르면 보존. 실제 CFB 스트림에 동일 그림 두 개를 생성한 통합 회귀로 PNG/OCR 옵션 양쪽 검증 |
| ZIP 해제량 공백 | OOXML·HWPX native 진입 전 모든 실제 해제량·CRC·헤더·descriptor를 64KiB 버퍼로 검사. 허위 크기·누적 예산·바이너리 CRC 회귀와 descriptor CRC=서명 값의 서명 생략/포함 양쪽 경계 검사 추가 |
| 취소·자원 반환 | 취소와 native 오류가 겹치면 취소 우선. PDF 대기 취소·즉시 취소 100회·예약 반환, OCR 성공·실패·취소 후 세션 반환 검사 |
| 동기 OCR 대기 | Swift Vision revision 3 비동기 경로로 전환. 한영·보정·최소 글자 높이 0 유지, 숫자 재인식도 비동기 처리 |
| 불필요한 작업 | 이미지·OCR을 모두 끈 Legacy 보완 단계에서 CFB 스트림을 다시 읽지 않음 |
| 배포·기여 | 고정 action/tool 자산의 PR/main 자동 CI, 새 버전 소비자 검사, 기여·보안 제보 안내, 기존 바이너리를 교체하지 않는 재빌드·고지 생성 절차 추가 |

ZIP은 stored/DEFLATE를 검사한다. 압축·CRC가 손상된 컨테이너는 native에 넘기지 않고 거부한다. 정상 컨테이너에서 특정 그림 디코딩만 실패하면 본문·표를 보존한다. 실행 중 페이지 예산과 반환 결과 메모리·프레임워크 캐시는 다른 한도이며 프로세스 강제 상한을 보장하지 않는다.

## 실제 실행 결과

| 검사 | 결과 |
| --- | --- |
| 패키지 회귀 | iPhone 17 / iOS 27.0 Simulator, 48/48, 실패·skip 0, 테스트 본문 40.669초 |
| 재빌드 Office 엔진의 같은 회귀 | 별도 소스·호스트, 48/48, 실패·skip 0, 44.306초 |
| generic Simulator | arm64·x86_64 빌드 통과 |
| generic iOS | 서명 없이 빌드 통과. 실기기 실행을 뜻하지 않음 |
| 새 버전 소비자 | 로컬 mirror의 임시 SemVer로 커밋 소스를 설치, 공개 의존성 자산의 새 다운로드·체크섬 검증·generic Simulator public API 빌드 통과 |
| SwiftLint | Homebrew 및 공식 portable 0.65.1로 각각 strict 53파일·위반 0건 |
| 원래 바이너리 | 두 아카이브의 기존 SHA-256 유지 |
| 재빌드 | 공식 도구를 별도 prefix에 설치, offline·2 jobs, 3타깃·XCFramework·고지 생성 전체 179.91초, exit 0 |
| CI 명령 | YAML/모든 shell 문법, 실제 Xcode·Simulator 선택, 고정 portable 자산 해시·버전·lint, 소비자 스크립트 검증 |

48개 실행과 65문서 대조에서 기존 QoS 경고는 관측하지 않았다. 모든 환경에서 경고가 발생하지 않는다는 보장은 아니다. Vision 취소 시험은 진입 표식 뒤 30ms에 취소하고 이미 완료했으면 skip하도록 했으며, 이번 실행은 skip 없이 통과했다. native 내부 진입 시점을 직접 trace한 검사는 아니고 프레임워크의 일정 시간 내 강제 중단을 보장하지 않는다.

추가 진단 도중 테스트의 필수 인자·import 누락과 ZIP 도우미의 Swift.zip 이름 충돌을 발견해 고쳤다. 실패 로그도 삭제하지 않고 최종 성공과 구분해 보존했다. 새 소비자 첫 실행은 macOS Keychain 승인 대기를 스택으로 확인해 해당 프로세스만 종료했다. 공개 의존성의 비대화형 검증에는 `-packageAuthorizationProvider netrc`를 사용하며 키체인·계정 설정은 바꾸지 않는다.

## 65문서 결과 대조

- 기존 블록 내용·위치·신뢰도·원래 OCR 텍스트가 정확히 같은 문서는 62/65다.
- JSON 1건은 의도한 true/false 보존 변화다.
- HWP·HWPX 2건은 기존 66개 블록을 그대로 유지하며 각 1개를 추가했다. 상세 전후 JSON과 원본 내장 그림을 직접 확인해 로켓 몸통에 인쇄된 세로 한글 한 줄의 정상 추가 인식임을 확인했다. 이에 대한 두 형식 회귀도 넣었다.
- 경고 payload는 65/65 동일하다. PNG·메타데이터는 64/65 바이트 동일하다. baseball PNG 1건은 반복 생성에서 컨테이너 바이트가 변하지만 픽셀·방향·위치·텍스트가 같음을 별도로 확인했다.
- 비동기 API 기본값의 차이도 실제로 찾았다. VN 요청의 최소 높이는 0, Swift 요청의 기본값은 1/32여서 초기 PDF·회전 PNG 결과가 달랐다. 0을 명시한 뒤 이 두 문서는 내용·좌표·신뢰도까지 원래 값으로 돌아왔다.

위 비교는 해당 65개 샘플의 회귀 근거다. 임의 문서 전체의 인식·조판 동등성을 보장하는 검사는 아니다. 일반·스캔·혼합 PDF와 한영 생성 스캔은 제품 회귀에 계속 포함한다.

## 성능과 메모리

Rust 컴파일과 다른 검증을 마친 뒤 같은 Mac mini에서 기존→수정 코드를 연속 실행했다. iPhone 17 / iOS 27.0 Simulator, Debug, 조건별 warm-up 1회 제외 후 3회다. 41,936바이트 스캔 PDF와 JPEG·DOCX의 혼합 입력을 사용했다. 같은 하네스·결과 순서·텍스트 해시·블록/그림/경고 수를 확인했다. 오래 전 baseline과 비교한 초기 측정도 보존하되 아래는 추가 연속 측정이다.

| 조건 | 중앙값 초: 기존 → 수정 | 3회 중 최대 표본 프로세스 MiB: 기존 → 수정 |
| --- | ---: | ---: |
| 스캔 PDF OCR | 0.793 → 0.846 | 104.5 → 103.9 |
| 스캔 PDF PNG+OCR | 0.823 → 0.886 | 105.9 → 103.7 |
| 혼합 3문서, 동시성 1 | 1.658 → 1.744 | 135.0 → 138.3 |
| 혼합 3문서, 동시성 2 | 1.648 → 1.102 | 153.7 → 206.4 |

병렬 배치는 빨라졌지만 표본 최대 메모리는 늘었다. 단독 OCR·직렬 조건의 지연도 소폭 늘었으므로 모든 조건에서 속도·메모리가 개선됐다고 주장하지 않는다. 혼합 병렬 반복 직전 프로세스 메모리 중앙값은 100.5→28.3MiB로 낮아졌다. 유휴 상태와 실행 중 최고치를 구분해야 한다. 기존 동시성 기본값 2는 유지하며 결과 PNG가 필요 없으면 extractImages=false, 낮은 실행 메모리가 우선이면 maximumConcurrentDocuments=1을 명시할 수 있다.

메모리는 테스트 호스트의 phys_footprint를 20ms마다 샘플링한 값으로 파서 순수 할당·OS 절대 최고치가 아니다. 다른 Simulator는 켜져 있고 고정 순서의 짧은 샘플이므로 호스트 부하·캐시 편향이 남는다. OCR을 끈 스캔 PDF는 빈 결과여서 그 짧은 시간을 내용 추출 속도로 세지 않았다. 실기기·Release·대용량의 동일 발열 반복 검증은 별개다.

## 바이너리와 라이선스

기존 Git 바이너리·라이선스 원문은 변경하지 않았다. [제작 절차](../ThirdParty/OfficeOxide/README.md)로 새 검토 번들을 저장소 밖에서 만들었다. 고지 출처 그룹 81개, 실제 타깃별 compiler-artifact ID 57·57·58개를 대응해 미확인 ID 0개를 확인했고, 세 슬라이스의 C office_* 정의 심볼 43개와 헤더 필수 심볼도 일치했다. 새 바이너리는 별도 호스트에서 48개 회귀를 통과했다.

기존 배포물과는 LLVM 제작 버전·경로가 달라 해시가 다르다. 새 두 빌드도 root object의 embedded LLVM IR 표현 차이가 있어 다른 루트의 바이트 동일성을 보장하지 않는다. machine code 대조와 의미가 같은 PHI 순서 차이의 분석 범위, 동일 절대 입력의 통제 반복 미실시는 [배포 검증](DISTRIBUTION_VERIFICATION.md)에 구분했다. 감사 가능한 재빌드, 샘플 기능 회귀, 비트 단위 재현, 소비 앱의 실제 링크 SBOM은 서로 다른 확인이다.

자체 코드는 MIT, 외부 의존성은 원래 조건을 따른다. [라이선스 검토](LICENSE_REVIEW.md)의 MPL·LGPL·전이 조건과 남은 실제 링크 대조 범위도 유지한다. 새 검토 번들의 존재로 현재 배포물 또는 모든 소비 앱의 조건 이행이 완료됐다고 표시하지 않는다.

## 실행 명령과 기록

```bash
xcodebuild test -scheme OmniParser \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -skipMacroValidation -packageAuthorizationProvider netrc \
  -parallel-testing-enabled NO -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO
xcodebuild build -scheme OmniParser -destination 'generic/platform=iOS Simulator' \
  -skipMacroValidation -packageAuthorizationProvider netrc CODE_SIGNING_ALLOWED=NO
xcodebuild build -scheme OmniParser -destination 'generic/platform=iOS' \
  -skipMacroValidation -packageAuthorizationProvider netrc CODE_SIGNING_ALLOWED=NO
swiftlint lint --strict
bash .github/verify-consumer.sh /새로운/OmniParserConsumer
bash ThirdParty/OfficeOxide/build.sh --verify
```

기존 캐시·고정 리비전만 사용하는 실제 명령에는 jobs 4, derivedDataPath, clonedSourcePackagesDirPath, disableAutomaticPackageResolution, skipPackageUpdates, onlyUsePackageVersionsFromResolvedFile도 지정했다. 새 소비자만은 의도적으로 새 캐시에서 해석·다운로드를 수행했다. 도구 구성·실행 출처는 배포 문서를 참고한다.

로컬 원시 기록은 `~/Developer/Codex/OmniParserVerification/2026-10-27/OpenSourceFixes-223719/`에 보존했다. regression-48-final, build-48-simulator, build-48-device-unsigned, consumer-build-v2, RebuiltBinaryHost-v2/Results, corpus-comparison-v4.json, detail-comparison.json, performance-paired-comparison.json, SwiftLintPortable/verification.json, CIChecks, RustRebuild/VerifiedBundle/BUILD_MANIFEST.json 및 재현성 분석이 근거다. 본문·OCR 원문은 제품 로그에 추가하지 않았고 공개 샘플의 상세 대조도 로컬 진단 JSON으로 분리했다. 새 바이너리·원시 로그·개인 도구 체인은 Git에 추가하지 않았다.

## 남은 확인

- 최신 코드의 실기기·Release·동일 발열 대용량 반복 측정. 이전 32개 실기기 결과와 구분한다.
- 실제 GitHub-hosted CI 실행과 수정 공개 버전 설치. 현재 변경은 로컬 커밋이며 기존 alpha.1 태그는 그대로다.
- 새 바이너리의 배포 채택, 실제 링크 오브젝트 전체의 고지 대조, 엄격한 동일 입력의 바이트 재현 검증.
- 병렬 메모리 증가의 추가 프로파일과 목표 선택. 측정값을 숨기거나 기존 API 기본값을 임의 변경하지 않았다.

선택 제품·스트리밍 결과·결과 불변화는 공개 API 설계 결정이다. 이번에는 기존 전체 형식·호출 계약을 유지했고, 배치 결과 누적 메모리와 호출 측 결과 변경의 제약을 API 문서에 명시했다. CI는 공식 표준 hosted Xcode 27로 구성했으며 아직 푸시하지 않아 클라우드 실행 결과는 없다.
