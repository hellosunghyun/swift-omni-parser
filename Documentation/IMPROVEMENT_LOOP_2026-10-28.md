# 메모리·OCR 정확도 개선 루프

기준 `26087b2`. 2026-10-28, Mac mini M4·16GiB·Xcode 27.1·iPhone 17 / iOS 27.0 Simulator에서 검증했다. 실기기 없이 공개 API와 한영·정확도·위치·취소·자원 제한을 확인하며 새 의존성이나 OS·Swift 언어 모드를 추가·변경하지 않는다. 아래 후보의 정확도 향상과 메모리 감소는 별도 조건이다.

## 겹친 PDF 그림의 OCR 중복

같은 페이지의 같은 그림을 같은 위치에 두 번 표시하면, 각 그림 OCR이 네이티브 본문에만 비교되어 같은 문구가 OCR 블록·전체 텍스트에 두 번 들어갔다. 기존 코드에서 실제 1개 테스트가 기대 1회와 관측 2회의 차이로 실패했다.

앞선 그림 OCR 중 페이지·정규화 문구·좌표가 사실상 같은 것만 추가 비교한다. 기존 네이티브 중복 조건은 유지하고 떨어진 같은 문구·다른 페이지를 합치지 않는다. source part와 PNG·그림 블록도 보존한다.

기존 대조군 4개와 수정본 6개가 통과했다. 공통 5개 사례의 PNG 바이트·canonical 픽셀·위치·part·첫 OCR의 신뢰도·원래 텍스트 해시가 같았다. 의도된 차이는 겹친 위치의 OCR·전체 텍스트 2→1이었다. raw PDF에는 생성 시각 메타데이터 차이가 있어 원본 바이트가 같다고 주장하지 않는다.

제품에 적용한 뒤 실제 패키지 scheme의 Release 테스트 **63개 통과·실패/skip 0·runtime warning 0**을 확인했다. 전체 명령 wall은 143.50초다. 일회성 JSON·픽셀 지문 계측은 외부 조사 자료에 보존하고 영구 회귀에서는 제거했다. 새 테스트 파일은 SwiftPM 테스트 타깃에서 자동 발견한다.

외부 호스트의 최초 실행은 새 파일의 타깃 등록이 빠져 실제 0개였다. 성공이나 결함 증거로 인정하지 않았고 등록 후 1·4·6개 실제 발견 수를 대조했다. 원자료는 삭제하지 않았다. 이 수정으로 OCR 호출 수나 peak 메모리가 줄었다고 주장하지 않는다.

## 동일 PDF 영역의 OCR 재사용

앞 절의 v1은 결과 블록의 중복만 제거했다. v2는 한 페이지의 같은 래스터를 정확히 같은 bounds로 자른 그림 중, 앞선 OCR이 성공하고 결과가 비어 있지 않은 영역만 재사용한다. PNG·그림 배치는 각각 유지하며 다른 페이지·떨어진 영역·부분 겹침은 합치지 않는다. 페이지를 넘는 캐시나 OCR 결과 전체를 보관하는 캐시는 추가하지 않았다.

고정 입력 6사례의 진단에서 그림 OCR 호출은 합계 **11→9회**, 페이지 OCR은 7→7회였다. 입력·블록·PNG·canonical 픽셀·위치·신뢰도·원래 OCR 텍스트 지문은 보존했다. 호출 계측 진단의 시간은 성능 근거로 사용하지 않았다.

동일 그림을 같은 위치에 두 번 둔 자체 PDF를 v1→v2→v2→v1로 비교했다. 각 프로필·변형은 예열 1회 뒤 측정하며 설정별 10표본, 5ms sampler·Release `-O`·Swift 5·WMO를 사용했다.

| 동일 영역을 포함한 프로필 | v1 시간 중앙값 | v2 시간 중앙값 | 최대 footprint v1 → v2 |
| --- | ---: | ---: | ---: |
| PDF 1개를 parseBatch로 처리 | 1.5110초 | 1.0800초 (−28.53%) | 102.16 → 104.46MiB |
| 해당 PDF·JPEG·DOCX 배치 | 1.6967초 | 1.3205초 (−22.17%) | 207.64 → 206.60MiB |

대상 프로필의 결과 지문은 같았고 시간은 줄었다. 단일 PDF의 최대 footprint는 오히려 늘었으므로 **peak 메모리 감소는 확인하지 못했다**. 일반적인 서로 다른 그림이나 기존 작은 3문서 배치에도 같은 이득이 있다고 해석하지 않는다.

이후 내부 인식 함수를 주입하는 회귀로 실패 후 재시도·빈 결과 후 재시도·취소 전파·성공한 영역만 재사용하는 조건과 실제 Vision 취소를 검증했다. 실제 5개가 통과했고, 같은 소스·컴파일 결과의 기본 인식 경로 6개도 통과했다. 실패/skip·runtime warning은 0건이다. 인식 함수 주입은 테스트 경계를 위한 내부 인자이며 공개 API를 추가하지 않았다.

## 한 행의 한영 혼합 인식

이전 자체 이미지의 같은 픽셀을 고정하고 자동 언어 감지·언어 보정의 2×2와 언어 순서를 비교했다. CER은 NFC·공백 제외 후 문자 단위 편집 거리이며 대소문자·숫자는 바꾸지 않는다. 입력·원시 텍스트·좌표·신뢰도 지문과 마커·문자 종류를 보존하고 본문은 로거에 출력하지 않는다.

| 정책 | 혼합 문서 CER | 영수증 CER | 별도 행 대조군 CER |
| --- | ---: | ---: | ---: |
| 기존 자동 감지·보정 on | 17.81% | 8.51% | 0% |
| 자동 감지만 off | 0% | 0% | 0% |
| 보정만 off | 18.36% | 8.51% | 0% |
| 감지·보정 모두 off | 0% | 0% | 0% |
| 자동 감지 on·영어 우선 | 17.81% | 23.40% | 0% |

