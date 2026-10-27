# 기여 안내

현재 공개 프리릴리즈이며 지원 범위·API가 바뀔 수 있습니다. 형식·위치·오류 계약은 [README](README.md)와 [API](Documentation/API.md)를 먼저 확인해 주세요.

- iOS 27 SDK를 제공하는 Xcode, SwiftPM tools 6.2, Swift 언어 모드 5.0을 유지합니다.
- 변경한 동작을 드러내는 원본 정답 회귀를 추가하고 `swiftlint lint --strict`, README의 Simulator 테스트·일반 빌드를 실행합니다. 실패·미실행 항목은 원인을 적습니다.
- 샘플은 자체 생성하거나 재배포 조건·출처를 확인해야 합니다. 민감한 문서는 공개 이슈·PR·로그에 올리지 않습니다.
- 새 의존성, 공개 API 변경, 지원 형식 조정은 구현 전에 이슈에서 범위·라이선스·영향을 논의합니다.
- PR에는 문제의 입력 조건, 결과의 변화, 실행한 검증과 남은 제약을 적습니다. 관계없는 리팩터링·생성 바이너리는 분리합니다.

## CI와 릴리즈 확인

`.github/workflows/verification.yml`은 `main`에서 수동 실행하며 외부 PR 코드를 자동 실행하지 않습니다. `self-hosted`, `macOS`, `ARM64`, `omni-parser-ios27` 라벨이 붙은 신뢰 runner를 운영자가 별도로 준비해야 합니다. 격리된 작업 공간에 Xcode 27 SDK·iOS 27 iPhone 17 runtime·SwiftLint 0.65.1을 설치합니다. 서명·개인 문서·개발 팀·쓰기 토큰은 필요하지 않습니다. runner를 등록하거나 비용이 드는 서비스를 자동 생성하지 않습니다.

workflow는 strict lint, Simulator 회귀·일반 빌드, 버전 기반 새 소비자 빌드, 아카이브 해시를 검사합니다. 도구가 없으면 명시적으로 실패하며 검사를 건너뛰거나 OS 설정을 낮추지 않습니다. 아직 게시·실행하지 않은 workflow의 문법/명령 검토를 실제 CI 통과와 구분합니다. GitHub 호스트의 Xcode 27 지원이 확인되면 별도 변경으로 자동 PR 검증을 검토할 수 있습니다.

```bash
# HEAD를 별도 로컬 mirror의 임시 SemVer로 소비한다. 커밋되지 않은 변경은 포함하지 않는다.
bash .github/verify-consumer.sh /새로운/OmniParserConsumer
bash ThirdParty/OfficeOxide/build.sh --verify
```

소비자 검사는 외부 의존성·공개 바이너리를 받을 수 있으므로 네트워크가 필요할 수 있습니다. 로컬 mirror 태그는 원격으로 푸시하지 않습니다. 릴리즈 전에는 별도로 실제 공개 태그의 설치·회귀와 최신 실기기 결과를 확인합니다. native 재빌드는 [별도 제작 절차](ThirdParty/OfficeOxide/README.md)를 따르며 자동 채택하지 않습니다.
