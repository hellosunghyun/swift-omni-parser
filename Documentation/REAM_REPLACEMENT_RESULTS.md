# Ream Office 교체 구현 및 검증 결과

> 개인 절대 경로는 [로컬 검증 경로 별칭](RESEARCH_PATHS.md)으로 표기했다. 원시 로그·진단 덤프는 저장소에 포함하지 않는다.

> 후속 작업: [운영 회귀 테스트 반영](REGRESSION_TESTS.md), [Ream/OdrCore XLS 수정 검증](ODR_XLS_FIX_VALIDATION.md). 아래는 이전 단계 기록이며, Ream 수정 후 기존 앱 크기·성능을 다시 측정한 결과는 아닙니다.

2026-10-26. Draft 실험. 기존 OfficeOxide/OdrCore를 제거한 별도 패키지와 소비 앱을 실제 빌드했다. 기본 저장소의 운영 Sources/Package.swift는 변경하지 않았다. 현재 결과는 앱 크기 절감의 근거이며, 전체 문서에서의 기능 동등성이나 생산 교체 승인을 뜻하지 않는다.

## 이번 요청의 네 가지 작업

| 작업 | 구현·실행 결과 | 남은 한계 |
|---|---|---|
| 구형 PPT 표 보완 | 명시적 OfficeArt 표의 행/열 경계, 빈 셀, 가로·세로 병합 span, 좌표를 보존. 표 위 그림을 셀 그리드와 분리. 자체 생성 fixture 통과 | 임의 도형 그룹을 표로 추정하지 않음. 중첩·복잡한 모든 PPT 레이아웃의 정답 비교는 미완료 |
| 취소·자원 제한 | JS 함수/루프 체크포인트, Swift Task 취소, 명시적 배열 할당 누적 예산, 실제 ZIP 해제 바이트·CRC·경로 검사, DTD/ENTITY 거부. 배치당 최대 2개 JSContext 재사용 | 협력적 제한이다. JS 내장 연산 중 즉시 중단, 전체 JS heap/프로세스 RSS 강제 상한은 보장하지 않음 |
| 실제 API 통합 | 교체 패키지의 DocumentParser.parse/parseBatch에 연결. 혼합 형식·실패·진행 이벤트·입력 순서·중간 취소 테스트 통과 | URL security scope/임시 파일 수명은 기존 코드를 유지했으나 별도 수명 계측은 하지 않음 |
| 기존 엔진 제거 앱 | Release iOS arm64 소비 앱에서 OfficeOxide/OdrCore 제거. 비Office 구현과 Vision OCR 경로는 유지 | unsigned generic iOS 빌드다. App Store 다운로드/설치 크기, 실기기 실행 결과가 아님 |

## 소비 앱 용량

같은 작은 UIKit 앱에 공개 parse API를 연결해 이미지/OCR 경로까지 링크했다. iOS 27.0, Swift 언어 모드 5.0, Release, arm64, dead stripping, 서명 없음. 파일 논리 바이트 합계이며 파일시스템 할당량이 아니다. 테스트 샘플은 앱에 포함하지 않았다.

| 구성 | 전체 .app | 빈 앱 대비 증가 | 비교 |
|---|---:|---:|---|
| 빈 앱 | 0.081 MiB | — | 85,137 bytes |
| 기존 OfficeOxide + OdrCore | 16.132 MiB | 16.051 MiB | 16,915,925 bytes |
| Ream 교체 + 기존 비Office 기능 | 8.332 MiB | 8.251 MiB | 8,736,698 bytes |

파서로 인한 증가량은 **48.60% 감소**, 약 7.80 MiB 절감했다. 새 앱의 OdrCore framework 파일, OdrCore 동적 링크, office_document_open/office_document_to_ir_json 공개 심볼이 없는 것을 확인했다. 시스템 libc++ 연결 자체를 기존 Office 엔진 잔존으로 해석하지 않았다.

새 앱에는 697,909-byte 계측 JS, 1,842-byte guard, 9,962-byte 외부 고지가 포함된다. 일반 ZIP은 참고용으로 기존 6,583,038 bytes, 새 앱 2,828,848 bytes다. 이 수치를 App Store 압축 다운로드 크기로 제시하지 않는다.

## 시간·메모리