기준 실패는 공백·NFC·자모나 top 10 후보 검사로 설명되지 않았다. 해당 OS·픽셀에서 자동 감지 경로의 영향으로 좁혔으며 내부 모델 선택 방식까지 확정한 것은 아니다. 6개 테스트 실행·54개 기록이 있고 실패/skip·runtime warning은 없었다. 이는 자체 이미지의 진단이며 일반 문서 정확도 보장이나 성능의 인과 비교가 아니다.

전역 기본값 변경은 **미채택**했다. 사용자 확인 후 요청별 `ocrLanguage` 옵션을 추가했으며 기본 `.automatic`은 기존 동작을 유지한다. `.koreanAndEnglish`와 `.english`는 언어를 아는 호출자가 선택한다. 작은 PDF·JPEG·DOCX 배치를 자동 감지 on→off→off→on, 예열 1회·측정 5회로 비교했다. 설정별 10표본, 같은 5ms sampler·Release `-O`·Swift 5·WMO다.

| 작은 3문서 배치 | 기준 | 자동 감지 off |
| --- | ---: | ---: |
| 시간 중앙값 | 1.4500초 | 1.1565초 |
| footprint peak 중앙값 | 190.72MiB | 203.18MiB |
| 최대 footprint | 209.86MiB | 229.28MiB |
| 최대 RSS | 537.91MiB | 519.64MiB |

시간은 짧아졌지만 footprint 중앙값 +6.53%·최대값 +9.25%로 메모리 개선 조건을 충족하지 못했다. JPEG에서 64→59블록으로 문자·위치·신뢰도·순서 지문도 달라졌다. PDF·DOCX는 같았다. 블록 감소를 정확도 향상으로 간주하지 않으며 JPEG 부분 정답과 다른 언어 프로필을 추가 검증했다. 실제 파서의 영어 모드 검증은 아래와 구분한다. 실제 회귀 8개는 모든 실행에서 통과했다. 최초 helper의 `Array(String)` 링크 실패는 제외하고 원자료를 보존했으며, 이후 CER 배열을 `[Character]`로 명시해 원래 문자 정의를 유지했다.

