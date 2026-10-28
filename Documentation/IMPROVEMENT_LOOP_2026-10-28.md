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

## 원자료와 남은 확인

로컬 근거 루트는 `~/Developer/Codex/OmniParserVerification/2026-10-28/ImprovementLoop-20261028/`다.

- `PDFOverlapInvestigation/RESULTS.json`: 기존 실제 실패, 대조군·수정본과 PNG/픽셀/메타데이터 대조.
- `MainPDFOverlap/`: 실제 제품 Release 63개 xcresult·명령·runtime warning·소스 SHA.
- `PDFOverlapV2/TRACE_RESULTS.json`, `PDFOverlapV2/BENCH_RESULTS.json`: 같은 영역의 호출 수와 대상 프로필 40표본 ABBA. 일반 작은 배치·서로 다른 그림은 포함하지 않았다.
- `V2FaultVerified/RESULTS.json`: 실패·빈 결과·취소·성공 재사용 5개와 기본 인식 경로 6개, 실제 발견 수·warning·소스/컴파일 근거.
- `MainFinal/`: 최종 Release 72개 결과·111.799초 wall·소스/테스트 57파일 SHA.
- `MainFinal/generic-build.metadata.json`: 일반 Simulator 빌드 전체 인자·12.064초 wall. arm64·x86_64 통과·경고 0.
- `FinalDefaultCorpus65/CorpusComparison.json`: OCR·그림 추출을 켠 기본 언어 모드의 65문서 semantic·PNG·메타데이터 대조와 원본 지문·실제 테스트 수·196.464초 wall.
- `FinalV2ABBA/RESULTS.json`: 최종 소스의 일반 작은 배치·서로 다른 그림 16개 ABBA 40표본, 전체 출력·PNG 대조와 환경 간섭 기록.
- `FinalV2ABBA/MEM_PATTERN.json`: 작은 배치의 파싱 전·최고점·결과 보관·해제 후 수치와 시계열 부재의 한계.
- `KoreanLineInvestigation/accuracy-matrix.json`: 한영 2×2·언어 순서·고정 픽셀과 정답 CER.
- `AutoLanguageComparison/SmallResults.json`: 작은 배치 20표본·컴파일·환경·문서별 변화.
- `EnglishModeComparison/EnglishModeResults.json`: 실제 요청별 모드 ABBA·JPEG 부분 정답·컴파일·환경·32회 회귀.
- `BusinessPlanPolicy4/`, `ManualEnglishPriority/`: 직접 Vision의 영어 표·수동 영어 우선 진단. 정답 텍스트는 로컬 oracle에만 보존했다.
- `GPUSelectionComparison/GPUResults.json`: GPU 초도 10표본·9개 실제 테스트·환경·source proof.
- `RecognizeDocumentsPrototype/Results-Accuracy-v2-01/`: 문서 인식 API의 4개 실제 테스트·28개 기록·원시 지문·단계 시간. 선검사와 실패 실행도 별도 보존했다.
- `RecognizeDocumentsPrototype/actual-pixel-comparison-v2.json`, `ACCURACY_V2_SUMMARY.json`: 4입력의 실제 픽셀 대조, CER·부분 정답과 중첩 컨테이너 포함 검사 한계.

공유 Mac의 swap·OS cache·계측 오버헤드를 배제하지 못하며 5ms도 순간 최고점을 보장하지 않는다. 실기기는 검증하지 않았다. 작은 일반 배치의 추가 메모리 절감은 목표 미달이며, 원시 표본의 증가 구간·잔류량과 후속 후보를 계속 분석한다.
