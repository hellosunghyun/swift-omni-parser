# Apple Quick Look·WebKit Office 우회 정확도 검증

> 개인 절대 경로는 [로컬 검증 경로 별칭](RESEARCH_PATHS.md)으로 표기했다. 원시 로그·진단 덤프는 저장소에 포함하지 않는다.

검증일: 2026-10-26. **일부 DOC/PPT의 본문·이미지를 얻는 우회 경로는 실제로 동작했다. 그러나 XLS 누락·PPT 로드 실패·구조 손실이 있어 기존 파서 전체의 대체 경로로 채택하지 않는다.**

## 환경과 검증 범위

- Xcode 27.1 (27A9275), Swift 6.4, Swift 언어 모드 5.0.
- iPhone 17 / iOS 27.0 **시뮬레이터**. 실기기 결과가 아니다.
- 자체 생성 복합 DOC·XLS·PPT 3개 + 기존 로컬 POI/Tika 샘플 9개. 입력 SHA-256은 [앞선 비교](DOCREADER_EVALUATION.md)에 기록했다.
- 본문·표 문구·내장 이미지와 마지막 페이지 확인 문구를 가진 자체 HTML 대조군 1개.
- 새 외부 문서 다운로드·업로드·운영 의존성 변경 없음. 테스트 앱과 변환 PDF는 로컬 캐시에만 생성했다.
- OOXML·HWP·한글 문서·대용량 스캔의 정확도는 이번 표에 포함하지 않는다. 이 결과를 전체 지원 형식으로 일반화하지 않는다.

## 실행한 공개 API 경로

1. Quick Look: `QLPreviewController.canPreview`, `QLThumbnailGenerator` 및 자체 생성 DOC/XLS의 실제 preview 화면 확인.
2. WebKit 파일: `loadFileURL(_:allowingReadAccessTo:)`.
3. WebKit 데이터: `load(_:mimeType:characterEncodingName:baseURL:)`, Office MIME, UTF-8, 입력 디렉터리 baseURL. 이것은 확인한 한 가지 데이터 로드 구성이다.
4. 각 WebKit 로드에서 `createPDF` 기본 설정, `WKPDFConfiguration.rect = scrollView.contentSize` 설정, `viewPrintFormatter` → `UIPrintPageRenderer` → `UIGraphicsPDFRenderer`를 비교했다.
5. 생성 PDF를 PDFKit으로 검사하고, 파일 로드의 전체 영역/인쇄 PDF 24개(HTML 2개 포함)와 원래 Office 12개를 기존 OmniParser로 다시 읽었다. OCR은 끄고 이미지 추출은 켰다.

웹뷰는 화면에 부착했고 navigation 완료 뒤 0.7초를 기다렸다. HTTP(S) 리소스 차단 규칙과 navigation 차단을 설정했다. 썸네일·로드·PDF 생성은 8초 제한을 적용했다. 썸네일 timeout은 해당 제한 안에 완료되지 않았다는 뜻이며 영구 미지원 판정이 아니다.

인쇄 renderer는 공개 override로 A4 paper/printable rect를 제공했다. private API나 KVC를 사용하지 않았다. 이 페이지 설정은 원본 페이지 크기의 동등성을 보장하지 않는다. PDF 생성과 의미론적 표·셀 추출은 별개다.

## HTML 대조군

파일·데이터 로드 모두 본문·셀·마지막 페이지 확인 문구 3개와 그림 1개를 PDF에 유지했다. 기본/전체 영역 PDF는 긴 페이지 1개, 인쇄 경로는 3페이지였다. PDF 검사·인쇄 코드가 항상 빈 문서를 반환하는 문제가 아님을 확인했다.

## 구형 Office: 파일 URL + 인쇄 PDF 재파싱