[자동 감지](https://developer.apple.com/documentation/vision/recognizetextrequest/automaticallydetectslanguage)와 [언어 우선순위](https://developer.apple.com/documentation/vision/recognizetextrequest/recognitionlanguages)는 공개 요청 설정이다. 문서에서 자동 감지가 언어 배열 전체를 무시한다고 확인한 것은 아니므로 그렇게 해석하지 않는다.

## 요청별 언어 옵션의 실제 파서 검증

새 API를 포함한 초기 패키지 Release 테스트 67개가 실패·skip·runtime warning 없이 통과했다(명령 wall 103.20초). 이후 동시 배치 언어 전달과 PDF 재사용 경계 회귀를 더해 아래 최종 72개 검사에 포함했다. 공통 요청 풀의 언어는 읽기 전용이며 숫자 보완도 같은 정책을 사용한다. 이미지 추출·OCR의 기본값 false와 기존 자동 언어 감지는 바꾸지 않았다.

같은 새 API 소스·호스트·헬퍼에서 요청 옵션만 automatic→english→english→automatic으로 바꿔 각 10표본을 비교했다.

| 작은 3문서 | automatic | english |
| --- | ---: | ---: |
| 시간 중앙값 | 1.5642초 | 1.1875초 |
| footprint peak 중앙값 | 198.13MiB | 207.28MiB |
| 최대 footprint | 215.91MiB | 216.08MiB |
| 최대 RSS | 510.69MiB | 494.56MiB |

시간 −24.08%지만 footprint 중앙값 +4.62%이며 최대값은 비슷했다. **메모리 절감으로 보고하지 않는다.** 실제 파서의 JPEG 부분 정답 64개 중 39→43개가 일치했고 기존 정답 손실은 0, 추가 정답은 4개였다. PDF·DOCX는 본문·위치·신뢰도·순서·경고·이미지 메타데이터 지문이 같았다. 모든 실행에서 실제 회귀 8개가 통과했으며 총 32회·runtime warning 0건이다. 초기 helper 컴파일 오류는 측정 0개로 제외하고 보존했다.

별도 직접 Vision 진단은 원래 관찰 순서로 처리하므로 실제 파서의 기하 정렬·숫자 보완과 같은 파이프라인이 아니다. 직접 진단의 시각 정답 토큰은 기준 40→한국어 우선 수동 21/64로 떨어졌고 순서 무관 단어 존재도 35→16으로 줄었다. 단순 줄 병합으로 해석하지 않는다. 영어 우선 수동은 44/64였지만 한글 위주 대조군 CER 94.61%여서 한영 기본값으로 사용할 수 없다. 직접 진단의 40→44와 실제 파서의 39→43 수치를 섞지 않는다. 이 부분 정답은 표 전체·UI 시간축·셀별 귀속의 완전한 정확도를 보장하지 않는다.

한영 프로필을 별도 ABBA로 재확인한 결과는 다음과 같다. 각 정책·프로필별 10표본이며 같은 코드·입력·5ms·Swift 5·Release WMO다.

| 프로필 | CER·기준 → 한국어 우선 수동 | 시간 중앙값 | 최대 footprint |
| --- | ---: | ---: | ---: |
| 혼합 문서 | 17.81% → 0% | 0.8761 → 1.0191초 | 132.25 → 139.66MiB |
| 혼합 영수증 | 8.51% → 0% | 0.4603 → 0.4040초 | 106.35 → 96.38MiB |
| 별도 행 대조군 | 0% → 0% | 0.8297 → 0.8481초 | 129.92 → 120.47MiB |

영수증은 정확도·시간·최대 footprint가 함께 좋아졌지만 문서는 비용이 늘었다. 모든 입력의 개선으로 일반화하지 않는다. 대조군은 정확한 semantic 지문도 같았다.

## 지원 GPU 지정 후보

요청이 지원하는 GPU를 명시한 외부 후보는 각 5표본에서 시간 1.4972→3.3041초, 최대 footprint 207.02→199.88MiB였다. 모든 결과 지문은 같았지만 속도 조건을 충족하지 못해 미채택했다. 실제 성능·회귀 8개와 설정 확인 1개가 통과했다. 장치 지원·명시적 지정은 실제 모든 커널의 실행 장치와 다르다.

이 초도 비교 중 다른 Simulator 관측·종료가 4쌍 있었으므로 무부하 인과 비교나 모든 기기의 GPU 성능으로 일반화하지 않는다. 교차 반복이나 전체 코퍼스는 추가 실행하지 않았다. 제품 장치 정책을 바꾸지 않았다.

## Vision 문서 인식 API의 외부 진단

`RecognizeDocumentsRequest`도 별도 호스트에서 실제 실행했다. 언어 지원 선검사에서 한국어·영어를 포함한 33개 언어를 확인한 뒤, 같은 자체 이미지 3개와 기존 JPEG에 자동 감지 on/off를 적용했다. 4입력 모두 실제 픽셀 SHA가 앞선 `RecognizeTextRequest` 진단과 같았고 정책·반복 사이에도 같았다. 렌더러 소스 일치만으로 판정하지 않았다. 인식 본문은 로그에 남기지 않았다.

| 문서 인식 정책 | 혼합 문서 CER | 영수증 CER | 별도 행 대조군 CER | JPEG 부분 정답 |
| --- | ---: | ---: | ---: | ---: |
| 자동 감지 on | 16.58% | 8.51% | 0% | 40/64 |
| 자동 감지 off·한국어 우선 | 0% | 0% | 0% | 21/64 |

자체 이미지는 각 3회로 예열 1회와 이후 2회를 구분했으며 반복 간 CER는 같았다. JPEG는 정책별 1회다. 실제 XCTest는 4개 통과·실패/skip·runtime warning 0, OCR 기록 20개와 지원 조회 기록 8개다. 전체 단계 wall은 159.813초였다. 이는 정확도 진단이며 교차 반복 성능 비교가 아니므로 기존 엔진 대비 시간·메모리 개선으로 해석하지 않는다.

관측한 컨테이너에서 `text.lines`와 `text.transcript`는 NFC·공백 제외 시 같고 문단도 포함됐다. 두 자체 이미지에서는 표 컨테이너도 관측했지만, 자식 문자열이 부모의 줄에 연속 포함되지 않은 사례가 반복을 포함해 1,800건이었다. 문자 개수 검사는 통과했지만 이를 셀 순서·귀속 정답으로 간주하지 않는다. 목록·중첩 표는 관측하지 못했으며 일반 표·목록의 완전한 추출까지 검증한 것은 아니다.

새 API에서도 언어별 절충이 남았고 모든 입력의 정확도·출력·속도·메모리를 함께 보존한다는 근거는 얻지 못했다. **제품의 OCR 엔진은 유지했다.** 최초 지원 조회의 잘못된 프로젝트 경로 실행은 실제 테스트 0개·exit 66으로 별도 보존하고 성공 결과에 합산하지 않는다.

## 최종 통합 검증과 기존 문서 호환성

새 언어 API와 PDF v2를 통합한 실제 패키지 Release 테스트는 **72개 통과·실패/skip 0·runtime warning 0**이었다. 명령 wall은 111.799초다. 해당 실행의 소스·테스트 57파일 해시가 현재 파일 바이트와 일치함을 확인했다. 최종 strict lint 58파일과 별도 문서 Swift 예제 1파일의 위반은 0건이었다. 앞의 63·67개 결과는 각각 당시 v1·언어 API 단계의 기록이며 최종 테스트 수와 합산하지 않는다.

런타임 경고와 빌드 도구의 경고는 구분한다. 위 Release 로그에는 SwiftPM 테스트 제품의 clang sysroot 경고와 App Intents 메타데이터 추출 생략 경고가 각각 1건 있다. 수정한 Swift 소스의 컴파일 경고는 없었다.

기존 `26087b2`와 최종 소스를 같은 고정 호스트·헬퍼·입력에서 비교했다. 이 대조는 **OCR·그림 추출을 켜고 기본 언어 모드**를 사용했다. 제품의 `performOCR`·`extractImages` 기본값 false를 바꾼 검증은 아니다. 동시 문서 2, PDF 최대 동시 페이지 10, 픽셀 한도 40,000,000, PDF 작업 예산 256MiB를 양쪽에 동일하게 적용했다.

양쪽 각각 실제 테스트 1개가 65문서를 모두 처리했고 각 1개 통과·실패/skip 0·runtime warning 0이었다. **65/65 문서의 전체 텍스트·블록·읽기 순서·좌표·OCR 신뢰도/원문·경고·이미지 canonical 픽셀과 메타데이터 지문이 같았다.** 합계는 각각 2,709블록·38이미지·297경고였다. 이 코퍼스의 PDF 출력에는 차이가 없었으며 새 overlap 자체 회귀의 의도된 차이와 구분한다.

PNG 컨테이너 바이트까지 같은 문서는 64/65개였다. baseball PNG 1개는 컨테이너 SHA가 달랐지만 길이 287,245바이트와 디코딩한 8-bit sRGB RGBA 픽셀·크기·방향·위치·설명·OCR 결과가 같았다. 컨테이너 차이를 픽셀 변화나 PDF 수정 효과로 간주하지 않는다.

원본 입력 SHA·파일 크기와 fixture 자산 94개 해시, 동일 호스트·헬퍼·옵션을 대조했다. 기준 소스는 git `26087b2`, 최종 소스는 현재 main 바이트와 일치했고 실제 컴파일의 `-O`·Swift 5·WMO·arm64를 확인했다. 전체 단계 wall은 **196.464초**다. 각 소스를 한 번씩 처리한 호환성 검사이므로 빌드·캐시가 섞인 시간 차이로 성능 향상을 주장하지 않는다.

패키지 회귀의 재현 명령은 다음과 같다. 실제 실행에는 고정된 의존성 캐시·업데이트 금지 옵션·장치 ID를 추가했고 전체 인자는 `MainFinal/main-release72.metadata.json`에 보존했다. 결과 경로는 매번 새 경로를 사용한다.

```bash
xcodebuild test -configuration Release -scheme OmniParser -jobs 2 \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -skipMacroValidation -packageAuthorizationProvider netrc \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath /새로운/OmniParser-Release.xcresult \
  CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES \
  SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_COMPILATION_MODE=wholemodule
xcrun xcresulttool get test-results summary --path /새로운/OmniParser-Release.xcresult
swiftlint lint --strict
swiftlint lint --strict --no-cache Documentation/VisionMemoryReproduction.swift
```

최종 v2와 동일한 언어 API·내부 인식 함수 경계를 가진 v1을 비교해 일반 입력의 재사용 비용도 확인했다. v1→v2→v2→v1, 프로필·변형별 10표본, 예열 8회 제외·총 측정 40표본이다. 호스트·헬퍼·옵션·자산을 고정하고 PDF 페이지 파서만 교체했다. 각 실행의 실제 테스트 2개, 합계 8개가 실패/skip·runtime warning 없이 통과했다. 작은 배치는 PNG 반환을 끄고, 그림 16개 PDF는 PNG도 반환해 각각 동일한 조건끼리 비교했다.

| 일반 입력 | 시간 중앙값 v1 → v2 | peak footprint 중앙값 | 최대 footprint | 최대 RSS |
| --- | ---: | ---: | ---: | ---: |
| 기존 PDF·JPEG·DOCX 배치 | 1.3428 → 1.3302초 | 185.73 → 201.66MiB | 211.47 → 209.94MiB | 508.39 → 526.34MiB |
| 서로 다른 그림 16개 PDF | 6.7262 → 6.5110초 | 110.87 → 109.83MiB | 113.50 → 113.56MiB | 340.25 → 360.97MiB |

모든 반복에서 블록·원래 OCR 텍스트·신뢰도·위치·순서·경고 지문과 반환한 PNG가 같았다. 이 범위에서 시간 회귀는 관찰하지 못했지만 **작은 배치 메모리가 더 줄었다고 할 수 없다**. footprint 중앙값·RSS가 증가한 값도 함께 남긴다. 첫 실행 전후에는 다른 프로젝트의 Xcode 테스트 프로세스도 관찰했으며 각 파싱 표본과의 정확한 겹침은 확인하지 못했다. 무부하 성능의 인과 비교나 최대 그림 개수 전체의 비용 검증으로 일반화하지 않는다. 네 명령의 wall 합계는 428.720초, 첫 명령 시작부터 마지막 종료까지는 519.824초다. 빌드·설치·예열이 포함되므로 표의 파싱 시간과 구분한다.

### 작은 배치의 증가 구간 분석

같은 원시 표본을 추가 실행 없이 구간별로 대조했다. v2 두 프로세스의 footprint peak 중앙값은 각각 202.16·201.16MiB로, v1의 184.50·188.28MiB보다 높았다. 최고점 중앙값 차이 15.93MiB를 하나의 이상치로 설명할 수는 없다.

| 작은 배치 구간의 footprint 중앙값 | v1 | v2 |
| --- | ---: | ---: |
| 파싱 전 | 28.10MiB | 30.04MiB |
| 파싱 중 최고점 | 185.73MiB | 201.66MiB |
| 반환 결과 보관 중 | 28.40MiB | 30.15MiB |
| 결과 해제 뒤 | 28.40MiB | 30.14MiB |

차이의 대부분은 파싱 중 일시적 최고점에 나타났다. 약 16MiB가 반환 결과에 계속 남는 패턴은 확인되지 않았다. 그렇다고 모든 네이티브 매핑이 해제됐다는 증거는 아니다. 양변의 DI 경계는 같고 작은 PDF의 그림 영역은 1개다. 새 CGRect 목록의 값 payload는 최대 32바이트 규모여서 이것만으로 증가분을 설명하기 어렵지만, 배열의 실제 할당량·async frame 수명·네이티브 작업 겹침을 측정한 것은 아니다.

5ms sampler는 최대값만 보관했다. 시계열·최고점 시각·문서별 OCR 구간이 없어 어떤 요청이나 할당 주체가 원인인지 확정할 수 없다. 다음 진단은 이 시간 정보를 제품 밖에서 수집해 최고점 구간을 찾는 것이다. 근거 없이 작은 배열을 다른 자료구조로 바꾸거나 동시성·해상도를 낮추지는 않는다.

`RecognizeDocumentsRequest` 외부 진단은 앞 절과 구분하며 위 제품 성능 통계에 포함하지 않았다.

일반 generic Simulator 빌드도 arm64·x86_64 모두 통과했다(12.064초, 경고·오류 0). Release 테스트와 별개로 저장소 CI의 기본 빌드 구성을 사용했다.

```bash
xcodebuild build -scheme OmniParser -jobs 2 \
  -destination 'generic/platform=iOS Simulator' \
  -skipMacroValidation -packageAuthorizationProvider netrc CODE_SIGNING_ALLOWED=NO
```

## 후속 언어 전달 회귀

요청별 한영 옵션의 직접 CGImage 검사에 자체 생성 PDF·TIFF 회귀 2개를 추가했다. PDF는 같은 2페이지 문서의 그림 OCR과, PNG 예산 1바이트로 보관 실패를 유도한 전체 페이지 OCR 복구 경로를 구분한다. 그림의 part 유무·위치 경고, 페이지별 CER·읽기 순서·신뢰도·전체 텍스트 일관성을 확인한다. TIFF는 서로 다른 한영 마커를 넣은 두 프레임을 프레임 순서·페이지 위치와 함께 검사한다.

최신 패키지 Release 테스트는 **74개 통과·실패/skip·runtime warning 0건**, 명령 wall 112.483초다. 실행 당시 소스·테스트 57파일 해시와 현재 파일이 같고 strict lint 58파일도 통과했다. 제품 소스·옵션의 기본값·의존성은 바꾸지 않았다. 앞선 generic 빌드 이후의 Swift 변경은 테스트 파일뿐이다.

Office·HWP·HTML·RTF도 정적 호출 경로에서는 같은 TaskLocal 풀을 사용한다. 다만 이번의 명시 언어 형식별 런타임 회귀에 포함하지 않았고, 앞선 기본 언어 65문서 대조로 이 공백을 대신하지 않는다.

## 최고점 시계열 진단

제품 밖의 고정 호스트에서 양변에 같은 계측을 넣어 V1→V2→V2→V1을 실행했다. 4개 테스트가 모두 통과했고 예열 4회·측정 12회의 전체 결과 지문은 기존 69블록·그림/경고 0개와 같았다. 타임라인 4,988행과 메모리 샘플 4,236개를 보존했다. 네 실행의 wall 합계는 206.456초이며 진단 준비·확인 간격과 구분한다.

측정 12회의 footprint 최고 샘플은 모두 JPEG와 PDF의 Vision `request.perform` 시작·종료 마커 사이에 있었다. PDF 그림 OCR 구간 4회, 전체 페이지 OCR 구간 8회였다. 이는 두 비동기 요청의 대기 구간이 겹친다는 관측이지 내부 네이티브 커널이 같은 순간 실행됐다는 증거가 아니다. 숫자 보완·블록 변환의 구간과도 구분했다.

실제 샘플 간격 중앙값은 4.971ms, 최대는 118.282ms였다. 같은 Mutex 안에서 메모리를 조회해 이벤트 기록이 지연될 수 있으며 순간 최고점을 놓칠 수 있다. 계측은 시점·수명을 바꾸므로 진단의 footprint 중앙값 V1 194.60→V2 186.46MiB를 정상 성능 결과나 기존 증가가 해결됐다는 증거로 사용하지 않는다. 네이티브 할당 주체는 이 시계열만으로 확정하지 않았다.

### 현재 코드의 네이티브 할당 스택

이후 외부 V2의 같은 진단 호스트를 cached Release로 한 번 빌드하고, 해당 테스트 프로세스에만 MallocStackLogging을 적용했다. warmup 완료를 확인한 뒤 measured 1회차의 높은 메모리 시점(문턱 180MiB, 관측 180.096MiB)을 캡처했다. PID·UID·시작 시각·앱 container·실행 파일 해시를 검증하고 독립 재개 watchdog과 finally를 사용했다. 약 6.195초 뒤 앱을 재개했으며 캡처·테스트 모두 exit 0이었다.

JPEG OCR과 PDF 그림 OCR의 Vision 요청 마커 사이에서, CoreML 모델 준비 → Espresso `allocate_blobs` → `blob_cpu::resize` → `posix_memalign` 스택을 직접 확인했다. 가장 큰 그룹은 28회 할당·97.156MiB, 별도 그룹은 4회·37.563MiB였다. 분류별 CoreML·Espresso 집계는 서로 겹치므로 합산하거나 footprint 기여율로 계산하지 않는다. 각 그룹이 어느 문서 하나에 속하는지는 식별하지 못했다.

이것은 현재 코드의 높은 메모리 구간에서 native 작업 저장소를 확인한 근거다. 절대 최고점의 캡처나 앞선 V1/V2 +15.93MiB 차이의 인과적 원인, 누수·속도 개선의 증거는 아니다. 진단의 measured 3회 모두 기존 69블록·그림/경고 0개와 전체 의미 지문이 같았고 실제 테스트 1개 통과·runtime warning 0건이었다. raw 할당 스택 68,310,619바이트는 Git 밖에 보존했다. 본문·메모리 content를 출력하지 않았다.

## 원본 이미지 Data 입력 후보 — 미채택

외부 복제본에서 단일 프레임 JPEG·PNG·HEIC의 주 OCR 요청에 원래 압축 Data를 전달하는 후보를 만들었다. ImageIO의 크기 검증, 원본 CGImage의 PNG 추출·숫자 보완, TIFF·PDF·내장 그림 경로와 언어 정책은 유지했다. 새 인코딩·색 변환을 넣지 않았다.

작은 3문서의 같은 호스트·헬퍼·입력·옵션에서 A→B 두 실행, 각 예열 1회·측정 5회만 수행했다. 실제 테스트는 각각 1개 통과·실패/skip·runtime warning·Sendable 경고 0건이다. 다만 helper의 PASS는 같은 프로세스의 반복 일치 검사이며 **A/B 출력 동일성을 뜻하지 않는다**.

실제 Data 분기는 JPEG에서 예열 포함 6회 사용됐다. JPEG는 64블록을 유지했지만 텍스트 SHA 6개·bounds 8개·confidence 1개가 달랐고 전체 의미 지문도 바뀌었다. 두 PDF OCR 요청의 진단 필드는 같았다. DOCX 네이티브 필드의 독립적인 동일성은 기록하지 않았다.

`CVPixelBufferCreate`의 framework stderr `-6680`은 6→0회로 줄었지만 출력 보존과 메모리 개선의 증거는 아니다. 기존 부분 oracle의 case-sensitive 단어 경계 일치는 32→33/64, 추가 1개·기존 일치 손실 0이었다. 앞선 compact 부분 문자열 점수와 정의가 다르며, 변경된 문구 전체의 정확도를 검증한 것도 아니다. 기본 경로는 바꾸지 않았다.

공통 진단 JSON·정규식 작업이 측정 구간에 포함돼 시간·메모리 수치를 정상 성능으로 사용하지 않는다. 출력 보존에 실패해 추가 ABBA·74개 회귀·65문서·codec·취소 검증은 실행하지 않았다. 실패 결과·후보 패치는 Git 밖에 보존했다.

## PDF 비트맵 저장소 대안 — 적용 보류

현재 캡처의 `DocumentPDFPageSpace.render` → `CGBitmapContextCreateImage` → `CGDataProviderCreateWithCopyOfData` → `create_protected_copy` → `mmap` 경로에는 3회·약 7.406MiB의 저장소 그룹이 있었다. 이는 렌더 결과의 저장소 생성 스택이며 물리 복사·동시에 살아 있는 두 벌의 dirty 픽셀·중복 footprint의 증거는 아니다.

[Apple 문서](https://developer.apple.com/documentation/coregraphics/cgcontext/makeimage%28%29?language=objc)와 설치 SDK 헤더는 일부 snapshot이 COW로 동작해 context 수정 때 실제 복사가 생길 수 있다고 설명한다. 현재 코드는 snapshot 이후 context를 다시 수정하지 않고 OCR에 context를 넘기지도 않는다. 직접 소유한 Data/CFData 버퍼로 바꿔도 절감이 0이거나 브리지 복사가 추가될 수 있다.

따라서 제품 치환은 보류했다. 살아 있는 CGContext를 이미지 provider의 owner로 보관하는 방식도 PDFKit·가변 상태의 수명을 OCR 작업에 넘길 수 있어 제외한다. 기존 자동 stride·이미지 보간·rendering intent의 실제 값과 독립 이미지 수명을 먼저 조회하는 단계이며, 확인 전에는 추정값으로 치환하거나 7.4MiB 절감을 주장하지 않는다.

후속으로 기존 renderer를 바꾸지 않은 메타데이터 전용 테스트 1개를 실행했다. 기본 픽셀 한도 40,000,000을 유지하고 기존 PDF 3개의 첫 페이지·자체 odd width·MediaBox 원점/90도 회전·P3/alpha 입력의 6사례를 조회했다. 실제 1개 통과·실패/skip·runtime warning 0, OCR 호출 0이었다. 명령 wall은 91.314초, 테스트 본문은 0.139초로 구분한다.

이 6사례에서 8-bit component·32-bit pixel·bitmapInfo/alpha 1·`shouldInterpolate: true`·rendering intent 0·decode 없음이었다. stride는 1190→4768, 1584→6336, 1224→4896, 203→832, 167→672바이트였다. 관측한 값은 32바이트 정렬과 맞지만 모든 크기·OS의 자동 stride 계약으로 일반화하지 않는다. P3 입력에서는 Display P3도 유지됐다. PDFDocument와 PDFPage의 weak 참조가 모두 해제된 뒤 이미지·crop을 읽을 수 있었고 전후 픽셀 해시가 같았다.

이 조회는 기존 렌더 결과의 메타데이터·수명 근거이며 새 버퍼의 동등성·COW의 물리 페이지·메모리 절감을 검증한 것은 아니다. 소유 버퍼 치환이나 제품 코드 변경은 하지 않았다.

### 소유 버퍼 후보의 기능·성능·해제 검증

이후 제품 밖에서 실패 가능한 `calloc` → `Data(bytesNoCopy:, deallocator: .free)` → CFData/provider로 독립 비트맵을 만드는 후보를 시험했다. 가변 포인터와 CGContext의 범위를 끝낸 뒤 불변 provider만 이미지에 남겼다. 렌더링 해상도·OCR 옵션·작업 동시성은 바꾸지 않았다.

A/B 기능 비교는 각 2개씩 총 4개 테스트가 통과했다. 6사례의 전체·crop 픽셀, 색공간·메타데이터, PNG 바이트와 디코딩 결과가 같았다. PDFKit 객체 해제 뒤 이미지도 읽을 수 있었다. 작은 3문서 배치의 예열·반복 결과 역시 텍스트·읽기 순서·위치·신뢰도·경고를 포함한 전체 지문이 같았다.

계측을 넣지 않은 실제 후보의 A→B→B→A는 4개 테스트가 통과했다. 각 프로세스 예열 1회 후 5회씩 총 20표본이며 모두 기존 69블록·그림/경고 0개였다. 5ms sampler와 입력·호스트·기존 헬퍼·Release 설정은 같았다.

| 작은 3문서 | 기존 A 중앙값 / 최대 | 소유 버퍼 B 중앙값 / 최대 |
| --- | ---: | ---: |
| 파싱 시간 | 1.217 / 1.663초 | 1.206 / 1.355초 |
| peak footprint | 191.104 / 203.096MiB | 186.471 / 202.002MiB |
| peak RSS | 529.141 / 535.625MiB | 532.570 / 538.016MiB |

시간 중앙값은 -0.93%, footprint는 -2.42%였지만 RSS 중앙값은 +0.65%였다. A1/A2 footprint 중앙값 자체가 182.346→197.284MiB로 변해 약 4.63MiB의 후보 차이보다 프로세스 간 편차가 컸다. 공유 Mac의 다른 QA 작업·swap도 기록했다. 출력은 같았고 이번 20표본의 시간 중앙값·최대값에서는 증가를 관찰하지 못했다. **메모리 절감 효과는 확정하지 않았고 제품에 적용하지 않았다.**

해제 확인은 성능 후보와 분리했다. 원본 주소·바이트 수만 기록하는 `.custom` deallocator 진단으로 마지막 crop 해제, 할당 nil·소유권 설치 뒤 nil 주입, allocation 시점 취소를 검사해 3개 테스트가 통과했다. 이 진단 변형의 원본 버퍼는 마지막 crop까지 유지됐고 이후 정확히 한 번 해제됐다. 두 nil 경로는 native 본문·위치와 기존 경고를 보존하고 페이지 경고를 추가했다. 취소는 내부 PDF의 cooperative 경계에서 `CancellationError`로 전달됐고 버퍼도 한 번 해제됐다.

이 결과로 무계측 `.free` 후보의 할당·브리지 동작까지 입증하지 않는다. 실제 OOM, bridge 내부 할당 실패, Vision 실행 중 취소나 모든 입력·OS의 보장도 아니다. 주소가 같다는 관측도 provider 내부 복사 부재·zero-copy·물리 footprint 절감의 증명으로 쓰지 않는다. 실행 인자 `-test-iterations 1`을 Xcode가 거부해 컴파일·테스트 0개로 끝난 첫 시도도 보존했다. 해당 옵션만 제외한 새 실행은 실제 Swift 5·`-O`·WMO로 3개 통과·실패/skip/runtime warning 0건, 빌드 포함 wall 90.807초였다.

추가로 양 renderer를 넣은 별도 바이너리에서 A/B 순서를 미리 고정한 10쌍·20표본을 같은 프로세스로 비교했다. 실제 1개 테스트 통과·실패/skip/runtime warning 0, 빌드 포함 wall 116.666초였고 양쪽 예열 분기의 도달과 전체 출력 지문 일치를 확인했다. footprint 중앙값은 A 198.651→B 201.987MiB, RSS는 527.883→529.609MiB였으며 B의 footprint가 10쌍 중 6쌍에서 컸다. 쌍별 B−A 차이의 중앙값은 footprint +2.211MiB·RSS +1.852MiB·시간 -0.010초였다. 시간의 변형별 중앙값은 1.135→1.138초로, 일관된 메모리·속도 개선은 관찰하지 못했다.

이 교차 진단은 프로세스별 편차를 일부 줄이지만 두 renderer를 넣은 코드 배치·TaskLocal 조회·공유 Vision 캐시·직전 실행의 영향을 포함한다. 별도 프로세스 ABBA를 대체하거나 단독 채택 근거로 쓰지 않는다. 두 비교 모두 요구한 메모리 절감을 입증하지 못했으므로 후보를 미채택으로 정리했다.

`CGDataProvider(dataInfo:data:size:releaseData:)`로 Data/CFData를 없애는 대안도 정적으로 검토했다. 정상 수명의 해제 callback은 제공하지만 nil 생성 실패 때 callback의 책임까지 SDK 헤더만으로 확정하지 못했다. 해제 상태 관리가 추가되고 메모리 이득도 미검증이라 별도 런타임이나 제품 변경으로 이어가지 않았다.

## CPU 명시 선택 후보 — 미채택

별도 외부 복제본의 `DocumentOCR.makeRequest` 한 파일에만 6줄을 넣어, 지원 목록에 CPU가 있으면 main compute stage에 지정했다. 언어·자동 감지·revision·정확도·숫자 보완·이미지 입력·동시성·해상도는 유지했다. 제품의 자동 장치 선택은 바꾸지 않았다.

A→B 두 실행에서 실제 4개 테스트가 통과했고 실패/skip/runtime warning은 0건이었다. 각 예열 1회 후 5회씩 총 10표본의 전체 의미 지문은 기존 69블록·그림/경고 0개와 같았다. 실제 OCR 비교는 기본 `.automatic` 모드다. 측정 밖의 별도 설정 조회에서 세 언어 모드 모두 B의 main 설정이 CPU임을 확인했지만, 실제 모든 커널의 실행 장치를 추적한 것은 아니다. 자동 미지정인 A를 CPU라고 해석하지 않는다.

파싱 시간 중앙값은 1.146→1.225초(+6.88%), peak footprint는 197.737→206.956MiB(+4.66%), peak RSS는 528.406→529.328MiB(+0.17%)였다. CLI 전체 wall은 A 96.369초·B 20.721초로 빌드 차이가 포함돼 파싱 속도로 비교하지 않는다. 실제 Swift 5·`-O`·WMO, 소스 지문과 공유 Mac 환경을 보존했다. 외부 호스트의 manifest 빌드에 나온 기존 clang sysroot 경고 A 5건·B 1건은 런타임 경고 0건과 구분해 원문에 남겼다.

초기 A/B의 순서·캐시·환경 영향이 있어 CPU 선택의 보편적인 인과 효과로 단정하지 않는다. 이번 관측은 메모리·속도 이득을 뒷받침하지 않아 미채택으로 정리했고 추가 BA/ABBA·74개 회귀·65문서 검증은 실행하지 않았다. 실기기에서 자동 장치 선택 대신 CPU를 강제했을 때의 속도·전력·출력도 미검증이며, 이 Simulator 결과로 제품의 장치 정책을 바꾸지 않는다.

## 원자료와 남은 확인

로컬 근거 루트는 `~/Developer/Codex/OmniParserVerification/2026-10-28/ImprovementLoop-20261028/`다.

- `PDFOverlapInvestigation/RESULTS.json`: 기존 실제 실패, 대조군·수정본과 PNG/픽셀/메타데이터 대조.
- `MainPDFOverlap/`: 실제 제품 Release 63개 xcresult·명령·runtime warning·소스 SHA.
- `PDFOverlapV2/TRACE_RESULTS.json`, `PDFOverlapV2/BENCH_RESULTS.json`: 같은 영역의 호출 수와 대상 프로필 40표본 ABBA. 일반 작은 배치·서로 다른 그림은 포함하지 않았다.
- `V2FaultVerified/RESULTS.json`: 실패·빈 결과·취소·성공 재사용 5개와 기본 인식 경로 6개, 실제 발견 수·warning·소스/컴파일 근거.
- `MainFinal/`: 최종 Release 72개 결과·111.799초 wall·소스/테스트 57파일 SHA.
- `MainCrossFormatLanguage/`: PDF 그림·페이지 복구와 TIFF 두 프레임을 포함한 최신 Release 74개·112.483초·소스 지문.
- `MainFinal/generic-build.metadata.json`: 일반 Simulator 빌드 전체 인자·12.064초 wall. arm64·x86_64 통과·경고 0.
- `FinalDefaultCorpus65/CorpusComparison.json`: OCR·그림 추출을 켠 기본 언어 모드의 65문서 semantic·PNG·메타데이터 대조와 원본 지문·실제 테스트 수·196.464초 wall.
- `FinalV2ABBA/RESULTS.json`: 최종 소스의 일반 작은 배치·서로 다른 그림 16개 ABBA 40표본, 전체 출력·PNG 대조와 환경 간섭 기록.
- `FinalV2ABBA/MEM_PATTERN.json`: 작은 배치의 파싱 전·최고점·결과 보관·해제 후 수치와 시계열 부재의 한계.
- `PeakTimeline/ANALYSIS.json`, `Results/*-timeline.jsonl`: 12개 측정의 최고점과 요청 대기 구간, 실제 샘플 간격·계측 영향. `PROOF.json`·소스/자산 해시도 보존했다.
- `FinalV2ABBA/PeakAllocationPrep/CaptureV2Owner/FINAL_RUNTIME_REPORT.json`: 현재 V2의 measured 높은 메모리 시점·OCR 마커 상관·직접 할당 스택·실제 출력 지문. 외부 cached build는 15.045초, 앱 동결 구간의 경과 시간은 성능 비교에서 제외했다.
- `KoreanLineInvestigation/accuracy-matrix.json`: 한영 2×2·언어 순서·고정 픽셀과 정답 CER.
- `AutoLanguageComparison/SmallResults.json`: 작은 배치 20표본·컴파일·환경·문서별 변화.
- `EnglishModeComparison/EnglishModeResults.json`: 실제 요청별 모드 ABBA·JPEG 부분 정답·컴파일·환경·32회 회귀.
- `BusinessPlanPolicy4/`, `ManualEnglishPriority/`: 직접 Vision의 영어 표·수동 영어 우선 진단. 정답 텍스트는 로컬 oracle에만 보존했다.
- `GPUSelectionComparison/GPUResults.json`: GPU 초도 10표본·9개 실제 테스트·환경·source proof.
- `RecognizeDocumentsPrototype/Results-Accuracy-v2-01/`: 문서 인식 API의 4개 실제 테스트·28개 기록·원시 지문·단계 시간. 선검사와 실패 실행도 별도 보존했다.
- `RecognizeDocumentsPrototype/actual-pixel-comparison-v2.json`, `ACCURACY_V2_SUMMARY.json`: 4입력의 실제 픽셀 대조, CER·부분 정답과 중첩 컨테이너 포함 검사 한계.
- `EncodedInputCandidate/ParityAB-01/RESULTS.json`: 실제 Data 분기·JPEG의 필드별 변화·원 실행 중 부분 정답·미채택 판단과 미실행 항목.
- `OwnedPDFBitmapCandidate/REVIEW.md`, `METADATA_GATES.json`: COW·소유권·실패 경계의 정적 검토와 제품 치환 보류. 이후 실제 조회 결과는 `MetadataOnly/`로 분리했다.
- `OwnedPDFBitmapCandidate/MetadataOnly/`: renderer 원본 지문, 기본 한도의 6사례 메타데이터·PDFKit 수명 종료 전후 픽셀 해시, 실제 1개 테스트·명령·91.314초 wall.
- `OwnedPDFBitmapCandidate/ParityAB-01/`: 소유 버퍼 후보의 실제 4개 테스트, 6사례 픽셀·PNG·메타데이터와 배치 전체 필드 대조.
- `OwnedPDFBitmapCandidate/PerfABBA-01/`: 무계측 후보의 정상 ABBA 20표본, 프로세스별 편차·속도·footprint·RSS와 미확정 판정.
- `OwnedPDFBitmapCandidate/OwnershipDiagnostics/Execution-01/`, `Execution-02/`: 첫 실행의 인자 오류·0테스트 실패와 새 실행의 실제 3개 소유권·실패·취소 테스트, source proof·해제 event. 본문·픽셀 로그는 남기지 않았다.
- `OwnedPDFBitmapCandidate/WithinProcessPrep/Execution-02/`: 동일 프로세스 교차 10쌍·20표본, 양 분기 예열 도달·전체 출력 지문, 모든 쌍의 차이·순서 효과. `Execution-01/`의 문서 변경 감지로 시작 전 중단된 기록도 보존했다.
- `CPUSelectionCandidate/RESULTS.json`: 초기 A/B 10표본·실제 4개 테스트, 언어별 장치 설정과 전체 의미 지문·컴파일 근거, 빌드 wall과 파싱 시간·환경·미채택 판단.

공유 Mac의 swap·OS cache·계측 오버헤드를 배제하지 못하며 5ms도 순간 최고점을 보장하지 않는다. 실기기는 검증하지 않았다. 작은 일반 배치의 추가 메모리 절감은 목표 미달이며, 원시 표본의 증가 구간·잔류량과 후속 후보를 계속 분석한다.
