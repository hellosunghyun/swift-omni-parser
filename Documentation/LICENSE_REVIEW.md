# MIT 적용 범위와 의존성 라이선스 검토

검토일: 2026년 10월 26일

## 결론

**루트 MIT는 별도로 작성한 OmniParser Swift 코드·문서의 라이선스 선언입니다. 직접 의존성의 원래 라이선스 표기는 확인했지만, 전체 배포물의 라이선스 준수 완료로 판정하지 않습니다.** 이 결론을 모든 구성요소가 MIT라거나, 소비 앱이 추가 의무 없이 바이너리를 배포할 수 있다는 의미로 해석하면 안 됩니다.

공개 대상은 자체 Swift 소스와 패키지 연결 코드입니다. SwiftSoup·OLEKit·OpenDocument.core·hwp-swift는 고정 버전의 별도 SwiftPM 의존성으로 가져오며 이 저장소에서 소스를 MIT로 변경하지 않습니다. 별도로 포함하는 OfficeOxide 정적 바이너리에는 원래 MIT·NOTICE와 전이 의존성·Rust 표준 라이브러리 고지를 보존했습니다.

## 확인한 버전과 근거

| 항목 | 고정 버전 | 확인한 조건 | MIT 자체 코드와 함께 제공할 때의 구분 |
| --- | --- | --- | --- |
| SwiftSoup | 2.14.3 | MIT | 원래 저작권·허가문 보존 |
| OLEKit | 0.3.1 | Apache-2.0 | 원래 라이선스·해당 고지 보존, 수정 시 변경 표시 등 적용 조건 유지 |
| OpenDocument.core 포크 | v7.5.2-omni.1 / b302cc85 | MPL-2.0 | 해당 라이브러리·수정된 MPL 파일은 MPL 유지, 소스 취득 방법 고지 |
| hwp-swift / CoreHwp | 0.19.0 | LGPL-2.1 | 해당 라이브러리·수정분의 조건 유지, 링크한 바이너리 재배포 시 LGPL 제6조 등 검토 |
| OfficeOxide | 0.1.15 / 5d183f4 | MIT OR Apache-2.0 | 이 배포에서는 MIT 선택, 내부 구성요소의 별도 조건은 유지 |

위 다섯 항목의 라이선스 파일은 고정된 커밋의 GitHub 원본과 로컬 사본의 해시가 일치하는지 확인했습니다. 상세 리비전과 라이선스 파일 해시는 `DEPENDENCIES.json`에 기록했습니다.

## MPL·LGPL을 MIT로 바꾸지 않는 이유

### OpenDocument.core / MPL

Mozilla FAQ는 MPL 코드를 포함하지 않는 별도 파일에 다른 라이선스를 적용하는 Larger Work 구성을 설명합니다. 반면 MPL 파일을 수정했다면 해당 파일의 소스와 변경분을 MPL 조건으로 제공해야 하며, 바이너리를 배포할 때에는 대응 소스의 취득 방법을 알려야 합니다.

OmniParser의 API 어댑터를 MIT로 제공하는 것과 OpenDocument.core 자체를 MIT로 바꾸는 것은 다릅니다. 이 저장소에는 후자를 허용하는 권한을 주장하지 않습니다.

### hwp-swift / LGPL

현재 `OmniParser` 제품의 `CoreHwp` 의존성은 선택 사항이 아닙니다. PDF 등 다른 형식만 호출하더라도 제품 구성에서 HWP 의존성을 제외할 수 없으므로, 사용 형식만으로 LGPL 검토가 면제된다고 가정하면 안 됩니다.

LGPL-2.1 제6조는 라이브러리를 사용하는 저작물과의 결합을 별도 조건으로 허용합니다. 라이브러리와 결합된 실행 파일을 배포할 때에는 저작권·라이선스 고지 외에도 수신자가 라이브러리를 수정하고 다시 링크할 수 있는 형태의 자료 제공 등 해당 조항에 맞는 방식을 선택해야 합니다. 라이브러리 변경을 디버깅하기 위한 역공학 관련 조건도 고려해야 합니다.

자체 코드를 MIT로 공개했다는 사실만으로 소비 앱 전체의 LGPL 이행 여부가 결정되지는 않습니다. 특히 iOS 앱의 정적 링크·서명·배포 경로는 최종 배포자가 확인해야 합니다. 이 패키지는 hwp-swift 소스의 고정 리비전과 원래 라이선스를 제공하며, 앱의 배포 조건을 대신 결정하지 않습니다.

## 네이티브 전이 의존성