컴파일이 끝난 뒤 iPhone 17 **Simulator** iOS 27.0에서 Release test-without-building을 기존/교체 번갈아 3회 실행했다. 같은 DOC/XLS/PPT 자체 샘플 3개를 배치로 5회 처리한다. 총 15문서, 요청 동시성 3, 이미지 true/OCR false. 교체안은 JSContext를 최대 2개로 제한한다. 작은 샘플에서의 측정이며 논문·대용량 스캔 결과가 아니다.

| 지표 | 기존 | Ream 교체 |
|---|---:|---:|
| 처리시간 중앙값 | 0.0534초 | 0.6140초 |
| 처리시간 범위 | 0.0526–0.1448초 | 0.4713–0.6470초 |
| 최대 관찰 RSS 중앙값 | 169.16 MiB | 274.33 MiB |
| 최대 관찰 RSS 범위 | 169.11–169.20 MiB | 269.75–275.88 MiB |

이 샘플에서 교체안은 **약 11.5배 느리고**, 프로세스 최대 관찰 RSS는 **약 105.17 MiB 증가**했다. 각 프로세스 시작 RSS도 원시 JSON에 기록했다. 기존 약 150.5 MiB, 교체 약 148.7 MiB다. RSS는 5ms 주기 task_info 샘플링이며 phys_footprint, 정확한 할당 최고점, 누수 판정이 아니다. XCTest 러너·시뮬레이터 프레임워크 비용도 포함된다.

매 문서 본문 마커와 그림 1개를 assertion으로 확인했다. 이 성능 테스트가 전체 Office 결과 fingerprint의 동등성을 검증하는 것은 아니다. CPU/메모리를 공유하는 다른 빌드는 측정 중 실행하지 않았다. 최초 실행과 OS/JS 캐시의 차이는 범위에 포함되어 있으므로 다른 문서로 수치를 일반화하지 않는다.

## 기능 검증

- iOS XCTest **13개 PASS**. 공개 API Office corpus 21문서/확인 문구 26개, PPT 병합·빈 셀·그림 셀, XLSX 날짜·백분율·불리언·한글·병합 위치, 혼합 배치 순서/실패/진행 이벤트, 파싱 중·배치 취소, 이미지 오류 뒤 본문·표 보존, 4가지 이미지/OCR 옵션, OCR 신뢰도, UTF-8/TypedArray offset/EUC-KR/windows-949를 포함한다.
- Ream PPT 기존·추가 테스트 **99개 PASS**, src TypeScript 타입 검사 PASS.
- SwiftLint strict **47파일, 위반 0**.
- 비Office 기존 문서 **42개**: HWP/HWPX/PDF/JPEG/PNG/HEIC/TIFF/TXT/CSV/JSON/XML/RTF/HTML/Markdown 각 3개. 입력 SHA-256을 확인하고 URL로 parse했다. 이미지 true/OCR false.
- 비Office 결과는 전체 텍스트·블록 종류/내용/순서/위치·이미지 방향/위치·경고 코드/위치를 비교했다. **42/42 의미 fingerprint 일치**. PNG 1개의 iCCP 메타데이터로 이미지 바이트 해시가 달라 **원시 fingerprint는 41/42**다. 동일 sRGB RGBA 픽셀·그 외 PNG chunk를 확인해 구분했다. 경고 메시지 문장과 OCR 신뢰도 전체 비교는 이 fingerprint 범위에 포함하지 않는다.
- 위험 입력: 실제 해제량이 선언 크기보다 큰 ZIP, 경로 탈출, 암호화 패키지, XML entity 선언, 매우 작은 작업/할당 예산의 거부를 확인했다. 전체 공격 표면에 대한 보안 감사로 간주하지 않는다.
- 추가 샘플은 기존 자체 그림/테스트 빌더로 생성했다. 새 외부 문서 다운로드는 하지 않았다.

Office corpus는 확인 문구·선택 구조 assertion 기반이다. Word 전체 문단/표/그림 위치, 모든 XLS 수식/서식, 모든 슬라이드 도형/노트와 픽셀의 원본 정답을 완전히 검증하지 않았다. 한영 혼합 OCR·회전·스캔 PDF의 전수 재검증과 실기기 대용량 테스트도 이번 실행에서는 **NOT_RUN**이다. 연결된 실기기가 available 상태가 아니어서 Simulator로 실행했다.

## 코드량과 라이선스

