# 배포 경로 후속 검증

2026-10-27~28. 대상은 공개 `v0.1.0-alpha.1` 이후의 로컬 변경이다. 이 작업은 원격 태그·릴리즈를 변경하지 않는다.

## 버전 설치

`alpha.1`은 버전 기반 소비자가 revision 기반 OpenDocument.core 의존성을 가져올 수 없어 SwiftPM 해석 단계에서 실패했다. OdrCore를 기존 `7.5.2-omni.1` SemVer 태그의 `exact` 의존성으로 바꿨다. 태그는 이전과 동일한 `b302cc85311490676986a2b731971473ad21efac` 커밋을 가리키며 엔진 코드는 바꾸지 않는다. `Package.resolved`도 같은 리비전과 버전을 보존한다.

루트에서 local path 패키지를 빌드하는 것만으로 이 결함을 확인할 수 없었다. `.github/verify-consumer.sh`는 커밋된 HEAD를 별도 bare mirror의 임시 SemVer로 소비하는 새 iOS 패키지를 만들고 public API를 컴파일한다. mirror 태그는 원격으로 보내지 않고 기존 작업물을 덮어쓰거나 삭제하지 않는다.

```bash
bash .github/verify-consumer.sh /새로운/소비자검증폴더
```

이 검사는 **커밋된 HEAD**를 사용한다. 로컬 미커밋 변경·실제 공개 버전 설치와 구분한다. 버전 해석·바이너리 다운로드·컴파일 실패를 각각 기록하고, 실제 공개 태그 설치는 다음 릴리즈 이후 별도로 확인한다. 기존 공개 `alpha.1`을 강제로 다시 태그하지 않는다.

새 소비 패키지의 실제 generic iOS Simulator 빌드가 통과했다. `exact: "0.0.0-consumer-check"` 로컬 검증 태그로 커밋한 소스를 가져오고, 공개 OdrCore 자산도 새 캐시에 다운로드해 SwiftPM 체크섬 검증을 거쳤다. 실제 공개 수정 버전을 게시한 검사는 아니다.

첫 시도는 binary 다운로드 전 macOS Keychain 승인 대기에 걸린 것을 프로세스 스택으로 확인해 해당 검증 프로세스만 종료했다. 공개 의존성의 비대화형 검증은 `-packageAuthorizationProvider netrc`로 실행한다. 키체인·계정 설정을 바꾸거나 비밀번호를 코드에 넣지 않는다.

## CI 준비 상태

공식 [Xcode 27 runner](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/) 지원을 확인해 공개 저장소의 PR·main 푸시·수동 실행에서 일회용 hosted `xcode-27`을 사용하도록 했다. self-hosted runner 등록은 필요하지 않다. 비공개 저장소는 job을 실행하지 않고 larger runner를 선택하지 않는다. 앱 최소 OS와 Swift 언어 모드도 바꾸지 않는다.

검증 순서와 도구는 [기여 안내](../CONTRIBUTING.md)에 적었다. 고정 SwiftLint portable 자산의 실제 해시·버전·strict 실행을 로컬에서 확인했다. 이 작업에서는 푸시·워크플로 실행·러너 등록·유료 서비스를 사용하지 않았으므로 실제 GitHub CI 결과는 아직 없다. 문법·명령 검사와 클라우드 실행을 구분한다.

## OfficeOxide

- 기존 두 아카이브는 `build.sh --verify`로 원래 체크섬과 일치했다. 원문 라이선스·바이너리는 변경하지 않았다.
- 재빌드 스크립트는 고정 소스·Rust 컴파일러 커밋·Cargo·Xcode·SDK·build-std를 검사하며 offline 캐시만 사용한다. 새 검토 번들에 해시·선언 그래프·컴파일 구성요소·오브젝트·원래 고지를 함께 보존한다.
- 출력 경로가 이미 있으면 실행 전에 실패한다. 소스·바이너리·고지를 자동 채택하거나 삭제하지 않는다.
- 공식 Rust 1.97.1 channel manifest와 rustc·Cargo·host std·rust-src tar 4개의 SHA-256을 대조한 뒤 저장소 밖 새 prefix에 설치했다. 고정 소스·lock으로 캐시를 준비하고 최종 offline 레시피 전체를 2 jobs로 실행해 3개 타깃·XCFramework·고지 생성을 완료했다(무정지 실행 179.91초, exit 0).
- 출처·고지 그룹 81개, 실제 compiler-artifact ID는 타깃별 57·57·58개이며 미대응 0개다. Rust 소스 고지 72개와 도구 체인 고지 14개를 보존했다. 선언·빌드 항목도 포함하므로 앱의 실제 링크 구성요소 수와 구분한다.
- 모든 슬라이스의 `office_*` C 정의 심볼 43개가 기존과 일치하고 헤더의 필수 4개를 포함한다. Xcode의 nm는 기존 LLVM bitcode 속성을 해석하지 못해 BSD archive의 정의 심볼 테이블로 대조했다. 심볼 검사와 별도로 새 프레임워크를 저장소 밖의 같은 Swift 소스·테스트에 연결해 Simulator 회귀 48/48을 통과했다. 실제 기기 결과나 모든 입력의 동등성을 보장하는 검사는 아니다.
- 기존/새 바이너리 해시는 다르다. 기존 bitcode LLVM producer 22.1.8과 공식 rustc LLVM 22.1.6, 제작 경로 차이가 있어 바이트 재현 성공으로 표시하지 않는다. 기존 원본 checksum 검사는 계속 통과한다.
- 첫 실행의 fat archive 후처리 오류를 고친 뒤 새 출력에서 최종 레시피 전체를 재실행했다. 첫 실행은 root 성능 측정 동안 199.53초 일시정지했으므로 제작 시간에 사용하지 않았다. 실제 링크 오브젝트 전체의 고지 대응·기존 배포물 바이트 재현·실기기 검증은 미완료다.

새 제작 경로가 있다는 사실로 기존 바이너리의 출처·라이선스 검증이 모두 끝났다고 판단하지 않는다. [제작 안내](../ThirdParty/OfficeOxide/README.md)와 [라이선스 검토](LICENSE_REVIEW.md)에 같은 한계를 유지한다.

### 재빌드 약속 범위

현재 절차는 소스·도구·설정·구성요소·고지·해시를 대조할 수 있는 감사 가능한 재빌드이며, 다른 실행 루트의 바이트 동일성을 보장하지 않는다. Candidate/Verified는 소스 374개와 유효 feature·profile이 같아도 루트 및 레시피 명시값이 달라 엄격한 동일 입력 반복으로 취급하지 않았다. 같은 절대 경로·같은 compiler invocation의 독립 clean 반복도 미실시다.

읽기 전용 분석에서 바이트 차이를 root object의 embedded LLVM bitcode로 좁혔다. device arm64에서 실제 IR 차이는 의미가 같은 PHI incoming 순서 한 곳과 파생 module hash였으며 기계어·일반 상수/데이터·relocation은 같았다. x86_64의 bitcode 크기와 unwind 인코딩 차이도 보존했다. 절대 경로 메타데이터가 근본 원인이라는 가설은 확정하지 않았고, source-map·임의 `-Cmetadata`·bitcode 제거 등의 우회 수정은 하지 않았다. 실제 Swift 실행 회귀와 엄격한 바이트 재현성은 별도 검사다.
