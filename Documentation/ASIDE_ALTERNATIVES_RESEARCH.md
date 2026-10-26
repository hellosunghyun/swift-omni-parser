# Aside CLI 추가 조사: 소스·JS·WASM·Apple 변환 경로

조사일: 2026-10-26. Aside CLI 1.26.1023.1115, 세션 `t5qGajxMXZIOjvnU`로 공식 문서와 실제 소스를 웹에서 조사했다. 이 단계는 빌드·실행 검증이 아니다. 기존 [엔진 실행 비교](LEGACY_ENGINE_RESEARCH.md)와 구분한다.

## 결론

기존 엔진을 교체하는 방법 외에도 소스 직접 컴파일, JS 실행, WASM 실행, 대형 문서 엔진의 로컬 PDF 변환 경로가 있다. 하지만 요구한 본문·표·그림·원본 위치와 취소·제한·경고를 모두 유지하면서 간단히 교체할 새 완성품은 확인하지 못했다.

| 방법 | 새로 확인한 근거 | 남는 비용·제약 | 권고 |
| --- | --- | --- | --- |
| wv2 C++ 소스 + Swift 브리지 | DOC 문단·셀·그림 콜백, 메모리 입력 | LGPL 계열 파일별 혼재, 오래된 의존성, floating object 미구현, iOS 미빌드 | DOC 후보로 격리 검증 가능 |
| docstream legacy 모듈 + JavaScriptCore | DOC 본문·표 AST, PPT 텍스트·노트 | Node Buffer 등 shim 필요, 그림·PPT 표·좌표 누락 | 기존 그림 보완과 조합할 실험 후보 |
| 문서 엔진 WASM + WKWebView/인터프리터 | wasm3 공식 iOS 예제, WebKit의 JIT 없는 Wasm 지원 | 문서 엔진은 별도 필요, WASM 파일은 여전히 바이너리, 메모리·호스트 ABI·성능 검증 | 사전 빌드 네이티브 XCFramework 대안이지 바이너리 제거 수단은 아님 |
| LibreOffice core + LibreOfficeKit 정적 임베딩 | 공식 iOS 소스 설정, 앱 내부 load/saveAs PDF API | 대형 엔진·리소스·폰트·전이 고지, iOS 27 빌드 미검증 | 복원 충실도가 엔진 경량화보다 중요할 때 고려 |
| Apple 공개 API로 Office→PDF 우회 | WKWebView.createPDF, 인쇄 formatter와 PDF renderer | Office 입력 계약 미확인, 의미론적 표·원본 그림·앵커 보존 보장 없음 | 실제 출력 확인 전 채택 불가 |

## 1. wv2: DOC에 실제 저수준 추출 API가 있다