운영 Swift Sources는 42파일 4,219줄, 별도 교체안은 43파일 4,298줄로 **79줄 증가**했다. 주석/빈 줄 포함, 테스트/생성 JS 제외다. native 연결 코드를 지운 대신 codec·취소·ZIP 경계·자원 제한·컨텍스트 수명 코드가 추가됐다. Ream upstream 패치/빌드 계측도 별도로 관리해야 하므로 자체 유지보수량 감소를 입증하지 못했다.

자체 Swift는 MIT를 유지하고 Ream과 번들 전이 의존성 고지를 resource에 담았다. HWP용 CoreHwp의 LGPL 등 기존 의무는 남는다. 전체 제품을 제약 없는 MIT 단일 라이선스로 재표기하지 않는다. 배포 시 LGPL 재링크/소스 제공 등의 충족 방식과 전체 전이 의무는 별도 검토해야 한다. OfficeOxide/OdrCore용 고지를 제거한 실험 THIRD_PARTY_NOTICES.md도 작성했지만, 이는 법률 검토나 배포 준수 완료 선언이 아니다.

## 산출물과 재현

연구 루트: `${OMNI_RESEARCH_ROOT}`.

- `ReamReplacement/`: 실제 교체 SwiftPM 패키지·API·회귀 테스트.
- `ReplacementConsumer/`: 교체 패키지만 연결한 Xcode 소비 앱.
- `reamkit/`: 고정 upstream 소스, Office JSON 어댑터, PPT 패치, 계측 빌드 단계와 자체 fixture 생성기.
- `SameCorpusComparison/ream-replacement.patch`: 추적된 upstream 변경. 새 어댑터/계측/테스트 파일은 reamkit에 별도 보존돼 있으므로 이 패치만으로 재현되지 않는다.
- `replacement-tests.log`, `replacement-ppt-tests.log`, `replacement-typecheck.log`, `replacement-swiftlint.log`: 기능·린트 근거.
- `nonoffice-comparison.json`: 42개 전후 fingerprint 비교.
- `release-batch-summary.json`, `release-batch-*-*.log`: 3회 원시 측정과 요약.
- `replacement-app-sizes.json`, `replacement-linked-libraries.txt`, `replacement-exported-symbols.txt`: 앱 구성·바이트·엔진 제거 증거.

```bash
# 기존 캐시·부팅된 Simulator가 있는 이 Mac에서 재현
bash ${OMNI_RESEARCH_ROOT}/SameCorpusComparison/reproduce-ream-replacement.sh

# 기존/교체 Release build-for-testing을 각각 먼저 완료한 뒤 실행
python3 ${OMNI_RESEARCH_ROOT}/SameCorpusComparison/benchmark-replacement.py
python3 ${OMNI_RESEARCH_ROOT}/SameCorpusComparison/measure-replacement-size.py
```

Release build-for-testing은 각 패키지 루트에서 실행한다. 기존은 OmniProbe/ReleaseBaselineTestData/SourcePackagesOriginal, 교체는 ReamReplacement/ReleaseReplacementTestData/SourcePackagesReam을 사용한다.

```bash
xcodebuild build-for-testing -scheme OmniParser -configuration Release   -destination 'platform=iOS Simulator,id=46BECA1F-89C4-42E2-B9DD-5F6CB316E62B'   -derivedDataPath ../ReleaseReplacementTestData   -clonedSourcePackagesDirPath ${OMNI_CACHE_ROOT}/SourcePackagesReam   -skipMacroValidation -enableCodeCoverage NO ENABLE_TESTABILITY=YES CODE_SIGNING_ALLOWED=NO
```

의존성 캐시는 두 구성을 분리했다. 공유 캐시에서 SPM이 사용하지 않는 바이너리를 정리해 기존 빌드가 실패한 뒤, 기존 로컬 ZIP과 고정 체크섬으로 OdrCore 캐시를 복구했다. 이 캐시 실패는 파서 회귀로 집계하지 않는다. Swift tools 6.2/컴파일러 6.4/언어 모드 5.0을 구분한다.

## 판단

앱 크기 절감은 확인했지만 속도·RSS·자체 코드량은 악화됐다. 따라서 현재는 **운영 기본 엔진 유지**, Ream은 작은 배포 크기가 중요한 경우의 별도 후보로 보존한다. 기본 저장소의 의존성 교체·커밋·푸시는 하지 않았다. 미검증 기능을 경고만 추가해 완료로 처리하지 않는다.
