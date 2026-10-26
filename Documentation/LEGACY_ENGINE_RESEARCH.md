# 구형 Office 소스 기반 엔진 추가 조사

> 개인 절대 경로는 [로컬 검증 경로 별칭](RESEARCH_PATHS.md)으로 표기했다. 원시 로그·진단 덤프는 저장소에 포함하지 않는다.

조사일: 2026-10-26. 목표는 DOC·XLS·PPT의 본문·표·삽입 이미지와 기존 위치·경고·취소·옵션을 유지하면서 직접 작성한 코드와 사전 빌드 바이너리 배포를 줄이는 것이다. 검색 결과의 지원 확장자만으로 대체 가능 판정을 내리지 않았다.

## 판단

- **사전 빌드 바이너리 없이 가능한 경로는 있다.** C 라이브러리는 SwiftPM의 C 타깃으로 소스 컴파일하는 구성을 검토할 수 있다. Rust도 소스는 공개되어 있지만 SwiftPM이 Rust를 기본 컴파일하지 않으므로 별도 툴체인·브리지·제작 과정이 필요하다. 소스 공개와 순수 Swift 구현은 다른 조건이다.
- **XLS는 추가 검증할 후보가 확인됐다.** libxls는 C 소스 컴파일 경로, calamine은 그림까지 포함한 추출 경로가 유망하다.
- **DOC·PPT를 한꺼번에 바꾸는 확정 후보는 아직 없다.** anydoc은 문구 추출에는 성공했지만 그림·표 구조 누락이 있다.
- 이번 조사에서 운영 소스·의존성·LICENSE·바이너리를 바꾸지 않았다. 순 코드 감소는 0줄이며 브리지·고지·보완 코드까지 포함한 순감소를 측정하기 전에는 감소량을 추정하지 않는다.

## 후보별 조사