[ParserFactory](https://svn.code.sf.net/p/wvware/svn/wv2-trunk/src/parserfactory.h)는 파일 및 메모리 입력 파서를 생성한다. [parser.h](https://svn.code.sf.net/p/wvware/svn/wv2-trunk/src/parser.h)에서 Text/Table/Picture/SubDocument handler를 설치한다.

[handlers.h](https://svn.code.sf.net/p/wvware/svn/wv2-trunk/src/handlers.h)에 다음 경로를 확인했다.

- paragraphStart/End, runOfText
- tableRowFound 및 tableRowStart/End, tableCellStart/End
- pictureFound, bitmapData, wmfData, escherData

그림 콜백의 reader는 콜백 안에서 바이트를 복사해야 한다. PICF의 크기·crop, TAP의 셀 경계는 제공되지만 정확한 원본 CP 범위·페이지 배치가 기본 콜백에 모두 노출되는 것은 아니다. [parser9x.cpp](https://svn.code.sf.net/p/wvware/svn/wv2-trunk/src/parser9x.cpp)의 emitDrawnObject는 TODO 경로라 floating drawing 지원을 완성된 것으로 설명할 수 없다.

라이선스는 LGPL-2.0-only, LGPL-2.0-or-later, LGPL-2.1-only가 확인한 파일들에 혼재한다. 단순히 MIT 또는 LGPL-2.1 하나로 재표기하면 안 된다. [COPYING.LIB](https://svn.code.sf.net/p/wvware/svn/wv2-trunk/COPYING.LIB), 개별 헤더와 zcodec.cxx 고지를 추가 검토해야 한다.

[INSTALL](https://svn.code.sf.net/p/wvware/svn/wv2-trunk/INSTALL)은 일반 Mac/Unix와 cross compilation 설명이며 iOS 27 검증이 아니다. libgsf/glib/iconv/zlib와 SHARED 중심 CMake를 조정해야 한다. 직접 구현량 감소가 가능한지보다 이식·유지보수 코드가 늘어날 가능성도 계산해야 한다.

관련 제외 후보: [AbiWord/wv](https://github.com/AbiWord/wv)는 그림 출력 예제가 있으나 GPL-2.0-or-later와 오래된 빌드 체계가 부담이다. [catdoc](https://github.com/vbwagner/catdoc)은 DOC/XLS/PPT 텍스트 중심 CLI이며 구조·그림·위치 계약을 충족하지 못한다.

## 2. docstream: JS 소스로 배포할 수 있지만 기능 공백이 있다

[legacy DOC](https://github.com/joseespana/docstream/blob/master/src/parsers/legacy/doc.ts)의 parseDoc은 WordDocument와 piece table을 읽고 row/col을 포함하는 표 AST를 만든다. 최종 attachments는 빈 배열이며 삽입 그림을 추출하는 구현을 확인하지 못했다.

[legacy PPT](https://github.com/joseespana/docstream/blob/master/src/parsers/legacy/ppt.ts)의 parsePpt는 slide text와 notes를 반환한다. 그림·표 셀·shape 좌표의 완전한 추출기는 아니다.

[브라우저 번들](https://github.com/joseespana/docstream/blob/master/build_browser.js)은 Node Buffer 등 polyfill과 window/setTimeout을 사용한다. browser bundle을 독립 JSContext에 그대로 넣어 동작한다고 볼 수 없다. 필요한 legacy 모듈만 번들링하고 호스트 기능을 제한한 뒤 실제 실행해야 한다. MIT 원문과 소스 내 알고리즘 출처 고지를 별도로 보존해야 한다. iOS 실행은 이번에 하지 않았다.

[SheetJS parse options](https://docs.sheetjs.com/docs/api/parse-options/)는 셀 데이터 중심이다. [Pro Image](https://www.sheetjs.com/pro)에 그림·shape 기능이 안내되지만, CE의 구형 XLS 이미지·앵커 추출 기능이나 Pro 소스 재배포 권한을 보장하는 근거는 아니다. 이번에는 JS XLS로 바꾸어 그림까지 해결된다고 판단하지 않았다.

## 3. WASM: 실행 방법과 문서 파서는 별개다

[wasm3 iOS 예제](https://github.com/wasm3/wasm3/blob/main/platforms/ios/README.md)에는 Xcode 프로젝트와 m3_ParseModule/LoadModule/CallV 사용 예가 있다. MIT 인터프리터지만 문서 파서가 아니다. 엔진의 exports, 파일·메모리 imports, Emscripten glue, SIMD/thread/exception 사용 여부를 맞춰야 하며 프로젝트는 최소 유지보수 상태를 명시한다.

[WebKit Safari 18.4 발표](https://webkit.org/blog/16574/webkit-features-in-safari-18-4/)는 JIT가 꺼져도 Wasm 실행이 가능하다고 안내한다. 따라서 iOS는 JIT 제한이 있으니 Wasm이 전부 불가능하다는 결론은 부정확하다. 반대로 WebKit main의 지원을 iOS 27 독립 JSContext의 실제 노출·동작으로 단정해서도 안 된다. JSContext/WKWebView 각각에서 실제 instantiate와 대표 문서 실행을 확인해야 한다.

WASM으로 바꾸어도 .wasm 자산은 컴파일된 바이너리다. 소스 저장소에 바이너리를 두지 않으려면 생성/배포 체계가 여전히 필요하다. 여러 입력의 복사·직렬화·WebView IPC·OCR 이미지 전달 비용도 측정해야 한다.

## 4. LibreOfficeKit: 서버 없이 iOS 프로세스 내부 변환이 가능하다

공식 소스 [iOS distro config](https://github.com/LibreOffice/core/blob/master/distro-configs/LibreOfficeiOS.conf), [iOS setup](https://github.com/LibreOffice/core/blob/master/ios/CustomTarget_iOS_setup.mk), [LibreOfficeKitInit.h](https://github.com/LibreOffice/core/blob/master/include/LibreOfficeKit/LibreOfficeKitInit.h)에 iOS 정적 연결과 직접 초기화 경로가 있다. 서버나 soffice subprocess를 반드시 요구하는 설계가 아니다.

[LibreOfficeKit.hxx](https://github.com/LibreOffice/core/blob/master/include/LibreOfficeKit/LibreOfficeKit.hxx)의 documentLoad와 saveAs PDF, [TDF 변환 예제](https://dev.blog.documentfoundation.org/2024/07/25/libreofficekit-for-document-conversion/)가 실제 API 근거다. DOC97/XLS97/PPT97 필터와 PPT 표 모델 생성 구현도 확인됐다.

다만 PDF 생성은 원본 semantic table/image/anchor 반환과 다르다. extractDocumentStructureRequest도 모든 Calc/PPT 표·이미지·좌표를 동일하게 JSON으로 반환하는 API로 확인되지 않았다. 완전한 구조 추출은 UNO/C++ 모델 순회나 추가 어댑터가 필요하다.

[라이선스 안내](https://www.libreoffice.org/about-us/licenses/)는 MPL 기반과 외부 구성요소의 다양한 조건을 구분한다. iOS 정적 아카이브·ICU·registry·filter·font 등까지 빌드·고지·리소스를 관리해야 한다. 이번 목표의 작은 소스 패키지를 만들려다가 대형 엔진 배포 프로젝트가 될 수 있다. iOS 27 실빌드·메모리·PDF 출력 결과는 미검증이다.

## 5. Apple 공개 API 우회

- [Quick Look](https://developer.apple.com/documentation/quicklook/qlpreviewcontroller)은 미리보기 API다. 지원 여부가 원본 구조·그림 추출 API의 존재를 의미하지 않는다.
- NSAttributedString의 [.docFormat](https://developer.apple.com/documentation/foundation/nsattributedstring/documenttype/docformat)과 [.officeOpenXML](https://developer.apple.com/documentation/foundation/nsattributedstring/documenttype/officeopenxml)은 확인한 문서에서 macOS 지원 항목이다. initializer 전체의 iOS availability를 각 Word importer에 적용하면 안 된다.
- [WKWebView.createPDF](https://developer.apple.com/documentation/webkit/wkwebview/createpdf(configuration:completionhandler:))는 웹뷰 콘텐츠의 PDF 생성 API다. Office native preview 전체의 PDF 변환을 보장한다는 근거는 확보하지 못했다.
- viewPrintFormatter → UIPrintPageRenderer → UIGraphicsPDFRenderer도 실험 경로다. Office 입력·전체 페이지·원문 보존 여부는 실제 iOS 결과로 확인해야 한다. private API/KVC로 내부 속성을 바꾸는 방법은 제안하지 않는다.

PDF 우회는 성공하더라도 표 구조를 다시 추정하고 이미지를 다시 추출해야 하므로 기존 결과 모델의 정확도·순서·중복·옵션을 유지하는지 별도 비교가 필요하다.

## 제안 순서

1. 기존 조사에서 컴파일된 libxls의 SwiftPM 소스 연결과 기존 그림 보완을 XLS에서 검증한다.
2. DOC는 wv2의 라이선스·의존성 이식 비용과 docstream+기존 그림 보완의 두 경로를 작은 격리 실험으로 비교한다.
3. PPT는 검증된 기존 엔진을 유지하며, 전체 엔진을 바꾸려면 LibreOfficeKit의 실제 빌드·용량·메모리를 먼저 측정한다.
4. WASM이나 Apple PDF 우회는 자동으로 더 작고 간단해지는 해결책으로 채택하지 않는다. 동작·추출 결과·중간 복사량을 먼저 확인한다.

이번 단계에서 운영 의존성·소스·원래 LICENSE는 변경하지 않았다. 원본 Aside 로그와 상세 조사 결과는 로컬 캐시에 보존했다. 커밋·푸시는 하지 않았다.
