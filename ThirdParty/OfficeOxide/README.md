# OfficeOxide

- office_oxide 0.1.15, 커밋 `5d183f4de990de254f32976bf952e548bcd25972`. MIT를 선택했다. 원래 LICENSE-MIT·NOTICE와 `THIRD_PARTY_LICENSES.txt`의 전이 고지를 보존한다.
- DOC·PPT 본문/표용 정적 XCFramework다. iOS arm64와 Simulator arm64/x86_64를 포함한다. C 핸들·반환 문자열은 호출 안에서 해제한다.
- `compat.patch`는 그림 payload 중복 생성 방지와 단일 행·열/병합 PPT 표 및 3% 영역 판정을 보존한다. XLS/XLSX·OOXML과 OfficeArt 그림 복구는 별도 경로다.

## 현재 배포물 확인

```bash
bash ThirdParty/OfficeOxide/build.sh --verify
```

`SHA256SUMS`는 Git에 포함된 두 정적 라이브러리의 해시다. 기존 배포물은 Homebrew Rust 1.97.1에서 `RUSTC_BOOTSTRAP=1`, `-Z build-std=std,panic_abort`를 사용한 것으로 기록되어 있다. 원래 제작 시점의 전체 환경·소스 해시가 남아 있지 않아, 아래 개선한 절차로 **기존 바이너리와의 바이트 일치가 증명된 것은 아니다.**

## 검토용 재빌드

Rust·소스·Cargo registry 또는 vendor 캐시는 별도로 준비한다. 앱·일반 Swift 패키지 빌드에는 Rust가 필요하지 않다. 스크립트는 도구를 설치하거나 소스를 내려받지 않으며 기존 배포물도 교체하지 않는다.

```bash
bash ThirdParty/OfficeOxide/build.sh \
  --source /고정커밋의/office_oxide \
  --output /새로운/OfficeOxide-검토번들
```

다음 조건과 입력을 확인한 뒤 실행한다.

- 추적 변경 없는 위 고정 소스 커밋과 저장소의 `compat.patch`.
- Rust 1.97.1의 rustc 커밋 `8bab26f4f68e0e26f0bb7960be334d5b520ea452`, 해당 공식 배포 Cargo 커밋 `c980f4866141969fab6254a680546a277789d6f0`, 같은 도구 체인의 rust-src·`library/Cargo.lock`.
- Xcode 27.1 (`27A9275`), iOS/Simulator SDK 27.1. 다른 환경은 자동 변경하지 않고 중단한다.
- 외부 Cargo 설정·RUSTFLAGS는 거부한다. offline·locked 빌드와 표준 라이브러리 소스 빌드를 사용하고 아카이브 시각·디버그 경로를 정규화한다.
- native 최소 버전은 기존 아카이브에서 확인한 10.0을 유지한다. OmniParser 앱의 iOS 27.0·Swift 언어 모드 5.0 설정과 구분한다.

출력에는 XCFramework 외에 해당 빌드의 `SHA256SUMS`, `BUILD_MANIFEST.json`, Cargo·표준 라이브러리 그래프, 타깃별 compiler-artifact 로그, 아키텍처별 아카이브 오브젝트 목록, 라이선스 원문과 해시를 함께 남긴다. 알 수 없는 라이선스·누락 고지·출처와 대조되지 않은 컴파일 구성요소는 실패로 처리한다. Rust 소스와 공식 도구 체인의 공통 고지도 보존하며, 이를 실제 링크된 오브젝트 전체의 완전한 SBOM이라고 표현하지 않는다.

출력 경로는 새 디렉터리여야 한다. 실패해도 자료를 보존하고 기존 XCFramework·고지·체크섬은 덮어쓰거나 삭제하지 않는다. 생성 번들을 검토하고 iOS·Simulator 회귀와 구성요소 대응을 확인한 뒤 별도 변경으로 채택한다. 자동 채택·릴리즈·업로드는 하지 않는다.

## 2026-10-27 실제 실행

전역 환경을 바꾸지 않고 저장소 밖 검증 폴더의 새 prefix에 공식 Rust 1.97.1 구성요소 4개를 설치했다. 공식 channel manifest와 각 tar의 SHA-256을 대조했다. 고정 OfficeOxide 소스와 Cargo.lock으로 캐시를 준비한 뒤, 최종 레시피 전체를 offline·2 jobs로 실행해 기기 arm64·Simulator arm64/x86_64와 XCFramework 조립·고지 생성을 완료했다. 무정지 실행은 총 179.91초였으며 앱 파싱 시간과 구분한다.

- 선언 그래프와 실제 컴파일 구성요소를 함께 모은 출처·고지 그룹 81개. 각 타깃의 컴파일 package ID 57·57·58개가 모두 대응했고 미확인 ID는 0개였다.
- Rust 소스 고지 72개와 공식 도구 체인의 고지 14개를 원문·해시와 함께 보존했다. 다른 OS·선택 기능의 선언 항목도 포함하므로 81개 모두가 앱에 링크된다는 의미는 아니다.
- 3개 슬라이스에서 `office_*` C 정의 심볼 43개가 기존과 동일하며, Swift가 사용하는 헤더의 4개도 포함했다. 타입·실행 결과의 동등성을 심볼 검사만으로 보장하지 않는다.
- 새 해시는 기기 `dd0ed8d2cec2eb25b1dcc808e826c8e2f368c15b6a29d0a03d8e2b139e3c9afd`, Simulator `3832b18d545cc06922d25c1fceca544a94661433ee87d5d601aae36575b3c21d`다. 기존과 바이트가 다르다. 기존 bitcode의 LLVM producer는 22.1.8, 공식 rustc의 LLVM은 22.1.6이었다. 입력 경로 등도 달라 기존 바이너리의 바이트 재현으로 표시하지 않는다.
- 기존 `SHA256SUMS` 검사는 계속 통과하며 Git의 XCFramework·원래 고지는 변경하지 않았다. 새 검토 번들은 저장소 밖에만 있다.

첫 실행에서는 fat Simulator 아카이브를 `ar -t`에 직접 넘기는 후처리 오류를 발견했다. 아키텍처별 slice로 검사하도록 고친 뒤 새 출력 경로에서 최종 레시피 전체가 종료 코드 0으로 끝났다. 첫 실행은 성능 측정과의 CPU 경합을 피하기 위해 199.53초 일시정지했으므로 위 제작 시간으로 사용하지 않았다. 완전한 링크 SBOM·기존 배포물의 바이트 재현·실기기 검증은 별도다.