- OfficeOxide의 기존 크레이트 고지는 36개 구성요소 항목을 포함합니다. MIT/Apache 선택형 외에 BSD-3-Clause, Unicode-3.0, Zlib 등도 있어 원문을 보존했습니다. 일부는 빌드 전용이며 모든 항목이 런타임에 링크된다는 뜻은 아닙니다.
- 기존 Rust 표준 라이브러리 HTML 고지의 외부 크레이트 목록은 비어 있습니다. 반면 기기용 아카이브 멤버에는 `libc`, `gimli`, `miniz_oxide`, `compiler_builtins` 등의 오브젝트 이름이 확인됩니다. 따라서 기존 HTML만으로 고지가 완전하다고 볼 수 없습니다.
- Rust 1.97.1 소스 트리에서 관련 크레이트와 compiler-builtins·libm·stdarch의 원래 고지를 추가 보존했습니다. 이 보충에는 Apache-2.0 WITH LLVM-exception, NCSA 계열 등의 원래 문구도 포함됩니다. 아카이브 멤버 이름은 정확한 버전을 증명하지 않으므로, 바이너리와 대응 소스 버전의 완전한 대조는 재현 빌드 후 확인해야 합니다. 자세한 출처와 해시는 `ThirdParty/OfficeOxide/RustStandardLibrary/ADDITIONAL_NOTICE_PROVENANCE.json`에 기록했습니다.
- OpenDocument.core의 고정 Conan 명세와 Apple 빌드 옵션에서 C++ 라이브러리 10개를 확인했습니다. Conan 레시피에는 MIT, BSL-1.0, BSD-2-Clause와 uchardet의 MPL-1.1이 표시되어 있습니다. 따라서 MPL-2.0 하나만으로 네이티브 구성요소 전체의 조건을 설명할 수 없습니다.
- OpenDocument.core의 글꼴·인코딩 데이터 출처에 기재된 BSD-3-Clause·Apache-2.0 등도 별도 설명을 보존했습니다.

이 확인은 명세와 제공된 고지에 대한 검토입니다. 업스트림 XCFramework 전체의 완전한 전이 SBOM, 실제 링크된 각 오브젝트의 출처, 최종 앱의 배포 준수까지 독립 검증한 것은 아닙니다.

## 재현 빌드 관련 미완료 항목

OfficeOxide README는 기존 바이너리가 Rust 1.97.1과 `RUSTC_BOOTSTRAP=1`, `-Z build-std=std,panic_abort`로 제작되었다고 기록합니다. 그러나 현재 `build.sh`는 Rust 도구 버전·해당 옵션을 고정하지 않고, 성공 후 `SHA256SUMS`·고지를 갱신하지도 않습니다. 따라서 이 스크립트를 배포된 바이너리와 동일한 산출물의 재현을 보장하는 절차로 표현하지 않습니다. 대응 소스·빌드 옵션·전이 의존성 고지를 함께 고정한 제작 경로가 후속으로 필요합니다.

## 포함하지 않은 범위

- 앱 UI, TCA, 워치 연결 코드와 해당 라이브러리
- 이전 스택에서 이미 제외된 테스트·샘플과 샘플의 라이선스 묶음
- Apple SDK 프레임워크의 재배포·재라이선스

SPM 해석 결과의 외부 소스 패키지는 SwiftSoup, OLEKit, OpenDocument.core, hwp-swift 네 개입니다. hwp-swift 명세의 테스트 전용 의존성 등은 OmniParser의 런타임 그래프에 포함되지 않았습니다.

## 확인 자료

- [Mozilla MPL FAQ](https://www.mozilla.org/en-US/MPL/2.0/FAQ/)
- [LGPL-2.1 원문 사본](../ThirdParty/hwp-swift/LICENSE), 특히 제5·6조
- [SwiftSoup 고정 소스](https://github.com/scinfu/SwiftSoup/tree/e7f85f4d3dd91ca9a1e94d3328aa1ed5120a8c0f)
- [OLEKit 고정 소스](https://github.com/CoreOffice/OLEKit/tree/2cc7a98b4ac4e9ce022336258a3bc4ff6bfc285b)
- [OpenDocument.core 고정 소스](https://github.com/opendocument-app/OpenDocument.core/tree/77e2a0a6e4b33c33a5aee64551fcd0d7493c9101)
- [hwp-swift 고정 소스](https://github.com/sboh1214/hwp-swift/tree/eebe90d160b3d437b97d0bb1ea7a5752f419f225)
- [OfficeOxide 고정 소스](https://github.com/yfedoseev/office_oxide/tree/5d183f4de990de254f32976bf952e548bcd25972)
- [서드파티 고지와 소스 취득 경로](../THIRD_PARTY_NOTICES.md)

이 문서는 기록한 버전과 배포 구성의 검토 결과이며, 법적 보증이나 소비 앱의 배포 승인서는 아닙니다.

## 2026-10-27 XLS 수정 포크 전환

OpenDocument.core 의존성을 `hellosunghyun/OpenDocument.core`의 `b302cc85311490676986a2b731971473ad21efac`으로 고정했다. 변경한 native 소스는 MPL-2.0을 유지한다. [Release](https://github.com/hellosunghyun/OpenDocument.core/releases/tag/v7.5.2-omni.1)에 고정 Conan 요구사항의 원문 고지, recipe/package 리비전, uchardet 0.0.8 대응 소스를 보존했다. 원문 고지는 Git에서도 줄바꿈 바이트를 유지한다. 이는 앱 배포 방식까지 포함한 모든 라이선스 의무를 이행했다는 판정은 아니다.
