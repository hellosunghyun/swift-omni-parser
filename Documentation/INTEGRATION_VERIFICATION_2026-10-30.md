# 2026-10-30 통합 및 남은 RTF 기능 검증

## 통합 기준

원격 `33991ef`의 OCR·PDF·메모리·CI 개선을 유지하면서 별도 작업의 RTF 입력 보호와 부분 복구를 `1d4b872`에 통합했다. 기존 의존성 버전과 iOS 27.0·Swift 언어 모드 5·tools 6.2를 유지했다. OpenDocument.core는 버전 기반 소비자도 설치할 수 있도록 revision 대신 exact `7.5.2-omni.1`을 사용한다.

`COMPLETION_VERIFICATION.md`의 34개 검사는 통합 전 동기 OCR 구현의 과거 기록이다. 최신 비동기 OCR 구현의 실기기 검증으로 대체해서 읽으면 안 된다.

## 실제 실행

| 상태 | 대상 | 결과 |
|---|---|---|
| PASS | 통합 `1d4b872`, Release 전체 회귀 | iPhone 17 Simulator / iOS 27.0, **105/105**, 실패 0, XCTest 합계 58.910초 |
| PASS | 같은 통합 상태의 strict lint | 67파일, 위반 0 |
| PASS | RTF 헤더·푸터·중첩 표 후속 검사 | 텍스트·그림 위치·표 scope·중첩 경로 **4/4**, 0.073초 |
| PASS | RTF 후속 상태의 strict lint | 68파일, 위반 0 |
| PASS | RTF 후속 전체 Release 회귀 | **109/109**, 실패 0, XCTest 합계 56.477초 |
| PASS | RTF 후속 generic Simulator Release 빌드 | arm64·x86_64 |
| PASS | OLE 후속 검사 | **13/13**, 실패 0, XCTest 0.315초 |
| PASS | OLE 후속 strict lint | 71파일, 위반 0 |
| PASS | 최종 통합 전체 Release 회귀 (`3c3a8b9`) | **134/134**, 실패·skip·expected failure 0, XCTest 합계 71.217초, xcresult 런타임 경고 0 |
| PASS | 최종 strict lint | 74파일, 위반 0 |
| PASS | 최종 generic Simulator Release 빌드 | arm64·x86_64 |
| PASS | 최종 실기기 호스트 build-for-testing | iphoneos arm64, 서명 빌드 성공. 실제 실행 통과와 구분 |
| BLOCKED | 이번 변경의 iPhone 17 실행 | Sub 기기는 연결됐지만 잠금 상태. 과거 실기기 결과와 구분 |

Release 테스트는 `ENABLE_TESTABILITY=YES`가 필요하다. 이 설정을 빠뜨린 최초 실행은 모듈의 `-enable-testing` 불일치로 컴파일 실패했으며, 설정 후 전체 실행은 통과했다. 시간은 빌드·설치 대기를 제외한 XCTest 실행 시간이며 파싱 성능 비교값이 아니다.

```bash
xcodebuild test -scheme OmniParser -configuration Release \
  -destination 'platform=iOS Simulator,name=OmniParser-Finish-iPhone17' \
  -skipMacroValidation -parallel-testing-enabled NO \
  -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES
swiftlint lint --strict
```

원시 로그·xcresult는 제품에 넣지 않고 로컬 `~/Documents/Codex/OmniParserVerification/2026-10-30/`에 보관했다. 전체 실행은 `integrated-105-testable.log`와 동명 xcresult, RTF 후속 검사는 `rtf-completion-step1.log`, 후속 전체 실행은 `integrated-109.log`와 동명 xcresult, generic 빌드는 `integrated-generic-build.log`다.

최종 회귀에는 새 RTF 헤더·푸터/중첩 표 4개, OLE 13개, scanner 경계 3개, DIB 9개를 포함한다. DIB는 무압축 1·4·8·24·32비트를 지원하고 RTF pict·OLE native 경로에 연결했다. 옵션이 모두 꺼졌을 때 OLE DIB 비트맵을 만들지 않는 검사와 OLE 미리보기 fallback의 object 위치 보존도 포함했다. 새 의존성·외부 테스트 샘플·제품 바이너리를 추가하지 않았다.

최종 원시 증거는 `final-134-options-fixed.log`와 동명 xcresult, `final-lint.log`다. 최종 generic 로그는 `final-generic-build.log`, 실기기 테스트 빌드는 `final-device-build-retry.log`다. 처음 실기기 호스트 링크 실패는 새 HWP 회귀가 참조하는 CoreHwp 메타데이터를 호스트 테스트에 직접 연결해 해결했다. 이 변경은 저장소 밖 로컬 검증 프로젝트에만 적용했다. 테스트 Swift 25개는 저장소 원본과 바이트가 같고 Bundle.module 어댑터만 별도 추가했다. 팀 설정은 CLI에만 전달했고 저장소에 반영하지 않았다. `final-source-sha256.json`에 소스와 호스트 일치를 보관했다.

한영 OCR은 기존 회귀의 자체 생성 그림을 사용하며 WMF·EMF 연구 검사와 제품 지원은 구분한다.

## CI

통합 `1d4b872`의 [GitHub Actions 실행 40983613682](https://github.com/hellosunghyun/swift-omni-parser/actions/runs/40983613682)이 성공했다. 105/105 테스트(245.914초)·strict lint 67파일 위반 0·generic Simulator 빌드·버전 기반 소비자 빌드·OfficeOxide device/simulator 배포 체크섬 검사가 모두 성공했다. job 합계는 9분 12초였다. CI는 Debug, 앞선 로컬 검사는 Release이므로 두 실행 시간을 같은 성능 비교로 사용하지 않는다. 이 결과를 그 이후 RTF 기능 커밋의 CI 결과로 확대하지 않는다. 기존 workflow를 유지했고 runner·OS 요구사항을 낮추거나 검사를 생략하지 않았다.

## 공식 XLS 배포 상태

10월 30일 조회 기준 [upstream PR #1291](https://github.com/opendocument-app/OpenDocument.core/pull/1291)은 10월 28일 한국시간에 병합됐다. 최신 공식 [v7.6.1](https://github.com/opendocument-app/OpenDocument.core/releases/tag/v7.6.1)은 10월 25일 배포로, 수정이 포함되기 전이다. 수정된 바이너리의 공식 배포와 동일 회귀 검증 전에는 검증한 포크를 유지한다.

## 별도 검증 중인 범위

WMF·EMF는 외부 연구 공간에서 JavaScriptCore 변환과 detached WebKit PDF→PNG 경로를 시험했다. macOS의 실제 변환·한영 OCR 및 iOS SDK 타입체크 성공은 iPhone 실행 성공을 의미하지 않는다. iPhone 17 Simulator / iOS 27.0(SDK 27.1)에서 연구 앱 4/4 검사도 통과했다. 기존 WMF 2개와 자체 생성 WMF·EMF의 도형 픽셀, 정적 SVG 한영 OCR을 확인했으며 실기기 실행은 잠금으로 차단됐다. 새 MIT 라이브러리의 제품 반영은 사용자 승인 후에만 진행한다. OLE1·CFB 내장 데이터 경로를 구현했고 13개 후속 검사를 통과했다. 첫 실행의 1개 실패는 생성 샘플에 기대 문구가 빠진 문제였다. 독립 검토로 발견한 누적 objdata 예산·미리보기 호환본 유실도 수정하고 회귀에 포함했다. OLE 로그는 `rtf-object-step3.log`다. 최종 전체 회귀는 위 표에 반영했으며 실기기 실행은 잠금 해제 후 별도로 확인해야 한다.
