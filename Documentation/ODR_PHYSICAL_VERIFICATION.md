# 수정 OdrCore의 iPhone 17 실기기 검증

> 아래는 로컬 수정 엔진을 처음 실기기에서 검증한 이력이다. 현재 기본 의존성과 RTF 보완까지 포함한 34개 결과는 [최종 검증](COMPLETION_VERIFICATION.md)을 따른다.

2026-10-27. **iPhone 17 / iOS 27.0.1 실기기에서 전체 16개 XCTest 통과, 실패·skip·expected failure 모두 0개**다. 이 결과는 로컬 수정 XCFramework 소비 구성에 해당한다. 운영 upstream 7.5.2 의존성을 전환한 결과가 아니다.

## 실행 구성

- Xcode 27.1, iOS 27.1 SDK, Debug, arm64.
- OmniParser의 Sources/Tests는 운영 저장소와 Swift 파일 바이트 비교 후 실행했다. 기존 65문서와 생성 샘플을 사용했으며 새 외부 문서는 다운로드하지 않았다.
- `PatchedOmniProbe`에서 OdrCore만 인접 `OdrNativeRebuild` 경로로 연결했다. `ODR_XCFRAMEWORK=OdrCoreObjC.xcframework`로 [재빌드 산출물](ODR_NATIVE_BUILD_MANIFEST.json)을 지정했다.
- Swift Package의 기본 테스트 타깃은 실기기에서 tool-hosted testing을 지원하지 않아 처음 실행은 테스트 시작 전에 실패했다. 이후 **저장소 밖의 임시 호스트 앱**에 같은 테스트를 연결해 실행했다.
- 호스트는 작은 SwiftUI 앱, 테스트 타깃은 호스트와 OmniParser 제품을 의존성으로 갖는다. Fixtures를 folder resource로 복사하고, 테스트 전용 `Bundle.module` 어댑터만 별도 추가했다. 제품·기존 테스트 소스는 수정하지 않았다.
- 개발 팀은 xcodebuild 명령에만 전달했다. 저장소에 팀·프로비저닝 설정을 기록하지 않았다.

호스트 XCTest 타깃의 번들 어댑터는 다음과 같다. SwiftPM 테스트에는 추가하지 않는다.

```swift
import Foundation

extension Bundle {
  static var module: Bundle { Bundle(for: APIContractTests.self) }
}
```

## 결과

| 검사 | 결과 |
|---|---|
| 기존 corpus 해시·기대값·본문/표/그림/OCR | PASS |
| XLS 중첩 차트 캐시와 실제 셀 값 | PASS |
| 단일/배치 오류 정규화·결과 순서·진행 이벤트 | PASS |
| 이미지/OCR 옵션 네 조합·기본값 | PASS |
| 다중 프레임 TIFF·일반/스캔/혼합 PDF | PASS |
| 입력 제한·경로 탈출·inflate 한도 단위 검사 | PASS |
| 부분 그림 실패·취소·임시 파일 정리 | PASS |
| 전체 | **16/16 PASS**, 테스트 본문 실행 합계 4.652초 |

4.652초는 여러 검사를 묶은 Debug XCTest 실행 시간이다. 단일 문서의 지연 시간, 대용량 성능, Release 개선율이나 최대 메모리 측정값으로 사용하지 않는다. `.xcresult`의 기기 모델·플랫폼·OS와 결과를 별도로 조회해 Simulator 실행과 구분했다.

빌드 로그의 ProcessXCFramework 경로는 `OdrNativeRebuild/OdrCoreObjC.xcframework`다. 원본 기기 슬라이스와 실제 앱 안의 framework는 같은 Mach-O UUID `71C16C2A-9277-31A6-8F50-55100602B774`다. 앱에 서명된 바이너리의 전체 파일 hash는 원본과 달라질 수 있어 ZIP checksum과 구분한다.

## 실제 명령과 로컬 증거

아래 호스트 프로젝트와 원시 로그는 로컬 검증 폴더에 있다. 공개 패키지의 새 테스트 scheme이나 자동 CI로 추가한 것은 아니다. 경로 별칭은 [연구 경로 안내](RESEARCH_PATHS.md)를 따른다.

```bash
# ${OMNI_RESEARCH_ROOT}/OdrPhysicalHost에서 실행
ODR_XCFRAMEWORK=OdrCoreObjC.xcframework xcodebuild test \
  -project OdrPhysicalHost.xcodeproj -scheme VerificationHost \
  -destination "platform=iOS,id=$OMNI_DEVICE_UDID" -destination-timeout 30 \
  -derivedDataPath ../PatchedPhysicalHostDerivedData \
  -clonedSourcePackagesDirPath "$OMNI_CACHE_ROOT/SourcePackagesPatched" \
  -skipMacroValidation -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath ../OfficeContractAudit/patched-host-physical-20261027.xcresult \
  DEVELOPMENT_TEAM="$OMNI_DEVELOPMENT_TEAM" CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates

xcrun xcresulttool get test-results summary \
  --path ../OfficeContractAudit/patched-host-physical-20261027.xcresult --compact
```

- `OfficeContractAudit/package-patched-physical-device-20261027.log`: 첫 호스트 없는 실행의 실패 기록.
- `OfficeContractAudit/package-patched-host-physical-20261027.log`: 호스트를 사용한 실행, exit 0 / TEST SUCCEEDED.
- `OfficeContractAudit/patched-host-physical-20261027.xcresult`: 실기기 테스트 16개의 결과.
- `OdrPhysicalHost/project.yml`: XcodeGen으로 생성한 로컬 검증 호스트 구성.

## 남은 확인

xcresult에 User-initiated 스레드가 Default QoS 스레드를 기다리는 우선순위 역전 경고가 1건 있었다. 위치는 corpus 테스트지만 원인 스레드와 해당 라이브러리는 이번 결과만으로 특정할 수 없다. 테스트는 성공했으나 성능상 확인할 사항으로 남긴다. 설정만 바꿔 경고를 없애거나 성능 개선이 완료됐다고 표시하지 않는다.

대용량 PDF·최대 메모리·장시간 연속 처리·배포용 Release 구성·App Store 심사·공개 URL의 클린 설치는 이번 실행의 검증 대상이 아니다. 운영 의존성 전환은 [준비한 변경안](ODR_MIGRATION_PREPARATION.md)으로 구분했다.
