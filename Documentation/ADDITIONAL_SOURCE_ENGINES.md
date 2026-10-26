# 추가 대체 경로: Ream·JDoc·변환 코어·번역 이식

> 개인 절대 경로는 [로컬 검증 경로 별칭](RESEARCH_PATHS.md)으로 표기했다. 원시 로그·진단 덤프는 저장소에 포함하지 않는다.

조사일: 2026-10-26. 기존 후보를 반복하는 대신 ① JS 소스로 직접 파싱 ② C++ 소스와 C API ③ 구형→OOXML 변환 코어 ④ Java→Objective-C 번역 ⑤ 상용 iOS 엔진을 비교했다. Aside CLI 세션 `YH3asNqLYM3JYyx7`에서 ONLYOFFICE·POI·상용 SDK를 웹 조사했고, Ream/JDoc은 별도 로컬 캐시에 복제해 실행했다.

운영 의존성·소스·라이선스는 변경하지 않았다. 새 후보를 기존 코드와 같은 수준으로 iOS 검증한 결과가 아니다. 자체 코드를 MIT로 유지하는 것과 외부 코드 전부를 MIT로 바꾸는 것은 구분한다.

## 1. Ream: 네이티브 바이너리 없는 JS 소스 경로

- [공식 저장소](https://github.com/alex-krassavin/reamkit), [문서](https://reamkit.dev/).
- 버전 1.33.1, 커밋 `253cb67f1f7f8d3f7493f4f2ba09a8855fe16d24`.
- [MIT 원문](https://github.com/alex-krassavin/reamkit/blob/main/LICENSE) 확인. 런타임 의존성은 fast-xml-parser와 fflate이며 각각의 고지를 유지해야 한다.
- 구형 DOC/XLS/PPT를 각 reader가 직접 읽고, `Ream.parse(bytes).flow`, `.sheet`, `.losses`와 ResourceStore로 구조·그림 바이트·일부 손실 정보를 얻는다. 문서 모델과 XLS의 인쇄용 FlowDoc 투영 결과는 다르므로 원본 셀 주소가 필요하면 `.sheet`를 확인해야 한다.
- SwiftPM에 Rust/C++ XCFramework를 넣는 대신 JS 소스를 번들링해 JavaScriptCore 또는 WKWebView에 넣는 설계를 검토할 수 있다. 이는 제안이며 이번에 iOS에서 실행하지 않았다. TextEncoder/TextDecoder·base64·암호화 등 사용하는 web API의 실제 노출과 필요한 shim을 확인해야 한다.
- PDF/SVG 변환은 기본 폰트 선택에서 네트워크 다운로드가 가능하다. 온디바이스 정책에서는 공급할 폰트를 명시하거나 remote provider를 배제해야 한다. 이번 테스트는 파싱과 Markdown만 실행하고 global fetch를 실패시키며 호출 수를 기록했다. 12개 모두 네트워크 호출 0이었다.

Node 26에서 기존 구형 샘플 12개를 실행했다. 행·열·그림·위치의 전체 정답 검증이 아니라 기존 마커와 공개 모델의 반환 관측값이다.

| 입력 | 표/셀 (FlowDoc) | 그림 배치/리소스 | 확인 문구 |
| --- | ---: | ---: | --- |
| LegacySample.doc | 1/2 | 1/1 | 전부 일치 |
| real-doc-01-SampleDoc.doc | 0/0 | 0/0 | 전부 일치 |
| real-doc-02-simple-table.doc | 1/6 | 0/0 | 전부 일치 |
| real-doc-03-pictures_escher.doc | 0/0 | 0/0 | 마커 없음 |
| LegacySample.xls | 2/228 | 1/1 | 전부 일치 |
| real-xls-01-mortgage-calculation.xls | 1/8 | 0/0 | 전부 일치 |
| real-xls-02-sumifs.xls | 8/226 | 0/0 | 전부 일치 |
| real-xls-03-testEXCEL-charts.xls | 2/879 | 0/0 | 마커 없음 |
| LegacySample.ppt | 0/0 | 1/1 | 전부 일치 |
| real-ppt-01-SampleShow.ppt | 0/0 | 0/0 | 전부 일치 |
| real-ppt-02-pictures.ppt | 0/0 | 4/4 | 마커 없음 |
| real-ppt-03-WithMaster.ppt | 0/0 | 0/0 | 전부 일치 |

자체 DOC는 표 2셀·이미지 1개, 실제 표 DOC는 6셀을 반환했다. 자체 XLS도 이미지 1개를 반환했다. 하지만 실제 DOC 그림 샘플은 기존 그림 2개 대비 리소스 0개이며, 자체 PPT의 표 2셀은 FlowDoc 표로 반환되지 않았다. PPT 그림 샘플의 4개 배치는 기존 파서의 2개 이미지와 개념이 달라 중복 또는 정확도 향상으로 단정하지 않는다. XLS의 FlowDoc 셀 수에는 인쇄 모델의 빈 셀·영역 분할이 들어가므로 원본 사용 셀 수와 동일한 지표가 아니다.

손실 정보는 읽기 손실과 Markdown 변환 손실을 구분해야 한다. 그림 링크 경고는 `images: link`로 테스트했기 때문에 생겼으며, ResourceStore에 바이트가 없다는 뜻이 아니다. DOC의 도형/text box/comments 제한은 reader가 보고했다. 전체 순서·좌표·메모리 제한·취소·한국어·손상 입력·iOS 실행은 미검증이다.

`npm ci --ignore-scripts`는 캐시 안에서만 실행했다. 설치 시 dev 포함 audit는 14개(10 moderate, 2 high, 2 critical)를 보고했고, 이어 실행한 `npm audit --omit=dev --json`의 런타임 결과는 0개였다. 후자를 보안 검증 완료로 해석하지 않는다. 자동 audit fix나 production lockfile 변경은 하지 않았다.

**판정:** 이번 신규 후보 중 사전 빌드 네이티브 바이너리 회피 목표에는 가장 가까워 추가 iOS 검증 가치가 있다. 기존 기능 유지가 확인된 대체재는 아니다.

## 2. JDoc: C++ 소스 + C API

- [공식 저장소](https://github.com/kiju7/JDoc), 자체 코드 MIT.
- 버전 1.6.3, 커밋 `4a08dc73ac07755308a3f2222d11c57f2ef54120`.
- `convert_chunks`, `for_each_chunk`, 메모리 입력과 C API를 제공한다. PageChunk에 text/tables/images, 이미지 인코딩 바이트와 raw pixels가 있다.
- C++17 기반이며 CMake로 macOS release 빌드에 성공했다. zlib·JPEG·libdeflate·pugixml·벤더 LZMA 등 전이 소스와 고지는 별도다. upstream CMake는 일부 의존성을 fetch하므로 이를 완성된 source-only SwiftPM 배포로 보지 않는다.
- 기존 12개를 min_image_size=0, tables/images=true로 실행했다. 운영 패키지에는 추가하지 않았다.

| 입력 | PageChunk 표/셀 | 반환 이미지 |
| --- | ---: | ---: |
| LegacySample.doc | 0/0 | 1 |
| real-doc-01-SampleDoc.doc | 0/0 | 0 |
| real-doc-02-simple-table.doc | 0/0 | 0 |
| real-doc-03-pictures_escher.doc | 0/0 | 0 |
| LegacySample.xls | 1/2 | 0 |
| real-xls-01-mortgage-calculation.xls | 1/8 | 0 |
| real-xls-02-sumifs.xls | 5/246 | 0 |
| real-xls-03-testEXCEL-charts.xls | 3/42 | 0 |
| LegacySample.ppt | 0/0 | 1 |
| real-ppt-01-SampleShow.ppt | 0/0 | 0 |
| real-ppt-02-pictures.ppt | 0/0 | 4 |
| real-ppt-03-WithMaster.ppt | 0/0 | 0 |

12개 모두 처리했고 제공된 문구 마커는 일치했다. **DOC 표는 Markdown 문자열에는 남았지만 PageChunk.tables는 비어 있었다.** 따라서 표 자체 미지원이라고 단정할 수는 없으며, Markdown을 다시 읽어 셀을 복구하는 보완이 가능할 수 있다. 그러나 원래 구조화 API와 위치 계약을 그대로 제공하는 것은 아니다.

실제 DOC 그림 샘플과 자체 XLS는 그림을 반환하지 못했고, 자체 PPT 표도 structured tables가 비었다. 기존 자체 HWP 2개(BinarySample/BinaryCompressed)도 본문·셀 마커는 읽었지만 tables/images는 모두 0이었다. 이 샘플들에는 기존 파서가 반환한 표·그림이 있으므로 완전한 HWP 대체로 판정하지 않는다. 모든 원본 HWP가 이렇게 동작한다고 일반화하지 않는다.

소스의 XLS 그림 배분에는 문서 그림을 시트에 분할하는 경로가 있어 정확한 원본 앵커와 일치하는지 별도 확인해야 한다. iOS 크로스 빌드·실행·스레드 안전성·자원 제한·OCR은 이번 미검증이다.

**판정:** 기존 프레임워크를 C++ 소스로 대체할 후보이지만, 현재 실행 결과로 Office/HWP 전체를 일괄 교체하면 기능이 줄어든다.

## 3. ONLYOFFICE core: PDF 대신 OOXML로 변환

[core 소스](https://github.com/ONLYOFFICE/core), [X2tConverter](https://github.com/ONLYOFFICE/core/tree/master/X2tConverter), [실제 binary 파서](https://github.com/ONLYOFFICE/core/tree/master/MsBinaryFile)를 Aside로 확인했다.

- DOC→DOCX: doc2docx → doc2docx_dir → COfficeDocFile::LoadFromFile.
- XLS→XLSX: xls2xlsx → ConvertXls2Xlsx.
- PPT→PPTX: ppt2pptx → COfficePPTFile::LoadFromFile.
- X2T_Convert C 진입점과 iOS의 build_x2t_as_library 분기가 있어 subprocess/서버가 반드시 필요한 구조는 아니다.

구형 문서를 OOXML로 만든 뒤 Swift 파서로 읽으면 PDF 우회보다 셀·관계 파일·이미지 앵커를 남길 가능성이 있다. 하지만 변환이 무손실이라는 검증은 없다. 공식 iOS SPM은 바이너리 XCFramework 방식이므로 그대로 쓰면 바이너리 회피 목표와 맞지 않는다. 직접 빌드에는 여러 format library·ICU·암호화 등 구성요소가 필요하다.

[원문 라이선스](https://github.com/ONLYOFFICE/core/blob/master/LICENSE)는 AGPL과 추가 고지를 포함한다. core를 전부 MIT로 재라이선스할 수 없다. 온디바이스라는 이유로 배포 의무가 사라지지 않는다. 상용 계약도 일반 웹 제품 계약을 네이티브 앱 소스 임베딩 권리로 해석해서는 안 되며 별도 확인이 필요하다. 이번에는 계약 문의·구매·설치·변환 실행을 하지 않았다.

## 4. Apache POI → J2ObjC → Swift

[POI 구성](https://poi.apache.org/components/index.html)의 HWPF/HSSF/HSLF는 구형 DOC/XLS/PPT 대상이다. [J2ObjC](https://developers.google.com/j2objc)는 Java 소스를 Objective-C로 번역해 iOS 앱에 포함한다. 주 라이선스는 둘 다 Apache-2.0이며 원문·NOTICE·전이 고지는 남는다.

공식 번역 도구가 존재한다는 사실과 POI 전체가 번역 가능하다는 것은 다르다. HSLF의 anchor가 java.awt.geom.Rectangle2D를 쓰며, J2ObjC JRE에서 필요한 AWT/geometry 범위를 보완해야 한다. reflection 자체는 J2ObjC가 지원하므로 그것만으로 불가능하다고 판단하지 않는다. 재현 가능한 POI→J2ObjC 완성 이식 사례는 확보하지 못했다. 로컬에는 JDK 17만 있고 최신 도구가 요구하는 JDK 21/J2ObjC는 설치하지 않았다. 빌드·테스트 미실행이다.

**판정:** 이미 완성된 라이브러리 추가가 아니라 포팅·런타임 관리 프로젝트다. 코드·유지보수 감소를 입증하기 전에는 권하지 않는다.

## 5. 상용 Apryse

[공식 iOS 변환 API](https://docs.apryse.com/ios/guides/features/office/convert-office)는 로컬 Office→PDF를 제공하고 PDF 요소에서 텍스트·이미지를 읽는 API도 있다. 그러나 이것은 원본 Excel/PPT DOM 추출과 다르다. 별도 레이아웃 리소스·폰트와 SDK 바이너리·상용 계약이 필요해 이번 목표의 개선으로 확정하지 않는다. trial 설치·비용 발생·외부 업로드는 하지 않았다.

## 우선순위

1. Ream의 **파싱만** iOS JavaScriptCore/WKWebView에서 실행해 호환 API, 오프라인, 메모리·취소·결과 순서와 누락을 측정한다. reader model을 직접 매핑하고 Markdown 재파싱은 가능한 한 피한다.
2. JDoc은 HWP/구형 Office의 확인된 누락을 해결할 수 있는지 API와 원본 파트별로 따로 확인한다. 지원 목록만 보고 LGPL 의존성을 제거하지 않는다.
3. 변환이 필요하면 ONLYOFFICE의 **OOXML 변환**을 PDF 변환과 별도 평가하되 라이선스·빌드 부담을 먼저 결정한다.
4. 실제 코드 감소는 Swift 어댑터·JS 번들·소스 제작·고지까지 포함해 회귀 통과 후 계산한다. 이번 순 코드 감소는 0줄이다.

## 로컬 재현 근거

루트: `${OMNI_RESEARCH_ROOT}`.

- `reamkit/legacy-probe.ts`, `reamkit-results.json`, `reamkit-probe.log`, `reamkit-runtime-audit.json`.
- `JDoc/probe-build/probe.cpp`, `jdoc-build.log`, `jdoc-results.json`, `jdoc-hwp-results.json`.
- `aside-new-methods.log`: ONLYOFFICE·POI·상용 SDK의 공식 API/소스/라이선스 웹 조사.
- 입력 원본/해시는 기존 `inputs.json`을 재사용했다. 새 외부 테스트 문서를 받거나 운영 저장소에 복사하지 않았다.

```bash
# Ream: 캐시 checkout, 설치 스크립트 실행하지 않음
npm ci --ignore-scripts
./node_modules/.bin/tsx legacy-probe.ts
npm audit --omit=dev --json

# JDoc: 캐시 checkout
cmake -S . -B probe-build -DCMAKE_BUILD_TYPE=Release
cmake --build probe-build -j 4
```

프로브로 보는 일부 마커 일치와 open 성공을 전체 정확도 통과로 표시하지 않는다. 이번에는 운영 iOS 빌드·린트·실기기 테스트를 실행하지 않았다. 커밋·푸시는 하지 않았다.
