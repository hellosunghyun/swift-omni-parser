# Third-party notices

루트 `LICENSE`의 MIT 조건은 OmniParser가 작성한 코드와 문서에 적용됩니다. 아래 구성요소와 `ThirdParty/` 아래의 원본 라이선스·고지·바이너리를 MIT로 변경하지 않습니다.

## 직접 사용하는 라이브러리

| 구성요소 | 버전 / 리비전 | 원래 라이선스 | 고지 / 소스 |
| --- | --- | --- | --- |
| SwiftSoup | 2.14.3 / e7f85f4 | MIT | [라이선스](ThirdParty/SwiftSoup/LICENSE) · [소스](https://github.com/scinfu/SwiftSoup/tree/e7f85f4d3dd91ca9a1e94d3328aa1ed5120a8c0f) |
| OLEKit | 0.3.1 / 2cc7a98 | Apache-2.0 | [라이선스](ThirdParty/OLEKit/LICENSE) · [소스](https://github.com/CoreOffice/OLEKit/tree/2cc7a98b4ac4e9ce022336258a3bc4ff6bfc285b) |
| OpenDocument.core | 7.5.2 / 77e2a0a | MPL-2.0 | [라이선스](ThirdParty/OpenDocument.core/LICENSE) · [소스](https://github.com/opendocument-app/OpenDocument.core/tree/77e2a0a6e4b33c33a5aee64551fcd0d7493c9101) |
| hwp-swift / CoreHwp | 0.19.0 / eebe90d | LGPL-2.1 | [라이선스](ThirdParty/hwp-swift/LICENSE) · [소스](https://github.com/sboh1214/hwp-swift/tree/eebe90d160b3d437b97d0bb1ea7a5752f419f225) |
| office_oxide | 0.1.15 / 5d183f4 | MIT OR Apache-2.0에서 MIT 선택 | [MIT](ThirdParty/OfficeOxide/LICENSE-MIT) · [원래 NOTICE](ThirdParty/OfficeOxide/NOTICE) · [소스](https://github.com/yfedoseev/office_oxide/tree/5d183f4de990de254f32976bf952e548bcd25972) |

SwiftPM으로 가져오는 의존성의 소스와 원래 라이선스는 해당 저장소에서 취득할 수 있습니다. 수정본을 별도로 배포한다면 수정한 소스와 그에 해당하는 고지를 제공해야 합니다. API 연결을 위해 작성한 OmniParser 파일은 외부 라이브러리 자체의 라이선스를 변경하지 않습니다.

## OfficeOxide 바이너리

- [크레이트별 고지 원문](ThirdParty/OfficeOxide/THIRD_PARTY_LICENSES.txt)을 보존했습니다. 원래 크레이트와 호스트 빌드용 구성요소가 함께 포함된 고지이므로 런타임에 모두 링크된다는 뜻은 아닙니다.
- 이 목록에는 MIT·Apache-2.0 외에 BSD-3-Clause, Unicode-3.0, Zlib 등의 조건이 있습니다. OfficeOxide에 MIT를 선택해도 이 조건을 덮어쓰지 않습니다.
- 정적으로 포함될 수 있는 Rust 표준 라이브러리의 [저작권 고지](ThirdParty/OfficeOxide/RustStandardLibrary/COPYRIGHT), [라이브러리 상세 고지](ThirdParty/OfficeOxide/RustStandardLibrary/COPYRIGHT-library.html), MIT·Apache 라이선스와 메타데이터를 별도 보존했습니다. 바이너리 제작에 기록된 Rust 1.97.1 설치본에서 가져온 고지입니다.
- [재빌드 스크립트](ThirdParty/OfficeOxide/build.sh), [호환 패치](ThirdParty/OfficeOxide/compat.patch), [SHA-256](ThirdParty/OfficeOxide/SHA256SUMS)를 포함합니다. 재빌드에는 Rust iOS 타깃과 Xcode가 필요하며 패키지 소비 시에는 Rust를 실행하지 않습니다.

## Rust 표준 라이브러리 고지 보충

기존 HTML의 외부 크레이트 목록이 비어 있어, 기기용 정적 아카이브에서 관찰한 구성요소 이름을 기준으로 Rust 1.97.1 설치 소스의 고지를 [추가 보존](ThirdParty/OfficeOxide/RustStandardLibrary/AdditionalNotices)했습니다. 여기에는 compiler-builtins의 LLVM 예외·NCSA 문구와 libc·gimli·miniz_oxide 등 관련 크레이트의 원래 고지가 포함됩니다.

파일별 원래 경로·SHA-256과 확인 범위는 [보충 출처 기록](ThirdParty/OfficeOxide/RustStandardLibrary/ADDITIONAL_NOTICE_PROVENANCE.json)에 있습니다. 구성요소 이름 관찰만으로 모든 버전과 링크 구성을 확정한 것은 아니며, 고지의 완전성 판정에는 재현 빌드가 남아 있습니다.

## OpenDocument.core 네이티브 구성요소

이 저장소는 OpenDocument.core의 XCFramework를 복제하지 않고, 해당 패키지가 선언한 업스트림 배포 자산을 사용합니다. 따라서 라이브러리의 소스 취득 경로와 고지는 위 고정 리비전을 기준으로 확인해야 합니다.

고정 리비전의 Conan 명세에는 pugixml 1.15, Crypto++ 8.9.0, fmt 11.2.0, md4c 0.5.2, miniz 3.1.1, nlohmann_json 3.12.0, OpenJPEG 2.5.4, uchardet 0.0.8, utfcpp 4.0.9가 선언되어 있습니다. Apple 빌드 스크립트는 HTTP 서버 기능을 켜며 cpp-httplib 0.47.0도 선언됩니다.

Conan 레시피에서 확인한 조건은 MIT·BSL-1.0·BSD-2-Clause와 uchardet의 MPL-1.1입니다. 이 명세와 레시피 확인을 배포 바이너리 전체의 완전한 SBOM·링크 구성 검증으로 보지는 않습니다. 이 라이브러리가 내장하는 데이터의 별도 [출처·라이선스 설명](ThirdParty/OpenDocument.core/THIRD_PARTY_DATA.md)도 보존했습니다. 앱 바이너리를 재배포할 때에는 추가 전이 의존성과 데이터의 원래 고지까지 확인해야 합니다.

## Apple 프레임워크

Foundation, CoreGraphics, ImageIO, PDFKit, UIKit, Vision, Synchronization 등은 Apple SDK가 제공하는 프레임워크입니다. 이 저장소가 해당 프레임워크를 MIT로 배포하는 것은 아닙니다. 실제 사용·배포에는 Apple SDK의 조건이 적용됩니다.
