# OdrCore 운영 의존성 전환 준비

> 후속 상태: 2026-10-27 사용자 승인 후 포크 Release를 공개하고 기본 의존성 전환을 진행했다. 아래는 전환 전 기록이며 현재 결과는 [XLS 수정·전환 검증](XLS_CHART_FIX.md)을 따른다.

2026-10-27. 운영 `Package.swift`는 아직 upstream 7.5.2다. 아래는 검토·적용을 위한 **미적용 패치 템플릿**이며, 공개 저장소나 Release를 생성한 결과가 아니다.

## 준비한 변경

| 적용할 저장소 | 템플릿 | 변경 |
|---|---|---|
| OmniParser | [Consumer 패치](OdrCore-Consumer-Migration.patch.in) | upstream exact 버전을 포크의 불변 커밋으로 변경. 제품 이름과 Swift 코드 유지 |
| OdrCore 포크 | [Wrapper 패치](OdrCore-Wrapper-Migration.patch.in) | ZIP URL·checksum 변경. 현재 빌드한 iOS 슬라이스만 플랫폼으로 선언 |

원래 Swift wrapper를 복사해 OmniParser 안에 별도 구현하지 않는다. 새 XCFramework를 OmniParser Git에도 추가하지 않는다. 포크 URL은 SwiftPM의 기존 `OpenDocument.core` identity를 유지하도록 저장소 이름이 `OpenDocument.core`인 URL을 사용한다. 다른 이름을 선택하면 product의 package 인자까지 함께 변경·검증해야 한다.

템플릿 변수는 실제 발행값이 확정된 뒤 치환한다.

- `__FORK_URL__`: 공개 포크 Git URL.
- `__FORK_COMMIT__`: 아래 wrapper 변경과 소스·고지가 들어 있는 40자리 커밋 SHA. branch 이름을 사용하지 않는다.
- `__ASSET_URL__`: 그 소스로 만든 XCFramework ZIP의 공개 HTTPS Release URL.
- `__ASSET_SHA256__`: 최종 ZIP에 `swift package compute-checksum`을 실행한 값.

현재 로컬 ZIP의 SHA는 `ce8d528523dcb4c475d4d55035782c49eda1a3c2d8258fc024f693d731eed566`이지만 번들 버전이 `0.0.0`인 검증용 산출물이다. 정식 버전으로 다시 빌드하면 **새 checksum을 사용**해야 한다. 검증용 checksum을 새 Release ZIP에 재사용하지 않는다.

## 적용 전 검증한 것

- 두 템플릿의 `git apply --check` 통과.
- 예약 도메인 `example.invalid`·가상 SHA로 임시 manifest를 생성해 `swift package dump-package` 통과. 이는 문법 검사이며 공개 URL의 접근성 검증이 아니다.
- Consumer는 iOS 27.0·언어 모드 5.0 유지, wrapper는 iOS 15.0 유지. iOS 전용 ZIP에 macOS 지원을 잘못 선언하지 않도록 macOS 항목을 제거했다.
- 검증용 ZIP checksum이 기존 build manifest와 일치.
- 기존 로컬 소비 구성에서 전체 16개 테스트 Simulator 통과에 이어 [iPhone 17 실기기도 통과](ODR_PHYSICAL_VERIFICATION.md).

운영 manifest나 Package.resolved에는 이 템플릿을 적용하지 않았다. 원격 ZIP 다운로드·원격 wrapper 소비는 아직 검증하지 않았다.

## 실제 전환 순서

1. 공개 포크·버전을 확정하고 upstream 기준 리비전, 두 native 패치, 빌드 프로필·전이 의존성 정보를 보존한다. 배포 대상은 현재 iOS 두 항목이다. macOS를 지원하려면 별도 슬라이스 빌드·검증이 필요하다.
2. `ODR_GIT_HEAD`에 확정한 릴리스 식별자를 지정해 세 아키텍처를 다시 빌드·조립한다. 번들 버전·식별자와 해당 소스가 일치하는지 확인한다. [기존 빌드 절차](ODR_NATIVE_REBUILD.md)를 따른다.
3. 최종 ZIP의 checksum을 계산하고 wrapper 템플릿을 치환한다. MPL 수정 소스 제공 안내와 네이티브 전이 의존성 고지를 실제 배포물에 대응시킨다.
4. wrapper 커밋과 Release ZIP을 공개한 뒤 Consumer 템플릿에 해당 Git URL·커밋을 넣는다. 적용 전 각 저장소에서 `git apply --check`를 다시 실행한다.
5. 새 SourcePackages·DerivedData에서 `ODR_XCFRAMEWORK`를 **설정하지 않고** resolve한다. Package.resolved의 포크 커밋, 실제 ZIP checksum, ProcessXCFramework 경로를 확인한다. 로컬 override 검증을 원격 설치 성공으로 간주하지 않는다.
6. 전체 Simulator 테스트, generic iOS/Simulator 빌드, 호스트 앱을 통한 실기기 테스트·SwiftLint를 실행한다. README·회귀 상태·라이선스 고지를 실제 설치 결과로 갱신한다.

공개 배포 전에는 기존 manifest를 유지한다. 전환 후 문제가 생기면 Consumer manifest와 Package.resolved를 함께 기존 upstream 고정값으로 되돌리고, XLS 정답 테스트가 다시 실패하는 기존 제약도 명시한다.

재빌드 ZIP 게시와 원격 의존성 전환은 이번 준비 작업에 포함하지 않았다. 현재 운영 구성의 기존 XLS 실패를 해결했다고 표시하지 않는다.
