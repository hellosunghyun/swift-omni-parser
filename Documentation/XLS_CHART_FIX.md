# XLS 차트 캐시 오류 수정과 기본 의존성 전환

2026-10-27. 기존 upstream 7.5.2의 실제 XLS 정답 테스트 실패를 재현하고, 수정 포크의 공개 배포물을 기본 의존성에 연결했다. **새 SourcePackages 캐시에서 공개 ZIP을 받은 구성으로 Simulator와 iPhone 17 실기기 모두 16/16 통과**했다. 로컬 ODR_XCFRAMEWORK override를 사용한 결과가 아니다.

## 원인

XLS의 Workbook 스트림에는 워크시트 BOF/EOF 안에 차트 BOF/EOF가 중첩될 수 있다. 기존 `parse_sheet`는 중첩을 구분하지 않았다.

1. 차트의 NUMBER 등 셀 모양 캐시 레코드를 실제 워크시트 셀처럼 등록해 같은 주소의 원본 값을 덮었다. 기존 실제 샘플의 A1:A3 문자열 정답 검사 3개가 실패했다.
2. 첫 EOF에서 종료하므로 차트 종료를 워크시트 종료로 잘못 해석했다. 차트 뒤의 워크시트 레코드도 놓칠 수 있었다.

Swift의 셀 좌표 변환이나 OCR 중복 문제는 아니었다. 2026-10-27 확인한 upstream v7.6.1과 main에도 같은 루프가 남아 있어 해당 버전으로만 올리는 방식은 적용하지 않았다.

## 수정

`parse_sheet`에서 BOF/EOF 깊이를 추적하고 워크시트 본래 깊이에서만 셀 레코드를 해석한다. 중첩 EOF 뒤에는 워크시트 처리를 계속한다. 원래 셀 값·읽기 순서·Swift 결과 API는 유지한다. 테스트 정답을 바꾸거나 실패를 skip하지 않았다.

- [공개 포크 Release](https://github.com/hellosunghyun/OpenDocument.core/releases/tag/v7.5.2-omni.1).
- [엔진 수정과 자체 중첩 회귀 테스트](https://github.com/hellosunghyun/OpenDocument.core/commit/32c655b5).
- OmniParser 고정 소스: `b302cc85311490676986a2b731971473ad21efac`.
- upstream 기준 소스: `77e2a0a6e4b33c33a5aee64551fcd0d7493c9101`.
- ZIP SHA-256: `c12eb737d85f01fb99404ee92734246e6882e2a7e881b023ee05284225a369ed`.
- ZIP 9,003,370 bytes. 이는 앱 크기 증가량이 아니다.
- native 버전 식별자 `v7.5.2-omni.1`, 숫자형 Apple 번들 버전 `7.5.2`.
- iOS arm64 / Simulator arm64+x86_64. 포크 manifest는 미빌드 macOS 지원을 선언하지 않는다.

OmniParser에서는 Package.swift와 Package.resolved로 포크 커밋을 고정했다. Swift 파서·기존 회귀 테스트·OfficeOxide·나머지 의존성·iOS 27.0·Swift 언어 모드 5.0은 바꾸지 않았다. 새 XCFramework를 OmniParser Git에 추가하지 않았다.

## 실제 검증

| 구성 | 결과 |
|---|---|
| 전환 전 upstream 7.5.2 XLS 정답 테스트 재실행 | FAIL 재현, exit 65 |
| 공개 Release ZIP 독립 다운로드 | checksum 일치 |
| 원격 포크 + 새 캐시 / iPhone 17 Simulator iOS 27.0 | **16/16 PASS**, skip·expected failure 0 |
| 같은 기본 의존성 / iPhone 17 iOS 27.0.1 실기기 | **16/16 PASS**, skip·expected failure 0 |
| 기기용 앱 빌드·서명·실행 | 실기기 호스트 테스트 과정에서 PASS |
| generic iOS Simulator 빌드 | PASS (arm64·x86_64) |
| SwiftLint strict | 위반 0건 / 50파일 |

검사에는 65개 기존 문서, XLS A1:A3 정답, 이미지/OCR 옵션, TIFF·PDF, 배치 순서, 오류 분류, 부분 실패, 취소·임시 파일 정리가 포함된다. 실기기는 기존 [호스트 앱 방식](ODR_PHYSICAL_VERIFICATION.md)을 사용하되 패키지 경로를 현재 OmniParser로 연결했다. 테스트 Swift 파일은 원본과 바이트 비교했다.

테스트 본문 실행 합계는 Simulator 66.925초, 실기기 4.580초다. 동시 빌드·OCR을 포함한 기능 검사 시간이므로 엔진 성능 개선율로 해석하지 않는다. OCR 세션 풀 관련 QoS 우선순위 역전 경고는 남아 있으며 이번 XLS 수정으로 해결했다고 표시하지 않는다.

## 재현과 증거

```bash
# OmniParser 루트. 로컬 native override를 제거해 공개 자산을 사용한다.
env -u ODR_XCFRAMEWORK xcodebuild test -scheme OmniParser \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipMacroValidation -parallel-testing-enabled NO -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=NO

env -u ODR_XCFRAMEWORK xcodebuild build -scheme OmniParser \
  -destination 'generic/platform=iOS Simulator' -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO

swiftlint lint --strict
```

실제 새 캐시는 `SourcePackagesForkRelease`와 `SourcePackagesForkDevice`로 분리했다. 두 로그의 ProcessXCFramework는 해당 캐시의 원격 artifact 경로다. 로컬 증거는 [연구 경로 별칭](RESEARCH_PATHS.md)의 `${OMNI_RESEARCH_ROOT}/OfficeContractAudit` 아래에 있다.

- `xls-baseline-recheck-20261027.log`: 전환 전 실패.
- `fork-release-simulator-20261027.log`와 같은 이름의 xcresult: 기본 패키지 전체 테스트.
- `fork-release-physical-20261027.log`와 같은 이름의 xcresult: 실기기 전체 테스트.
- `fork-release-generic-simulator-20261027.log`: generic Simulator 빌드.
- `xls-fix-swiftlint-20261027.log`: lint.

## 소스·고지와 남은 범위

원래 MPL-2.0과 전이 의존성 조건을 유지한다. Release에 원문 고지 ZIP·Conan 리비전 목록·build manifest·checksum 목록과 uchardet 0.0.8의 대응 소스를 공개했다. 상세 경로는 [서드파티 고지](../THIRD_PARTY_NOTICES.md)에 있다. 자체 MIT와 외부 라이선스를 구분한다.

추가한 native GoogleTest 자체 중첩 입력 검사는 소스에 포함했으나 native 전체 테스트 타깃은 실행하지 않았다. 실제 문서에 대한 소비자 XCTest는 위와 같이 실행했다. 대용량 최대 메모리·배포용 Release 앱·App Store 심사·모든 XLS 변종을 검증했다는 뜻은 아니다.
