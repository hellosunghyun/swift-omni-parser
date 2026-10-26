# XLS 차트 캐시 수정 검증

> 개인 절대 경로는 [로컬 검증 경로 별칭](RESEARCH_PATHS.md)으로 표기했다. 원시 로그·진단 덤프는 저장소에 포함하지 않는다.

> 후속 전체 빌드: 기기 arm64·Simulator arm64/x86_64 XCFramework를 재빌드해 별도 Swift 소비 테스트 **16/16 PASS**를 확인했다. [실제 재빌드](ODR_NATIVE_REBUILD.md)와 [배포 방식](ODR_DISTRIBUTION_OPTIONS.md)을 참고한다. 아래 host probe는 그 전 단계 기록이다. 운영 의존성은 아직 기존 버전이다.

2026-10-26. Ream의 수정은 별도 실험 패키지에 적용했다. OdrCore는 고정 버전 7.5.2의 원본 C++ 소스에 대한 수정 경로를 검증했고, 운영 배포 바이너리·의존성은 바꾸지 않았다.

## Ream

worksheet record와 중첩된 chart substream을 구별했다. worksheet 셀·서식·메모·그림 처리에는 최상위 레코드만 사용하고, chart 처리에는 원래 중첩 레코드를 유지한다. 차트 이후의 셀도 보존한다. 단순 중복 제거로 값을 고르지 않는다.

자체 생성 테스트는 수정 전에 1개 실패를 재현했다. 수정 후 XLS 셀/차트/그림/도형/서식 및 PPT 회귀 **171개 PASS**, src TypeScript 검사 PASS다. 계측된 JS를 다시 생성해 교체 패키지 **13개 XCTest PASS**, 별도 실제 XLS 원본 정답 XCTest **1개 PASS**를 확인했다.

실험 소스: `Research/reamkit/src/excel/xls/biff-reader.ts`, `tests/xls-chart.test.ts`. [재적용 가능한 Ream 패치](Ream-XLS-Chart-Stream.patch)도 보존했다. 산출물: `Research/ReamReplacement`. 운영 SwiftPM manifest에는 Ream 의존성을 추가하지 않았다. 이 변경이 이전 앱 크기·성능 수치의 재측정을 의미하지는 않는다.

## OdrCore

원본 parse_sheet는 첫 EOF에서 종료하고 중첩 BOF를 구별하지 않았다. 그 안의 chart NUMBER 레코드를 실제 셀로 추가하면 registry의 같은 주소 값이 덮인다. 작은 depth 추적으로 중첩 레코드를 건너뛰고 worksheet 자체의 EOF에서만 종료하도록 수정했다. 기존 globals/암호화 검사와 셀 스타일 코드는 유지했다.

패치: [OdrCore-XLS-Chart-Stream.patch](OdrCore-XLS-Chart-Stream.patch). upstream 고정 소스에 git apply --check로 적용 가능함을 확인했다. 공유 SPM checkout이나 artifact를 직접 수정하지 않았다.

| 검사 | 기존 소스 | 패치 소스 |
|---|---|---|
| C++ host probe 실제 원본 Workbook의 A1:A3 | FAIL, exit 4 | PASS, exit 0 |
| 첫 시트 셀 내용과 차트 뒤의 셀 존재 | 오답 검출 | PASS, 셀 11개 |
| C++ host 컴파일·링크 | PASS | PASS |
| arm64 iOS 15.0용 parser 오브젝트 컴파일 | 미실행 | PASS |
| 전체 iOS XCFramework 재빌드/Swift 소비 테스트 | 기존 버전은 XLS 실패 | 후속 구성 PASS, 16/16 |

host probe는 원본 C++ parser/registry/style 등 필요한 실제 upstream 소스를 컴파일했다. 입력은 실제 샘플의 원본 CFB에서 꺼낸 Workbook 바이트이며 원본 A1:A3 값을 assertion했다. 디스크/메모리 파일 I/O를 작은 테스트 어댑터로 제공했다. utf8cpp 빌드 환경 대신 UTF-16→UTF-8 경계만 CoreFoundation 어댑터로 연결했으므로 전체 upstream 빌드와 동일한 실행 환경으로 주장하지 않는다. iOS 컴파일은 upstream 최소 슬라이스 기준 15.0이며 앱의 최소 버전 27.0이나 Swift 언어 모드를 변경하지 않았다.

최초 host probe 단계에서는 Conan 기반 환경이 없었다. 후속 단계에서는 전체 native 재빌드와 iOS 소비 검증을 수행했다. 이는 전체 전이 고지 감사·배포 교체까지 완료한 것은 아니다. 적용하려면 다음 둘 중 하나가 필요하다.

1. upstream에 수정이 포함된 고정 릴리스/리비전을 검증한 뒤 의존성을 변경한다. 실제 제공된 버전을 확인하기 전 임의 버전 번호를 지정하지 않는다.
2. 7.5.2 기준 패치 XCFramework를 별도로 재현 빌드하고, 소스·수정 이력·원래 라이선스/전이 고지·checksum을 보존한 고정 배포물을 사용한다.

둘 다 현재 운영 의존성/바이너리 배포 방식의 변경이므로 운영 manifest에는 반영하지 않았다. Swift에서 잘못된 값을 임의 선택하거나 모든 XLS를 다른 엔진으로 우회하지 않았다. 따라서 운영 정답 테스트는 기존 결함을 계속 실패로 검출한다.

## 재현 근거

연구 루트: `${OMNI_RESEARCH_ROOT}`.

- `OdrXlsFix/xls_parser.original.cpp`, `xls_parser.cpp`: 원본/수정 소스.
- `parser_probe.cpp`, `build_probe.py`, `Workbook.bin`, `host-probe-results.json`: 원본/수정 비교.
- `compile-parser.log`, `compile-parser-ios.log`, `build-original.log`, `build-patched.log`: 컴파일 근거.
- `OfficeContractAudit/ream-xls-before-fix.log`, `ream-fix-tests.log`, `ream-fix-typecheck.log`, `ream-fixed-full-tests.log`: Ream 전후 검사.
- `SplitParity/ream-source-truth-fixed.log`: 실제 XLS iOS 정답 테스트 PASS.
- `OfficeContractAudit/package-regression-tests.log`: 운영 패키지의 같은 결함 BASELINE_FAIL.

native patch는 외부 MPL-2.0 소스의 변경이며 OmniParser의 MIT로 재라이선스하지 않는다. 기존 외부 소스 취득 경로·고지는 [서드파티 고지](../THIRD_PARTY_NOTICES.md)를 따른다. 커밋·푸시는 하지 않았다.
