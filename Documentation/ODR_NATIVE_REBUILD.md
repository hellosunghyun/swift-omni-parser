# OdrCore 패치 XCFramework 전체 재빌드

2026-10-26. 이전 host probe/오브젝트 컴파일에서 더 진행해 **실제 OdrCore·전이 라이브러리·Objective-C framework를 빌드하고 iOS Swift 소비를 검증**했다. 외부 UTF 변환을 바꾼 작은 host probe가 아니라 전체 native 빌드다. 바이너리는 Git에 추가하거나 외부 게시하지 않았다.

## 소스와 환경

- upstream OdrCore 7.5.2 기준 커밋 `77e2a0a6e4b33c33a5aee64551fcd0d7493c9101`.
- [엔진 수정](OdrCore-XLS-Chart-Stream.patch): worksheet/중첩 chart stream 구분.
- [로컬 빌드 도구 조정](OdrCore-Local-Build-Tools.patch): 실제 Apple clang 21 설정, 없는 ccache launcher 제거, 동시 native 컴파일 4개 제한. iOS 최소 슬라이스 15.0은 유지했다.
- Python 3.12.13, Conan 2.33.0, 주 빌드 CMake 4.3.3, Xcode 27.1, Apple clang 21.0.0. Conan의 빌드 도구 의존성으로 CMake 3.31.12도 사용했다.
- 소비 패키지는 iOS 27.0, Swift 언어 모드 5.0, tools 6.2를 유지했다.
- Conan HOME·도구 가상 환경·소스·SPM cache·DerivedData를 기존 기본 구성과 분리했다. 원래 SPM checkout/바이너리 캐시를 수정하지 않았다.

기본 Python 3.9로는 upstream build script의 타입 문법을 실행할 수 없어 3.12 환경으로 전환했다. upstream Conan 설정이 먼저 참조하는 백업 서버는 401을 반환해 공개 origin 경로로 다운로드했다. 검증용 build profile의 compiler 설정은 Xcode 27.1의 실제 clang 21로 맞췄다. 앱 OS/Swift 설정을 낮추거나 네이티브 의존성을 임의로 생략하지 않았다.

## 산출물·검증

| 항목 | 결과 |
|---|---|
| 기기 arm64 framework | 전체 native 빌드 PASS |
| Simulator arm64 framework | 전체 native 빌드 PASS |
| Simulator x86_64 framework | 전체 native 빌드 PASS |
| XCFramework 조립 | PASS. Mach-O 플랫폼·install name·headers/module map/plist 확인 포함 |
| 최종 XCFramework 연결 후 iPhone 17 Simulator | **16개 XCTest 전부 PASS**, 기존 XLS 원본 정답 포함 |
| 최종 XCFramework 기기용 generic iOS 소비 | 빌드 PASS, 서명 생략. 실기기 실행 아님 |
| 기존 고정 upstream 의존성 | 16개 중 15개 PASS, 기존 XLS 1개 BASELINE_FAIL |
| 오류 정규화 변경 | 단일/배치 같은 malformedDocument, 기존 unreadableInput·unsupportedFormat·크기·취소 유지 검사 PASS |

Simulator 검증은 실제 공개 Swift 파서·테스트 소스를 그대로 복사하고 OdrCore 의존성만 로컬 수정 wrapper로 연결했다. Sources/Tests의 Swift 파일은 운영 코드와 바이트 비교했다. ODR_XCFRAMEWORK로 최종 OdrCoreObjC.xcframework 경로를 지정했으며 build log의 ProcessXCFramework 경로도 확인했다. 테스트 실패를 skip/expected-failure로 숨기지 않았다.

이 아티팩트는 iOS용이다. upstream macOS slice 2개는 빌드하지 않았으며 현재 OmniParser 제품은 iOS 대상이다. 물리 iPhone 실행·App Store 배포 검증·전이 고지 전체 재감사는 이번에 하지 않았다. Release 빌드에서 debug symbols가 없다는 upstream dSYM 경고가 있어 symbolication 품질을 검증한 것으로도 표시하지 않는다.

## 재현 순서

다음은 새 검증 디렉터리에서 수행하는 명령이다. 연구 스크립트와 원시 로그 전체를 공개 저장소에 포함한 것은 아니지만, upstream 빌더와 이번 패치는 포함된 경로로 재구성할 수 있다. 공개 원본 코드와 Conan 의존성을 받으며 문서 테스트 자산은 다운로드하지 않는다.