| 후보 | 구현·라이선스 | 범위와 관찰 | 판단 |
| --- | --- | --- | --- |
| [anydoc](https://github.com/firecrawl/anydoc) | Rust, MIT | 구형 세 형식 직접 해석. 12개 실행 완료. 일부 이미지·표 구조 누락 | 추가 비교 후보, 즉시 교체 불가 |
| [calamine](https://github.com/tafia/calamine) | Rust, MIT | XLS·XLSX 등. picture 기능으로 XLS 이미지 바이트 접근. XLS 4개 실행 완료 | XLS 후보. DOC·PPT는 대상 아님 |
| [libxls](https://github.com/libxls/libxls) | C, BSD-2-Clause | XLS 값·행·열·병합 정보. 핵심 5개 C 소스의 기기·Simulator 오브젝트 컴파일 성공 | 사전 빌드 바이너리 배포를 줄이려는 목표에 가장 가까운 XLS 후보 |
| [tokimo-package-fileparser](https://github.com/tokimo-lab/tokimo-package-fileparser) | Rust, MIT OR Apache-2.0 | 구형 Office는 office_oxide 사용을 명시 | 독립 대체 엔진이 아닌 래퍼라 우선순위 낮음 |
| [Shiva](https://github.com/igumnoff/shiva) | Rust, MIT OR Apache-2.0 | XLS·DOCX 등. 지원 표에 구형 DOC·PPT 없음, DOCX 이미지 미지원 명시 | 전체 Office 대체로 부적합 |
| [DocWire](https://github.com/docwire/docwire) | C++20, AGPL-3.0 또는 별도 상용 계약 안내 | 넓은 형식 지원. iOS 빌드·추출 결과 미검증 | MIT 자체 패키지의 배포 부담을 줄이려는 목적에서 우선순위 낮음 |

라이선스는 후보의 원문 LICENSE·manifest·README를 대조한 항목이다. MIT/BSD는 저작권·원문 고지 유지 조건을 확인해야 하며 전이 구성요소의 조건도 별도로 남는다. 후보 자체의 표기를 최종 앱 전체의 배포 적합성 확인으로 해석하면 안 된다.

순수 Swift 검색에서는 CoreXLSX·SwiftDocuments·SwiftDocX처럼 OOXML 중심 후보와 이미 검증한 DocReader를 다시 확인했다. 이번 검색으로 기존 구형 세 형식의 추출 기능을 모두 유지하는 순수 Swift 대체재는 확인하지 못했다. 후보가 존재하지 않는다고 단정하는 결론은 아니다.

## anydoc 실제 비교

버전 0.2.4, 커밋 `e7178e099b6bf9171e2c52b832cbdb4134b69112`. 원본 `Cargo.lock`으로 macOS에서 `cargo build --locked --example convert`를 실행했고 성공했다. 검증용 예제는 별도 캐시의 `examples/legacy_probe.rs`다.

같은 기존 로컬 샘플 12개를 `to_document`로 읽어 표·셀·image MIME 자산 수를 기록했다. 문구 확인은 `to_markdown_bytes`를 별도로 호출했다. 두 번 파싱하고 플랫폼도 기존 iOS 실행과 다르므로 수집된 시간을 성능 우열 비교에 사용하지 않는다. 새로운 외부 문서 다운로드·업로드·테스트 자산 편입은 하지 않았다.

| 파일 | anydoc 셀 | 기존 셀 | anydoc 이미지 | 기존 이미지 |
| --- | ---: | ---: | ---: | ---: |
| LegacySample.doc | 2 | 2 | 1 | 1 |
| real-doc-01-SampleDoc.doc | 0 | 0 | 0 | 0 |
| real-doc-02-simple-table.doc | 6 | 6 | 0 | 0 |
| real-doc-03-pictures_escher.doc | 0 | 0 | 0 | 2 |
| LegacySample.xls | 2 | 2 | 0 | 1 |
| real-xls-01-mortgage-calculation.xls | 8 | 7 | 0 | 0 |
| real-xls-02-sumifs.xls | 243 | 195 | 0 | 0 |
| real-xls-03-testEXCEL-charts.xls | 37 | 12 | 0 | 0 |
| LegacySample.ppt | 0 | 2 | 1 | 1 |
| real-ppt-01-SampleShow.ppt | 0 | 0 | 0 | 0 |
| real-ppt-02-pictures.ppt | 0 | 0 | 2 | 2 |
| real-ppt-03-WithMaster.ppt | 0 | 0 | 0 | 0 |

12개 모두 열렸고 제공된 본문·셀 확인 문구는 모두 포함됐다. 하지만 자체 생성 PPT는 본문 문자열에 셀 문구가 남아도 표·셀 블록은 0개다. DOC 그림 샘플은 기존 2개 대비 0개, 자체 생성 XLS 그림은 기존 1개 대비 0개다. 셀 개수 차이는 빈 셀·숨김 처리·사용 영역 정책의 차이일 수 있어 더 많다는 이유로 정확도가 높다고 판단하지 않는다.

소스에서도 PPT 그림은 문서 단위 자산이고 슬라이드별 배치를 복원하지 않는다고 명시한다. 공통 Document/Block 모델에는 OmniParser와 동등한 원본 페이지·슬라이드·셀 주소·이미지 좌표·부분 실패 경고 필드가 없다. 일부 실패는 `log::warn!` 경로이며 구조화된 결과 경고와 다르다. 제한 상수는 있지만 현재 소비 API와 동일한 조정 가능 제한·취소·이미지/OCR 옵션을 그대로 대체하는 공개 API는 확인하지 못했다. Rust 및 Swift 어댑터 보완량을 포함해야 한다. anydoc의 Node/CLI에서 제공하는 hosted OCR은 사용하지 않았다.

## calamine 실제 비교

버전 0.37.0, 커밋 `c922fc0a0c3cc9901e7d0b7a40507140478e5912`. `picture` 기능을 켜고 macOS에서 읽었다. `examples/legacyprobe.rs`로 시트·비어 있지 않은 셀·그림 수를 기록했다.

| XLS 입력 | 시트 | 비어 있지 않은 셀 | 그림 |
| --- | ---: | ---: | ---: |
| LegacySample.xls | 1 | 2 | 1 |
| real-xls-01-mortgage-calculation.xls | 3 | 7 | 0 |
| real-xls-02-sumifs.xls | 5 | 195 | 0 |
| real-xls-03-testEXCEL-charts.xls | 3 | 15 | 0 |

4개 완료, 제공된 확인 문구 일치, 자체 생성 XLS의 그림 1개 반환. 그림 바이트 반환과 셀 앵커 반환은 다르다. 확인한 `pictures_with_metadata`는 XLS의 위치 복원을 보장하지 않으므로 기존 위치 경고 처리를 유지해야 한다. 병합·날짜·수식 캐시·숨김 시트·그림 중복·깨진 입력·한영 OCR의 전체 회귀와 Swift 연결은 미검증이다. iOS Rust 빌드·실행도 이번에 수행하지 않았다.

## libxls 소스 배포 가능성 검증

커밋 `34c7cc6da1c005c1385992c73529546b66838c78`, configure 버전 1.6.4. 라이브러리 본체 `xlstool.c`, `endian.c`, `locale.c`, `ole.c`, `xls.c` 5개를 iOS 27.0 기기 arm64와 Simulator arm64로 각각 컴파일해 **10/10 성공**했다. 이는 upstream의 공식 iOS 지원 선언이나 완성된 SwiftPM 통합 검증을 의미하지 않는다.

```bash
xcrun --sdk iphoneos clang -target arm64-apple-ios27.0 \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -std=c99 -Iinclude -Iprobe-build -c src/xls.c -o probe-build/iphoneos-xls.o
```

검증용 config.h에 Apple용 기능 매크로와 iconv 설정을 작성했다. 최초에는 `ICONV_CONST`가 누락되어 xlstool.c만 두 타깃에서 실패했고, Apple 설정으로 추가한 뒤 전부 재실행해 성공했다. 원본 소스는 고치지 않았다. 생성 설정을 상수로 고정해 다른 OS에 배포해도 된다는 뜻은 아니다.

같은 5개 소스와 xls2csv.c를 macOS에서 `-liconv`로 링크해 XLS 4개를 읽었고 모두 종료 0·확인 문구 일치였다. sumifs 샘플의 CSV 출력은 행 병합 재현 한계를 경고했다. 메모리 입력 API `xls_open_buffer`가 있어 문서마다 임시 파일을 쓰지 않는 어댑터를 검토할 수 있다.

공개 API에서 그림 바이트·앵커 추출 API는 확인하지 못했다. 현재 `DocumentLegacyOfficeSupplement`를 남겨 이미지 처리를 보완하는 조합이 가능할지는 실제 어댑터 검증이 필요하다. SwiftPM C 타깃 제작·iOS 링크/실행·한국어 인코딩·자원 제한·취소·오류 전파·스레드 안전성은 미검증이다. 프로세스 전역 debug/handler 상태도 배치 병렬 처리 전에 확인해야 한다.

## 권장 검증 순서

1. **libxls + 기존 그림 보완 경로**를 격리된 SwiftPM C 타깃으로 연결해 iOS에서 확인한다. 새 생산 의존성 반영은 별도로 승인받는다.
2. 실패하면 **calamine + Rust 브리지**를 XLS 한 형식에 한정해 비교한다. 이미지 위치·자원 제한 보완까지 포함한다.
3. DOC·PPT는 현 엔진을 유지한다. anydoc은 누락 요소와 원본 위치·부분 실패 계약을 보완하지 않는 한 교체하지 않는다.
4. OOXML은 SwiftDocuments·SwiftDocX·CoreXLSX·PPTX 후보를 따로 검증한다. XLS만 교체해도 DOCX·XLSX·PPTX가 OdrCore를 사용하므로 그 바이너리 의존성 전체가 바로 없어지지는 않는다.

## 로컬 근거

`${OMNI_RESEARCH_ROOT}/`에 각 고정 리비전의 checkout과 원본 고지를 보존했다.

- 입력·SHA-256: `inputs.json` 및 [이전 비교 문서](DOCREADER_EVALUATION.md)
- anydoc: `anydoc-build.log`, `anydoc-probe-build.log`, `anydoc-results.json`, 샘플별 Markdown
- calamine: `calamine-build.log`, `calamine-results.json`, 샘플별 텍스트
- libxls: `libxls-ios-compile.json`(초기 실패), `libxls-ios-compile-final.json`(최종 명령·결과), `libxls-results.json`, `libxls/probe-build/config.h`, 샘플별 출력

운영 파서 코드 변경이 없어 앱 빌드·린트를 다시 실행하지 않았다. 위 macOS 실행·C 크로스 컴파일을 실기기 검증이나 전체 회귀 테스트로 표시하지 않는다. 커밋·푸시는 하지 않았다.
