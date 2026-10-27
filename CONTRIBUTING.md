# 기여 안내

현재 공개 프리릴리즈이며 지원 범위·API가 바뀔 수 있습니다. 형식·위치·오류 계약은 [README](README.md)와 [API](Documentation/API.md)를 먼저 확인해 주세요.

- iOS 27 SDK를 제공하는 Xcode, SwiftPM tools 6.2, Swift 언어 모드 5.0을 유지합니다.
- 변경한 동작을 드러내는 원본 정답 회귀를 추가하고 `swiftlint lint --strict`, README의 Simulator 테스트·일반 빌드를 실행합니다. 실패·미실행 항목은 원인을 적습니다.
- 샘플은 자체 생성하거나 재배포 조건·출처를 확인해야 합니다. 민감한 문서는 공개 이슈·PR·로그에 올리지 않습니다.
- 새 의존성, 공개 API 변경, 지원 형식 조정은 구현 전에 이슈에서 범위·라이선스·영향을 논의합니다.
- PR에는 문제의 입력 조건, 결과의 변화, 실행한 검증과 남은 제약을 적습니다. 관계없는 리팩터링·생성 바이너리는 분리합니다.

## CI와 릴리즈 확인

`.github/workflows/verification.yml`은 공개 저장소의 PR·main 푸시·수동 실행에서 일회용 GitHub-hosted `xcode-27` runner를 사용합니다. 별도 self-hosted runner 등록·서명·개발 팀·쓰기 토큰은 필요하지 않습니다. 비공개 저장소에서는 job을 실행하지 않으며 larger runner는 사용하지 않습니다.

GitHub의 [표준 runner 안내](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)와 [Xcode 27 이미지](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)를 2026-10-27에 확인했습니다. Xcode 27.1·SDK 27.1·iOS 27.0 iPhone 17 runtime을 선택하고 SwiftLint 0.65.1 공식 portable 자산은 고정 SHA-256을 확인한 뒤 실행합니다. checkout action도 Node 24 기반 v7.0.1의 커밋 SHA로 고정하며 자격 증명을 남기지 않습니다.

workflow는 strict lint, Simulator 회귀·일반 빌드, 버전 기반 새 소비자 빌드, 아카이브 해시를 검사합니다. 도구가 없으면 명확히 실패하며 검사를 건너뛰거나 OS 설정을 낮추지 않습니다. 아직 게시·실행하지 않은 workflow의 문법·명령 검토는 실제 CI 통과와 구분합니다.

```bash
# HEAD를 별도 로컬 mirror의 임시 SemVer로 소비한다. 커밋되지 않은 변경은 포함하지 않는다.
bash .github/verify-consumer.sh /새로운/OmniParserConsumer
bash ThirdParty/OfficeOxide/build.sh --verify
```

소비자 검사는 외부 의존성·공개 바이너리를 받을 수 있으므로 네트워크가 필요할 수 있습니다. 로컬 mirror 태그는 원격으로 푸시하지 않습니다. 릴리즈 전에는 별도로 실제 공개 태그의 설치·회귀와 최신 실기기 결과를 확인합니다. native 재빌드는 [별도 제작 절차](ThirdParty/OfficeOxide/README.md)를 따르며 자동 채택하지 않습니다.