| 입력 | 전체 텍스트 문자: 직접 → 우회 | 직접 결과 대비 토큰 재현율 | 셀 블록: 직접 → 우회 | PNG: 직접 → 우회 |
| --- | ---: | ---: | ---: | ---: |
| LegacySample.doc | 40 → 40 | 100.0% | 2 → 0 | 1 → 1 |
| real-doc-01-SampleDoc.doc | 135 → 137 | 100.0% | 0 → 0 | 0 → 0 |
| real-doc-02-simple-table.doc | 237 → 236 | 100.0% | 6 → 0 | 0 → 0 |
| real-doc-03-pictures_escher.doc | 842 → 842 | 100.0% | 0 → 0 | 2 → 2 |
| LegacySample.xls | 37 → 36 | 66.7% | 2 → 0 | 1 → 0 |
| real-xls-01-mortgage-calculation.xls | 51 → 63 | 85.7% | 7 → 0 | 0 → 3 |
| real-xls-02-sumifs.xls | 3501 → 487 | 13.1% | 195 → 8 | 0 → 5 |
| real-xls-03-testEXCEL-charts.xls | 45 → 37 | 0.0% | 12 → 0 | 0 → 3 |
| LegacySample.ppt | 40 → 40 | 100.0% | 2 → 0 | 1 → 1 |
| real-ppt-01-SampleShow.ppt | 219 → 225 | 100.0% | 0 → 0 | 0 → 0 |
| real-ppt-02-pictures.ppt | Office 로드 실패 | — | — | — |
| real-ppt-03-WithMaster.ppt | 121 → 159 | 100.0% | 0 → 0 | 0 → 0 |

**수치 해석:** 직접 결과는 기준 비교값이며 사람이 작성한 전체 문서 정답은 아니다. 토큰 재현율은 소문자화·공백 분리 후 해시별 다중집합 교집합/직접 토큰 수다. 순서·정밀도·레이아웃·한글 인식 정확도를 평가하는 지표가 아니다. 특히 자체 XLS는 셀 경계 공백이 합쳐져 토큰 점수가 낮아져도 두 확인 문구는 모두 남았다. 이를 본문 33.3% 소실로 해석하면 안 된다. 기준 결과가 잘못됐거나 생략한 내용이 있으면 이 지표도 영향을 받는다.

### DOC

- 인쇄 경로 4개 모두 직접 추출 토큰을 유지했다. 그림 샘플은 2개가 남았고 자체 DOC는 1개가 남았다.
- 다만 자체 DOC의 2개 셀과 실제 표 DOC의 6개 셀은 PDF 재파싱에서 0개 셀로 바뀌었다. **표 문구가 남는 것과 행·열·병합 구조를 유지하는 것은 다르다.**
- `createPDF`의 전체 영역 설정은 실제 표 DOC에서 83.3%, 그림 DOC에서 75.7%의 토큰 재현율이었다. scrollView의 contentSize가 모든 Office 페이지를 담는다고 가정하면 안 된다.

### XLS

- 자체 XLS의 본문·셀 확인 문구는 남았지만 원래 그림 1개는 PDF에 없다. 실제 Quick Look 화면에서도 이 그림을 확인하지 못했다.
- 다중 시트 sumifs는 직접 추출 195개 셀·3,501자 대비 인쇄 우회 8개 셀·487자로 줄고, `Bedrooms` 확인 문구가 빠졌다. 선택된 시트/영역에 한정될 가능성이 있으나 모든 원인을 구현 계약으로 단정하지 않는다.
- charts 샘플의 기준 토큰은 출력에 남지 않았다. PDF의 이미지 자산 수가 늘어도 셀·삽입 이미지가 더 정확해졌다는 뜻은 아니다. 시트 전환 UI 등의 그래픽이 포함될 수 있다.
- 이 경로는 전체 workbook 추출 대체로 부적합하다.

### PPT

