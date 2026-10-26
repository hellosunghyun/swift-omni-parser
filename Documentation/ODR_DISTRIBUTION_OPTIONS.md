# 수정 OdrCore 배포 방식 비교

2026-10-26. XLS 수정 XCFramework를 로컬에서 빌드하고 iOS 소비 검증까지 수행했다. 이 문서는 배포 방식 추천이며 저장소 생성·Release 게시·운영 의존성 전환은 하지 않았다.

**장기적으로 upstream 고정 릴리스, 그 전에는 패치 소스와 Release ZIP을 제공하는 임시 포크를 권장한다.** 생성 바이너리를 OmniParser Git에 추가하는 방식은 피한다. 이는 이번 로컬 결과와 유지보수 비용을 기준으로 한 판단이다.

| 방식 | 기능·검증 | 소비자 설치와 저장소 영향 | 유지보수 | 판단 |
|---|---|---|---|---|
| upstream 수정 릴리스 고정 | 수정이 실제 포함된 버전을 재검증해야 함 | 현재처럼 Swift wrapper + 원격 binaryTarget | 가장 적음 | 장기 권장. 이번에 새 upstream 릴리스의 존재를 확인하거나 임의 버전을 지정하지 않음 |
| 임시 소스 포크 + Release ZIP | 이번 패치와 같은 소스·빌드·소비 테스트를 고정 가능 | Git에는 소스/패치/고지, 바이너리는 Release에서 내려받음 | 패치·빌드 환경·배포물 추적 필요 | 수정이 필요할 때의 권장 임시 경로. 실제 포크/게시 승인은 별도 |
| OmniParser에 XCFramework 직접 커밋 | 동작 검증 가능 | 새 네이티브 바이너리 약 23MiB와 이후 Git 이력 누적 | 배포는 단순하나 이력 비용 큼 | 바이너리를 최대한 Git에 넣지 않는 요청에 맞지 않음 |
| 소비자마다 C++ 소스 빌드 | 동일 소스라도 SDK·전이 라이브러리·프로필 검증 필요 | Conan/Python/CMake/Apple C++ 빌드 환경이 소비자에게 필요 | 설치·CI 비용과 실패 지점 증가 | 현재의 간단한 SwiftPM 설치를 대체하는 기본 방식으로 권장하지 않음 |
| 로컬 override로만 사용 | 이번 소비 테스트에 사용 | ODR_XCFRAMEWORK와 로컬 경로 의존성 필요 | 개인 검증에는 적합, 공개 설치에는 불충분 | 현재 상태. 일반 사용자의 재현 가능한 배포 방식은 아님 |

## 실제 로컬 산출물

- 기기 iOS arm64, Simulator arm64+x86_64의 두 XCFramework 항목.
- ZIP 9,003,328 bytes(약 8.59MiB), XCFramework 전체 약 23MiB. **앱 증가량이나 App Store 다운로드 크기가 아니다.**
- ZIP SHA-256: `ce8d528523dcb4c475d4d55035782c49eda1a3c2d8258fc024f693d731eed566`.
- [원본 커밋·패치·도구·슬라이스 manifest](ODR_NATIVE_BUILD_MANIFEST.json).

기존 OmniParser에는 OfficeOxide 바이너리도 들어 있다. OdrCore의 배포 방식을 바꾸는 것만으로 기존 OfficeOxide의 Git 이력이나 앱 바이너리 크기가 없어지지는 않는다. Release ZIP은 Git 이력의 바이너리 누적을 줄이는 방식이며 소비자의 실제 다운로드·링크 비용은 남는다.

## 권장 경로의 구체적인 내용

1. upstream 기준 커밋, 엔진 패치, 빌드 도구 조정과 전이 의존성 lock을 고정한다. 수정 소스는 원래 MPL-2.0과 고지를 유지한다.
2. 원래 OdrCore Swift wrapper와 binaryTarget 구성을 유지한 포크에서, 릴리스 ZIP URL·checksum을 같은 소스 리비전에 기록한다. OmniParser에는 Swift wrapper를 복사해 중복 유지하지 않는다.
3. ZIP 안의 XCFramework를 기준으로 기기 링크·Simulator 실행·기존 corpus를 확인한다. 번들 버전/소스 식별자를 발행할 버전으로 확정해 다시 생성하면 checksum도 다시 계산한다. 현재 로컬 테스트용 바이트를 정식 릴리스로 가장하지 않는다.
4. 수정 소스 취득 경로와 원래/전이 고지를 배포물에 대응시킨 뒤 공개 설치를 새 환경에서 검증한다.
5. upstream 고정 릴리스로 이전할 수 있을 때 동일 회귀를 실행하고 임시 포크 의존성을 제거한다.

Apple은 원격 binaryTarget 배포용 XCFramework ZIP과 checksum 기반 검증 방식을 안내한다. 원격 ZIP의 checksum과 버전은 함께 고정해야 한다. [Apple 배포 안내](https://developer.apple.com/documentation/Xcode/distributing-binary-frameworks-as-swift-packages), [binary dependency 확인](https://developer.apple.com/documentation/xcode/identifying-binary-dependencies).

MPL 파일을 수정해 실행 형태로 외부 배포하면 해당 소스의 제공·취득 안내 의무를 검토해야 한다. 자체 Swift가 MIT라는 사실이 외부 C++ 수정 소스나 전이 라이브러리의 조건을 바꾸지는 않는다. 이는 앱 전체 소스를 일괄 공개한다는 뜻과 다르다. [MPL 2.0 FAQ](https://www.mozilla.org/en-US/MPL/2.0/FAQ/), [MPL 원문 3절](https://www.mozilla.org/en-US/MPL/2.0/). 이번 로컬 검증은 모든 배포 의무나 App Store 심사를 완료한 선언이 아니다.

현재 운영 Package.swift는 기존 upstream 7.5.2를 유지한다. 따라서 기본 의존성의 XLS 정답 테스트는 여전히 실패하며, 수정 XCFramework를 연결한 별도 소비 검증은 16/16 통과했다. [전체 재빌드 및 소비 검증](ODR_NATIVE_REBUILD.md)을 참고한다.