```bash
# OmniParser 저장소 루트에서 시작. 기존 디렉터리를 덮어쓰지 않는 새 경로를 선택한다.
OMNI_SOURCE_ROOT="$PWD"
OMNI_RESEARCH_ROOT="${OMNI_RESEARCH_ROOT:-$HOME/Library/Caches/OmniParser/Research}"
python3.12 -m venv "$OMNI_RESEARCH_ROOT/OdrBuildTools312"
"$OMNI_RESEARCH_ROOT/OdrBuildTools312/bin/python" -m pip install conan==2.33.0

git clone https://github.com/opendocument-app/OpenDocument.core "$OMNI_RESEARCH_ROOT/OdrNativeRebuild"
git -C "$OMNI_RESEARCH_ROOT/OdrNativeRebuild" checkout 77e2a0a6e4b33c33a5aee64551fcd0d7493c9101
git -C "$OMNI_RESEARCH_ROOT/OdrNativeRebuild" apply "$OMNI_SOURCE_ROOT/Documentation/OdrCore-XLS-Chart-Stream.patch"
git -C "$OMNI_RESEARCH_ROOT/OdrNativeRebuild" apply "$OMNI_SOURCE_ROOT/Documentation/OdrCore-Local-Build-Tools.patch"

export CONAN_HOME="$OMNI_RESEARCH_ROOT/OdrConan"
cd "$OMNI_RESEARCH_ROOT/OdrNativeRebuild"
"$OMNI_RESEARCH_ROOT/OdrBuildTools312/bin/conan" config install .github/config/conan
# 새로 만든 격리 Conan HOME에서만 공개 원본 다운로드를 사용한다.
python3.12 - <<'PYCONFIG'
import os
from pathlib import Path
Path(os.environ["CONAN_HOME"], "global.conf").write_text('core.sources:download_urls=["origin"]\n')
PYCONFIG
```

Apple build profile은 소스와 Conan HOME에 같은 로컬 조정을 사용했다. 위 설정은 새로 만든 격리 디렉터리만 대상으로 하며 시스템/사용자의 기존 Conan 설정을 바꾸지 않는다.

```bash
for profile in apple-iossim-armv8 apple-ios-armv8 apple-iossim-x86_64; do
  python3.12 apple/build_xcframework.py \
    --conan "$OMNI_RESEARCH_ROOT/OdrBuildTools312/bin/conan" slice --profile "$profile"
done
python3.12 apple/build_xcframework.py assemble \
  --slice ios-arm64 --slice ios-arm64_x86_64-simulator
swift package compute-checksum OdrCoreObjC.xcframework.zip
```

실제 실행에서는 Simulator arm64를 먼저 만들고 나머지 두 아키텍처를 각각 4개 컴파일 작업으로 동시에 빌드했다. 위 루프는 순차 재현 예다.

## Swift 소비 검증 구성

별도 소비 패키지의 Sources/Tests/OfficeOxide 자산은 현재 OmniParser와 같게 두고, manifest에서 다음 두 부분만 바꿨다. 운영 manifest에는 적용하지 않았다.

```swift
.package(path: "../OdrNativeRebuild")
.product(name: "OdrCore", package: "OdrNativeRebuild")
```

```bash
# 별도 소비 패키지 루트에서. OdrNativeRebuild는 인접 디렉터리다.
ODR_XCFRAMEWORK=OdrCoreObjC.xcframework xcodebuild test \
  -scheme OmniParser -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipMacroValidation -parallel-testing-enabled NO -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=NO

ODR_XCFRAMEWORK=OdrCoreObjC.xcframework xcodebuild build \
  -scheme OmniParser -destination 'generic/platform=iOS' \
  -skipMacroValidation CODE_SIGNING_ALLOWED=NO
```

별도 소비 구성은 로컬 Research/PatchedOmniProbe, 결과는 OfficeContractAudit/package-patched-full-tests.log와 package-patched-device-build.log에 보관했다. 기존 upstream의 비교 로그는 package-normalized-tests.log다. 실제 ZIP hash·슬라이스별 hash·build version은 [manifest](ODR_NATIVE_BUILD_MANIFEST.json)에 있다. cache나 생성된 framework를 Git에 넣지 않았으며, 독립 설치를 위해 필요한 배포 결정은 [배포 방식 비교](ODR_DISTRIBUTION_OPTIONS.md)에 구분했다.