- 4개 중 3개가 인쇄 PDF 생성에 성공했고 직접 추출 토큰은 유지했다. 추가 문자열과 개행 차이는 남으므로 완전 동일 결과는 아니다.
- 자체 PPT의 원래 2개 셀은 0개로 바뀌었다. `createPDF` 전체 영역은 여러 슬라이드 샘플에서 기준 토큰의 23.8%·33.3%만 남았고 인쇄 경로가 더 나았다.
- pictures.ppt는 `OfficeImportErrorDomain` code 912로 로드 실패했다. 기존 파서는 이 파일에서 그림 2개를 반환했다.

## 이미지 자체 보존과 재래스터화 구분

자체 DOC와 PPT의 인쇄 PDF에서 이미지 XObject를 직접 조사했다.

- 원본 PNG: 1200×240.
- PDF 내부 이미지: 둘 다 1200×240, 8-bit RGB.
- 원본과 PDF stream을 디코딩해 같은 sRGB RGBA 형식으로 정규화한 픽셀 SHA-256은 둘 다 일치했다.
- 해시: `c5957eb023da654a3e194acbb1d36bb0d3c39f7725c720f14499984570f1a305`.

반면 OmniParser의 PDF 이미지 API는 표시 영역을 PNG로 래스터화하므로 이 PDF를 다시 읽어 반환한 PNG는 크기·해시가 달랐다. 이것을 WebKit에서 원본 이미지가 소실되거나 저해상도화됐다는 증거로 쓰지 않는다. 픽셀 동등성은 위 자체 샘플 2개에 한정하며 전체 코퍼스 모든 그림에 대한 검증은 아니다.

## MIME 데이터 로드 결과

검증한 데이터 로드 구성에서는 일부 Office 입력이 바이너리 내용을 문자로 렌더링하는 결과, 빈 PDF, WKErrorDomain 오류가 나왔다. 문자열 앵커가 raw binary 안에 그대로 있어 우연히 일치하는 경우도 있어 확인 문구 포함 여부만으로 성공 처리하지 않았다. HTML 대조군은 정상이다. 이번 결과는 `loadFileURL`과 데이터 로드의 Office 처리를 동일하다고 가정할 수 없음을 보여준다. 모든 가능한 MIME/baseURL 조합의 불가능성을 증명한 것은 아니다.

## Quick Look 결과와 한계

- 구형 12개 모두 `canPreview == true`였지만, 그중 PPT 하나는 WebKit importer에서 실제 로드 실패했다. 지원 여부 Bool은 추출 정확도 검사가 아니다.
- 8초 제한에서 썸네일은 3개 성공, 3개 오류, 6개 timeout이었다. HTML 대조군도 timeout이었다. 공급자 초기화·시뮬레이터 환경 영향을 배제하지 못했으므로 이 수치로 Quick Look의 제품 정확도를 단정하지 않는다.
- 자체 DOC preview 화면에는 본문·셀 문구·이미지가 보였다. 자체 XLS preview에는 문구가 보였지만 그림은 확인되지 않았다.
- 자체 PPT 추가 preview 캡처는 앱 실행/캡처 요청이 수분 지연되고 흰 화면만 확보돼 **화면 정확도 미검증**이다. PPT 썸네일에서는 두 확인 문구가 인식됐지만 전체 문서 검증이 아니다. 이 환경 지연을 파서 결함으로 단정하지 않는다.
- Quick Look의 공개 preview/thumbnail API 자체로 본문·표 셀·원본 이미지·앵커를 모두 반환하는 경로를 구현한 것은 아니다. 썸네일 OCR은 첫 화면의 근사 텍스트일 뿐 원본 구조 추출과 다르다.

## 실패 사례 재확인

원래 혼합 실행 뒤 별도 `--retry` 실행에서 MIME 경로·썸네일을 제외하고, 파일 로드 뒤 3초로 대기 시간을 늘려 다음 3개를 다시 확인했다.

