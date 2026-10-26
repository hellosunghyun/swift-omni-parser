# DocReader 구형 Office 대체 검증

> 개인 절대 경로는 [로컬 검증 경로 별칭](RESEARCH_PATHS.md)으로 표기했다. 원시 로그·진단 덤프는 저장소에 포함하지 않는다.

검증일: 2026-10-26. **결론: 현재 버전으로는 OmniParser의 구형 Office 추출 엔진을 대체하지 않는다.** 지원 확장자와 실제 본문·표·그림 추출 범위가 다르다. 운영 의존성·소스·바이너리는 변경하지 않았다.

## 기준과 환경

- DocReader: `d9d1c88534a05aa5c84d20c08e593482ee03db15`를 별도 캐시에 복제했다. 생산 패키지에 추가하지 않았다.
- OmniParser: `ddc987b24e5489e633188db03c7028bb8c3a9bfe`의 별도 복제본에 검증 전용 XCTest 타깃을 추가했다.
- Xcode 27.1 (27A9275), Apple Swift 6.4. OmniParser의 iOS 27.0·Swift 언어 모드 5는 유지했다.
- 후보 전체 12개 비교는 macOS에서 실행했다. 기존 파서 전체 12개와 후보 자체 샘플 3개는 iPhone 17 / iOS 27.0 시뮬레이터에서 확인했다. 실기기·성능 비교는 수행하지 않았다.
- 자체 생성 복합 샘플 3개와 기존 로컬 POI/Tika 자산 9개를 읽었다. 새 외부 문서 다운로드·저장소 자산 추가·문서 업로드는 하지 않았다. 기존 자산의 출처와 고지는 원래 저장소에 보존했다.

## 소스 확인

DocReader의 공개 `DocReadable`은 페이지 수·크기·메타데이터·PDF 및 인쇄 출력 API를 제공한다. 본문·표 셀·원본 그림 반환 API는 없다. 구형 세 파서는 내부 `DocContentProviding`에도 적합하지 않아 `PDFExporter`에서 `renderPlaceholder`로 들어간다. PDF로 우회해도 원본 본문·표·그림을 복원할 수 없는 구조다.

