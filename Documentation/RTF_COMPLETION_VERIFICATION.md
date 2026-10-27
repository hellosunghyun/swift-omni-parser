# RTF·부분 복구 후속 검증

2026-10-27. 맥북에서 이관한 미커밋 변경을 맥미니에서 검증했다. 외부 다운로드·업로드·푸시·PR 생성 없이 이관된 의존성 캐시를 사용했다. iOS 27.0과 Swift 언어 모드 5.0을 유지한다.

## 변경과 확인 범위

- RTF: Foundation importer로 문단·표·빈 셀·병합 범위를 읽는다. 별도 그림 리더는 hex/bin 그림, 이스케이프된 괄호, Word 기본/호환 그림 중복, 입력 경계와 제한을 처리한다. 그림을 생략할 때도 `{}`를 남겨 `\pard`와 다음 본문이 합쳐지지 않게 했다.
- RTF 회귀 9개: 자체 PNG/한글/표/병합/순서 샘플, 기존 일본어 표·Word JPEG 2개, 이미지/OCR 4조합, 손상 그림 후 결과 보존, 픽셀·보관 크기·개수·잘못된 binary 길이, 마지막 control-word 경계 검사.
- Office 그림: 공통 래스터 경로를 사용해 OCR 실패 후에도 PNG를 보존한다. 실패를 주입하는 회귀 검사로 확인했다.
- JSON/XML/RTF: 원문 텍스트 복구 시 위치가 있는 경고를 반환한다. XML 외부 엔티티 해석을 막고 내부 선언도 확장 전에 중단한다.
- 기존 65문서 corpus, XLS 셀 원본 정답, TIFF·일반/스캔/혼합 PDF, 배치 순서·오류·취소·임시 파일 회귀도 함께 실행했다. 테스트 정답·기존 자산은 바꾸지 않았다.

## 실제 결과

| 환경/검사 | 결과 |
| --- | --- |
| 맥미니 / Xcode 27.1 / iPhone 17 Simulator iOS 27.0 | 전체 **28/28 PASS**, skip 0, 테스트 본문 합계 28.510초 |
| 마지막 RTF control-word 경계 검사 | PASS, 이미지 추출 false/true 모두 본문 `After` 유지 |
| RTF 회귀 9개 | PASS, 2.781초 |
| 맥북 / iPhone 17 실기기 iOS 27.0.1 / 경계 수정 전 | 기존 후속 **27/27 PASS**, 5.819초 |
| 맥미니 generic iOS Simulator 빌드 | **PASS**, arm64·x86_64 |
| 마지막 경계 수정 후 실기기 | 미실행. 이관된 completed-physical.log는 의존성 해석 단계에서 끝나 실행 성공 증거가 아님 |
| 맥미니 SwiftLint strict | 미실행. 실행 파일이 없어 외부 설치 없이 진행할 수 없음 |
| 맥북 최종 이관 lint 기록 | 53파일, 위반 0건. 맥미니 재실행 결과와 구분 |

시간은 기능 테스트의 본문 합계이며 앱의 문서당 성능이나 개선율이 아니다. Simulator 실행 중 기존 Vision/CoreML의 파일·CVPixelBuffer 경고와 OCR 세션 풀의 QoS 경고가 남았다. 통과 결과로 이 경고의 해결까지 주장하지 않는다.

## 오프라인 재현

저장소 루트에서 실행한다. `verification`은 생성물 경로이며 제품 소스에는 포함하지 않는다. 첫 이관 실행은 SwiftPM workspace-state.json에 맥북의 절대 artifact 경로가 남아 실패했다. 해당 파일을 별도 사본으로 보존한 뒤 경로만 현재 위치로 고쳤고 재실행했다. 의존성 코드·바이너리는 수정하지 않았다.

```bash
verification="$HOME/Developer/Codex/OmniParserVerification/2026-10-27"
xcodebuild test -scheme OmniParser \
  -destination 'platform=iOS Simulator,id=EE442049-BD19-4EDA-AA52-6860D61826E3' \
  -jobs 4 -derivedDataPath "$verification/MacMiniDerivedData" \
  -clonedSourcePackagesDirPath "$verification/SimulatorSourcePackages" \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -onlyUsePackageVersionsFromResolvedFile -skipMacroValidation \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build -scheme OmniParser \
  -destination 'generic/platform=iOS Simulator' -jobs 4 \
  -derivedDataPath "$verification/MacMiniBuildDerivedData" \
  -clonedSourcePackagesDirPath "$verification/SimulatorSourcePackages" \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -onlyUsePackageVersionsFromResolvedFile -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO
```

로컬 증거는 위 검증 폴더의 `macmini-tests-retry.log`·동명 xcresult, `macmini-build.log`, `completed-lint.log`, `final-physical.log`·동명 xcresult에 있다. 실제 실행에는 결과 번들 경로도 지정했다. 다른 Mac에서는 해당 Mac의 Simulator ID를 사용한다.

## 남은 제약

RTF의 독립 WMF/EMF/DIB 등 ImageIO가 읽지 못하는 내장 그림은 위치가 있는 경고로 반환한다. 모든 RTF 요소·벡터 그림·페이지 좌표의 완전 복원은 아니다. 셀 안의 본문과 OCR 교차 순서는 경고와 셀 위치로 표시한다. 최신 28개 테스트의 실기기 재실행과 맥미니 lint는 남아 있다. 대용량 최대 메모리·모든 native 압축 입력의 안전성·배포 라이선스 전체 감사·자동 CI는 이번 결과로 입증하지 않는다. 새 의존성이나 바이너리는 추가하지 않았다.