- 자체 XLS: 이미지 0개가 반복됨.
- sumifs.xls: 동일한 확인 문구 누락과 인쇄 PDF 488자(PDFKit 문자열 기준)가 반복됨.
- pictures.ppt: 동일한 importer code 912가 반복됨.

PDFKit 문자열 488자와 OmniParser fullText 487자처럼 정리 방식에 따라 개수는 다를 수 있다. 원래 실행과 재실행의 raw text SHA도 비교했다. 추가 대기가 위 실패를 해결하지 않았다.

## 실행 근거와 재현

로컬 루트: `${OMNI_RESEARCH_ROOT}/`.

- `AppleOfficeProbe/project.yml`, `App/Probe.swift`: 별도 UIKit 검증 앱. 운영 패키지에 포함하지 않음.
- `AppleOfficeResults/results.json`: 13개 입력 × 두 로드 방식 × 세 출력 경로의 관측 결과와 오류.
- `AppleOfficeResults/Retry/`: 실패 사례의 파일 전용 재실행.
- `AppleOfficeResults/*.pdf`: 생성 PDF. 원본 파일은 변경하지 않았다.
- `AppleOfficeResults/quicklook-doc.jpg`, `quicklook-xls.jpg`, `quicklook-ppt.jpg`: 실제 캡처. PPT 흰 화면은 미검증 근거로만 보존.
- `apple-roundtrip.log`, `apple-pixels.log`: 원본 12개 + 생성 PDF 24개, 각각 iOS XCTest 1개 안에서 36문서 실행. 두 실행 모두 TEST SUCCEEDED. 코퍼스 정확도 36/36 통과를 뜻하지 않는다.
- `apple-roundtrip-results.json`, `apple-roundtrip-comparison.json`, `apple-pixels-results.json`: 비교용 해시·토큰 수·셀 수·그림 수.
- `inspect-pdf-images.swift`, `compare-pdf-pixels.swift`, `apple-raw-image-pixels.txt`: raw 이미지 해상도와 픽셀 대조.

```bash
# 검증 앱 생성
cd ${OMNI_RESEARCH_ROOT}/AppleOfficeProbe
xcodegen generate
xcodebuild build -project AppleOfficeProbe.xcodeproj -scheme AppleOfficeProbe \
  -destination 'platform=iOS Simulator,id=46BECA1F-89C4-42E2-B9DD-5F6CB316E62B'

# 실제 실행은 XcodeBuildMCP build_run_sim 및 launch_app_sim 사용
# 실패 사례 재실행 시 앱 launchArgs: --retry
# Quick Look 자체 샘플 화면: --preview LegacySample.doc

# 원본/변환 PDF 비교용 별도 복제본
cd ${OMNI_RESEARCH_ROOT}/OmniProbe
xcodebuild test -scheme OmniParser \
  -destination 'platform=iOS Simulator,id=46BECA1F-89C4-42E2-B9DD-5F6CB316E62B' \
  -skipMacroValidation -parallel-testing-enabled NO
```

최초 앱 빌드의 CGPDF optional 처리와 리소스 복사 설정 오류를 수정한 뒤 정상 실행했다. 비동기 미완료를 방지하는 제한 시간도 추가했다. 생산 Swift 코드가 바뀌지 않아 운영 빌드·린트는 다시 실행하지 않았다. 커밋·푸시는 하지 않았다.

## 적용 판단

**file URL → 인쇄 PDF → PDF 파서**는 검증한 일부 DOC/PPT에서 로컬 fallback 후보가 될 수 있다. 하지만 XLS 전체 workbook, 원본 표 구조·앵커, 모든 PPT, 일관된 읽기 순서를 보장하지 못한다. 메인 스레드·window/view lifecycle 의존성도 생긴다. 현재 파서의 형식 지원을 이 경로로 일괄 교체하지 않는다. 채택하려면 실기기, 한국어, OOXML, 다중 시트·슬라이드, 암호화·손상·취소·대용량 메모리까지 별도 회귀가 필요하다.
