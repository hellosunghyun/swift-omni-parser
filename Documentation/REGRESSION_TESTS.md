# 회귀 테스트 실행 및 현재 결과

> 후속 최종 상태: [32개 테스트·대용량·QoS 검증](LOCAL_REVIEW_2026-10-27.md). 아래는 각 작업 당시의 기록입니다.

> 최신 RTF·복구 보완 검증은 [후속 검증 기록](RTF_COMPLETION_VERIFICATION.md)을 참고하세요. 아래의 과거 실행 결과와 구분합니다.

현재 상태: 2026-10-27 공개 포크 Release를 기본 의존성에 연결한 전체 16개 테스트가 Simulator와 iPhone 17 실기기에서 통과했다. [XLS 수정·전환 결과](XLS_CHART_FIX.md)가 최신 기록이다. 아래는 upstream 7.5.2를 사용하던 전환 전 2026-10-26의 검증 기록이다.

2026-10-26. 운영 패키지에 XCTest 타깃 OmniParserTests를 추가했다. 제품·기존 엔진·런타임 의존성·iOS 27.0·Swift 언어 모드 5.0·tools 6.2는 유지한다. 테스트용 리소스는 소비 앱 제품에 포함하지 않는다.

## 구성과 실제 검증

| 영역 | 현재 검사 |
|---|---|
| API 계약 | URL/Data/CGImage 입력, fullText·readingOrder, 이미지/OCR 4조합·기본값, OCR 신뢰도, 배치 순서·개별 실패·진행·메인 액터 이탈 |
| 형식별 회귀 | 기존 고유 파일 65개: 형식별 실제 문서 60개 + 자체 Office/HWP 5개. 입력 해시·기대 문구·최소 텍스트/표/그림·기존 부분 정답과 위치/순서 검사. OCR 켜고 실행 |
| 자체 구조 | 병합/빈 셀/그림 셀 PPT·XLSX 서식 4파일의 해시·일관성·선택 위치/그림 assertion. 모든 병합 구조의 정답을 검증한 것은 아님 |
| TIFF·PDF | 직접 만든 다중 프레임 TIFF의 프레임 순서/방향, 일반·스캔·혼합 PDF의 본문/OCR/페이지 위치 |
| 제한·수명 | 입력 크기, 실제 inflate 출력과 경로 탈출, 그림 실패 뒤 본문·표 보존, 추출 도중 취소·종료 이벤트, Office 임시 디렉터리 정리 |
| XLS 원본 정답 | 중첩 차트 캐시가 실제 A1:A3를 대체하거나 같은 주소에 중복되지 않아야 함 |

기존 upstream 7.5.2를 사용하는 기본 구성은 전체 16개 XCTest 중 **15개 PASS, 1개 BASELINE_FAIL**이다. 실패는 OfficeSourceTruthTests의 A1:A3 원본 값 assertion 3개이며 고정 의존성 OdrCore 7.5.2의 알려진 XLS 차트 캐시 결함이다. 기본 xcodebuild test는 exit 65로 실패한다. 이 사실을 제외한 부분 실행만으로 전체 테스트 성공을 주장하지 않는다.

기대 문구 검사는 기존 앱의 부분 정답 방식을 이관했다. 그 검사의 공백/대소문자 처리는 실제 원본 전체의 완전 일치 판정이 아니다. 정확한 셀 정답은 별도 테스트로 검사한다. 문서 원문은 assertion 실패 메시지에 포함하지 않는다.

## 실행 명령

Xcode 27.1 / iOS 27.0 iPhone 17 Simulator에서 실행했다. 물리 기기 검증이 아니다. 자동 생성 scheme OmniParser를 xcodebuild -list로 확인했다.

```bash
xcodebuild test -scheme OmniParser \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipMacroValidation -parallel-testing-enabled NO -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build -scheme OmniParser \
  -destination 'generic/platform=iOS Simulator' -skipMacroValidation

swiftlint lint --strict
```

실제 로그는 로컬 `Library/Caches/OmniParser/Research/OfficeContractAudit/package-normalized-tests.log`와 `package-final-swiftlint.log`에 있다. 테스트는 별도 PackageRegressionDerivedData, 기존 엔진 캐시는 SourcePackagesOriginal을 사용했다. Ream 실험은 SourcePackagesReam으로 분리했다. 일반 사용자 설치에 이 절대 경로들이 필요한 것은 아니다.

실패 하나만 재현하려면 다음을 사용한다.

```bash
xcodebuild test -scheme OmniParser \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipMacroValidation -collect-test-diagnostics never \
  -only-testing:OmniParserTests/OfficeSourceTruthTests CODE_SIGNING_ALLOWED=NO
```

## 해결되지 않은 사항

- 단일 parse와 배치 개별 오류를 같은 공개 분류로 정규화했다. 손상 BIFF가 malformedDocument로 반환되고, 실패 진행 이벤트와 임시 파일 정리, 기존 오류 분류·취소가 유지되는지 검사했다.
- OdrCore 패치를 전체 iOS XCFramework로 재빌드하고 Swift 소비 구성에 연결해 **16/16 PASS**를 확인했다. 기기용 빌드도 통과했지만 물리 기기 실행은 아니다. 운영 의존성/배포 전환은 아직 하지 않아 기본 구성의 XLS 실패는 남는다. [재빌드 결과](ODR_NATIVE_REBUILD.md)와 [배포 방식 추천](ODR_DISTRIBUTION_OPTIONS.md)을 참고한다.
- Ream은 같은 문제를 실험 소스에서 수정했다. TypeScript 171개, 교체 패키지 XCTest 13개와 별도 실제 XLS 정답 XCTest 1개가 통과했다. Ream은 운영 의존성이 아니다.
- CI runner/워크플로는 추가하지 않았다. 현재 환경의 iOS 27 SDK/Simulator를 갖춘 runner 선택과 알려진 실패 해결이 선행돼야 한다.
- 실제 inflate 출력 검사는 내부 XML ArchiveReader 단위 검사다. OdrCore 전체 native ZIP 경로의 출력 상한을 입증한 것이 아니다.
- 압축/픽셀/동시성의 모든 공격 조합, OCR 중간·배치 중간 취소, 접근 권한 수명 전수 계측, 대용량·실기기 성능은 이 16개 테스트만으로 입증되지 않는다.
- 외부 샘플의 출처·고지와 원래 검토 한계는 Fixtures의 README/manifest를 함께 읽는다. 추가 다운로드나 원문 진단 파일의 공개 저장소 반입은 없다.

[11문서 원본 대조](OFFICE_DIFFERENCE_AUDIT.md), [OdrCore 수정 검증](ODR_XLS_FIX_VALIDATION.md), [테스트 자산 안내](../Tests/OmniParserTests/Fixtures/README.md)를 참고한다.
