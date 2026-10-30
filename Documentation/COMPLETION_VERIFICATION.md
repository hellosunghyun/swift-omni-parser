# RTF·부분 복구 보완 및 최종 검증

2026-10-30. 현재 구현·검증 상태를 기록한다. 이전 문서의 15/16·16/16은 XLS 의존성 전환 전후의 과거 결과다.

## 구현

- RTF 본문·목록 텍스트·표는 시스템 RTF importer를 사용한다. 표 식별자, 셀 행·열, 제공되는 가로·세로 병합 범위와 다중 문단 셀을 보존한다.
- 시스템 importer가 버리는 hex·binary `pict`를 분리해 ImageIO·Vision 경로에 연결했다. 원래 문단·셀 위치, 원본 바이트 위치와 읽기 순서를 반환한다. 셀 내부의 세부 인라인 순서 차이는 위치 경고로 알린다.
- 이미지·OCR 옵션은 독립적이며 둘 다 기본값이 false다. 정상 원본과 호환본은 중복 처리하지 않고, 손상된 원본은 정상 호환본으로 복구한다.
- Office 이미지도 공통 래스터 경로를 사용해 OCR 실패 뒤에 정상 PNG를 보존한다.
- JSON·XML·RTF 구조 복구 시 위치 경고를 반환한다. XML 외부 엔티티는 해석하지 않고 내부 엔티티 선언은 확장 전에 중단한다.
- RTF 손상 경고 개수, 그룹 깊이·그림 개수·제어어 길이·binary 길이·픽셀·보관 바이트를 제한한다. 제어어가 4096 경계를 건너뛰어도 진행량 기준으로 취소를 점검한다.

새 런타임 의존성·바이너리·화면·영구 저장 기능은 추가하지 않았다. iOS 27.0, tools 6.2, Swift 언어 모드 5.0을 유지한다. 상세 지원 범위는 [RTF 문서](RTF_SUPPORT.md), 호출 방법은 [API](API.md)를 따른다.

## 실제 결과

| 항목 | 결과 |
|---|---|
| 최종 Simulator 전체 XCTest | **34/34 PASS**, iPhone 17 / iOS 27.0 |
| generic iOS Simulator 빌드 | **PASS**, arm64·x86_64 |
| SwiftLint strict | **PASS**, 53파일·위반 0건 |
| 실기기 1차/2차 실행 | 2026-10-27 **26/26·27/27 PASS**, iPhone 17 / iOS 27.0.1. 최종 추가 검사 이전 결과 |
| 최종 실기기 전체 XCTest | **34/34 PASS**, iPhone 17 / iOS 27.2. skip·expected failure 0 |
| 독립 코드 검토 | 경고 개수 증폭·취소 검사 누락·정상 fallback 손실 수정 확인, 추가 확정 blocker 없음 |

34개는 API 5개, 기존 형식별 2개, 이미지/PDF 2개, XLS 원본 정답 1개, RTF 12개, 자원·취소·복구 12개다. 기존 출처·해시가 있는 65문서 검사를 포함하며, 새 RTF 입력은 테스트 중 생성한다. 외부 테스트 샘플을 추가 다운로드하지 않았다.

새 검사는 손상 원본의 호환 그림 복구, 셀 안 그림의 좌표·순서 경고, PNG 예산 초과 시 OCR 유지, 세로 병합·별도 표·다중 문단, 10만 개 잘못된 괄호의 경고 상한, 긴 제어어 입력 취소를 포함한다. 취소 테스트는 실행 스케줄링에 따라 초기 취소가 될 수도 있어 정확한 취소 지연 시간의 성능 측정으로 사용하지 않는다.

기능 검사 본문 실행 합계는 Simulator 26.774초, 실기기 5.235초다. 설치·연결 대기와 빌드 시간은 포함하지 않은 XCTest 값이며 단일 문서 지연이나 성능 개선율로 사용하지 않는다. OCR 세션 풀 관련 QoS 경고는 남아 있어 성능 문제까지 해결했다고 표시하지 않는다.

## 실행과 증거

```bash
xcodebuild test -scheme OmniParser \
  -destination 'platform=iOS Simulator,name=OmniParser-Finish-iPhone17' \
  -skipMacroValidation -parallel-testing-enabled NO -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build -scheme OmniParser \
  -destination 'generic/platform=iOS Simulator' -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO

swiftlint lint --strict
```

로컬 결과 루트는 `~/Documents/Codex/OmniParserVerification/2026-10-27`이다. 폴더 날짜와 개별 실행 날짜를 구분한다. 10월 30일 검증도 같은 루트에 보관했다. 제품 저장소에 원시 로그·xcresult·임시 앱을 포함하지 않는다.

- `reviewed-simulator-20261030.log`와 xcresult: 최종 전체 Simulator 실행.
- `reviewed-generic-simulator-20261030.log`: 최종 generic 빌드.
- `final-lint-20261030.log`: 최종 strict lint.
- `final-physical.log`와 xcresult: 10월 27일의 27/27 실기기 실행.
- `reviewed-physical-retry-20261030.log`와 xcresult: 최종 실기기 전체 실행.
- `ReviewEvidence/rtf-completion-code-review-final.md`: 독립 검토 결과.

실기기는 로컬 `DeviceHost`의 호스트 앱에 같은 XCTest 소스를 연결한다. 최종 호스트와 저장소의 테스트 Swift 파일 바이트가 같은지 확인했다. 번들 접근 어댑터 외에 테스트 Swift 소스를 바꾸지 않았고 개발 팀은 명령에만 전달했다. 초기 Simulator 러너 연결 실패와 실기기 연결 지연은 기능 assertion 실패와 구분한다. 과거 캐시 경로의 원시 기록은 현재 없을 수 있으며, 이번 결과는 위 Documents 경로를 사용한다.

## 의존성과 남은 범위

XLS 수정 [upstream PR #1291](https://github.com/opendocument-app/OpenDocument.core/pull/1291)은 2026-10-28 병합됐다. 10월 30일 확인한 최신 공식 릴리스는 수정 전 `v7.6.1`이므로 현재는 검증한 포크 커밋 `b302cc85311490676986a2b731971473ad21efac`을 유지한다. 수정이 포함된 공식 binary Release가 나온 뒤 같은 검사로 이전해야 한다. 소스 main만 바꾸는 것으로 배포 바이너리가 교체됐다고 간주하지 않는다.

단독 WMF·EMF `pict` 래스터화, OLE 객체, 중첩 표 전체 계층·헤더/푸터의 완전한 복원은 제공한다고 표시하지 않는다. 읽지 못한 그림은 위치 경고와 부분 결과를 반환한다. 전체 문서의 레이아웃 재현·이미지 속 표 셀 복원도 제공하지 않는다.

자동 CI·안정 버전 릴리스·OfficeOxide 전체 재현 빌드 및 앱 배포 방식까지 포함한 라이선스 검토는 이번 기능 검증으로 완료된 것이 아니다. 자체 MIT와 외부 MPL·LGPL 등의 조건을 유지하며 [라이선스 검토](LICENSE_REVIEW.md)와 [고지](../THIRD_PARTY_NOTICES.md)의 한계를 보존한다.