- [구형 DOC](https://github.com/germanhl36/DocReader/blob/d9d1c88534a05aa5c84d20c08e593482ee03db15/Sources/DocReader/Parsers/Legacy/DOCLegacyParser.swift): 속성 스트림 기반 페이지 수·메타데이터.
- [구형 XLS](https://github.com/germanhl36/DocReader/blob/d9d1c88534a05aa5c84d20c08e593482ee03db15/Sources/DocReader/Parsers/Legacy/XLSLegacyParser.swift): BOUNDSHEET 레코드 개수. 셀 값 추출 경로 없음.
- [구형 PPT](https://github.com/germanhl36/DocReader/blob/d9d1c88534a05aa5c84d20c08e593482ee03db15/Sources/DocReader/Parsers/Legacy/PPTLegacyParser.swift): 레코드 개수·크기. 도형 텍스트·그림 추출 경로 없음.
- [PDF 출력](https://github.com/germanhl36/DocReader/blob/d9d1c88534a05aa5c84d20c08e593482ee03db15/Sources/DocReader/Rendering/PDFExporter.swift): 구형 형식에 자리표시자 사용.

## 실제 결과

기존 파서는 `extractImages: true, performOCR: false`로 실행했다. 문자는 `fullText.count`, 셀은 `tableCell` 블록 수, 이미지는 반환된 PNG 수다. 전체 문서 정답을 확정한 수치가 아니라 이번 실행의 관측값이다.

| 입력 | DocReader PDF 문자열 / 실패 | 기존 파서 문자 | 기존 파서 셀 | 기존 파서 이미지 |
| --- | --- | ---: | ---: | ---: |
| LegacySample.doc | Page 1 | 40 | 2 | 1 |
| real-doc-01-SampleDoc.doc | 10초 제한 초과 | 135 | 0 | 0 |
| real-doc-02-simple-table.doc | 10초 제한 초과 | 237 | 6 | 0 |
| real-doc-03-pictures_escher.doc | Page 1 | 842 | 0 | 2 |
| LegacySample.xls | Sheet 1 | 37 | 2 | 1 |
| real-xls-01-mortgage-calculation.xls | Sheet 1 / Sheet 2 / Sheet 3 | 51 | 7 | 0 |
| real-xls-02-sumifs.xls | corruptedFile | 3501 | 195 | 0 |
| real-xls-03-testEXCEL-charts.xls | corruptedFile | 45 | 12 | 0 |
| LegacySample.ppt | Slide 1 | 40 | 2 | 1 |
| real-ppt-01-SampleShow.ppt | Slide 1 | 219 | 0 | 0 |
| real-ppt-02-pictures.ppt | Slide 1 | 0 | 0 | 2 |
| real-ppt-03-WithMaster.ppt | Slide 1 | 121 | 0 | 0 |

- DocReader: 8개가 PDF를 만들었지만 문자열은 `Page N`·`Sheet N`·`Slide N`뿐이다. 원문 확인 문구는 모두 누락되었고, 성공한 PDF의 페이지 Resources/XObject 항목 수는 모두 0이었다. 나머지 2개 XLS는 `corruptedFile`, 2개 DOC는 10초 제한 초과로 종료했다. 제한 초과를 무한 루프로 단정하지 않는다.
- 제한 초과 샘플의 프로세스 샘플에는 PDF 출력 중 페이지 크기 계산과 OLE 재열기 경로가 관측됐다. 원인 규명이나 후보 수정은 이번 대체 가능성 검증에 포함하지 않았다.
- 기존 파서: 12개 모두 완료. 제공된 텍스트 확인 문구는 모두 일치했다. 자체 생성 세 형식 각각에서 본문·표 셀 2개·이미지 1개가 남았다. DOC/PPT 그림 샘플에서도 각각 2개가 반환됐다. 그림만 있는 PPT의 본문 0자는 OCR을 끈 결과다.
- 후보의 자체 생성 세 형식은 iOS에서도 자리표시자만 반환하는지 별도 검증했다. 해당 특성 검증의 통과는 추출 기능 통과를 뜻하지 않는다.

## 빌드·테스트

캐시 기준 디렉터리: `${OMNI_RESEARCH_ROOT}`.

```bash
# DocReader 원본 테스트 (검증용 테스트 추가 전)
cd ${OMNI_RESEARCH_ROOT}/DocReader
swift test

# 후보 iOS 빌드
xcodebuild build -scheme DocReader -destination 'generic/platform=iOS Simulator'

# 후보 자체 생성 샘플의 iOS 특성 검증
xcodebuild test -scheme DocReaderIntegrationTests \
  -destination 'platform=iOS Simulator,id=46BECA1F-89C4-42E2-B9DD-5F6CB316E62B' \
  -only-testing:DocReaderIntegrationTests/LegacyIOSProbe -parallel-testing-enabled NO

# 기존 파서 비교 복제본
cd ${OMNI_RESEARCH_ROOT}/OmniProbe
xcodebuild test -scheme OmniParser \
  -destination 'platform=iOS Simulator,id=46BECA1F-89C4-42E2-B9DD-5F6CB316E62B' \
  -skipMacroValidation -parallel-testing-enabled NO
```

원본 macOS 테스트: 단위 81개, 통합 45개 중 4개 skip, 실패 0. 누락 자산으로 skip된 경우를 통과로 계산하지 않았다. 원본 테스트는 페이지 수·PDF 출력 등의 검증이며 구형 본문·표·그림 추출 정확도를 증명하지 않는다.

후보 manifest는 `DocReader` 빌드 scheme과 `DocReaderIntegrationTests` 테스트 scheme을 구분한다. `DocReader`로 test를 시도한 최초 실행은 테스트 action이 없어 실패했고 올바른 scheme으로 재실행했다. 원본의 deprecated API 경고는 남았다. 생산 Swift 코드 변경이 없어 린트는 재실행하지 않았다.

macOS 파일별 비교는 추가한 `LegacyReplacementProbe/testExistingLegacyCorpus`를 `DOC_PROBE_INPUT` 환경변수로 선택해 별도 xctest 프로세스에서 실행했다. 각 프로세스의 10초 제한은 외부 Python 실행기가 적용했다. 입력 manifest·파일별 SHA-256·수집 JSON·테스트 소스·전체 로그·xcresult는 위 로컬 캐시에 남겼다. 이 문서만으로 새 clone에서 검증할 수 있는 영구 테스트 자산 구성은 아니다.

## 의존성·라이선스와 적용 판단

[DocReader 원문 LICENSE](https://github.com/germanhl36/DocReader/blob/d9d1c88534a05aa5c84d20c08e593482ee03db15/LICENSE)는 MIT다. 외부 구성요소까지 MIT로 바뀌는 것은 아니며 ZIPFoundation·OLEKit 등의 원래 고지는 유지해야 한다. 이번에는 코드를 복사하거나 패키지를 추가하지 않았다.

후보 manifest는 OLEKit `0.2.x`를 요구하고 현재 OmniParser는 `0.3.1`을 고정한다. 그대로 함께 추가하면 요구 범위가 겹치지 않는다. 버전 조정만으로 본문·표·그림 기능 부재가 해결되지는 않는다.

**순 코드 감소: 0줄.** 구형 Office 기능을 유지하려면 본문·셀·그림 파싱을 새로 구현해야 하므로, 이 후보로 OfficeOxide/OpenDocument.core 바이너리를 제거하지 않는다. 이번 결과는 Swift 기반 대체재 전체가 불가능하다는 뜻이 아니라 검증한 후보·리비전의 한계다.

## 입력 식별

| 파일 | SHA-256 |
| --- | --- |
| LegacySample.doc | `2b069901ca3dc54a499c5a2f3067d88660900a6367d1bfa03e8165d3df4bd747` |
| real-doc-01-SampleDoc.doc | `717585c0a88f20862c86220163dd03da87cd743970354c6b29add32725f2e833` |
| real-doc-02-simple-table.doc | `67d7fe8e0555c16516354498a5935f24eeef90beb5efbf526f93a1d6c734da43` |
| real-doc-03-pictures_escher.doc | `84a68678fc525e763beabab7e79240e2bbf4cd6b7766eed3364681d38fed2457` |
| LegacySample.xls | `be3eddd8b58cd2784bc2145d637d4a2d99338395d8db9c1e5581e261e6825e95` |
| real-xls-01-mortgage-calculation.xls | `271c06d988bfe033afdc69733c5ba09e95658ebff571bfca189b567e678631dc` |
| real-xls-02-sumifs.xls | `ed34698a6c9bd269acb80874e820edd8cdbd246a3f939544a44ebeb3d2cb888c` |
| real-xls-03-testEXCEL-charts.xls | `33f08ed32503437615af7ca8d5413ffa22df33ceb6765c51e200039f71452f6a` |
| LegacySample.ppt | `fcff02696fc357b4068fe73f3b25e12f42b4cd75d24158114c5cbd15592e2200` |
| real-ppt-01-SampleShow.ppt | `64275a6685b8f267827178037dcc59de927475e56385725916f4c6039c7ce7f6` |
| real-ppt-02-pictures.ppt | `5318e8486f47c7d9e838eaa4edfe385ba27d7d0ce145364792df53488430e98c` |
| real-ppt-03-WithMaster.ppt | `307cb62b279b1b1014058f26866d905e1f80ac649ecedeb63604371d807233dd` |
