# 레포 분리 전후 및 Ream 교체의 기능 비교

> 개인 절대 경로는 [로컬 검증 경로 별칭](RESEARCH_PATHS.md)으로 표기했다. 원시 로그·진단 덤프는 저장소에 포함하지 않는다.

> 후속 [11문서 원본 대조](OFFICE_DIFFERENCE_AUDIT.md)에서 기존 엔진과 Ream 양쪽의 XLS chart cache 혼입 결함을 확인했다. 이 문서의 동등성 PASS는 원본 정확성 PASS를 뜻하지 않는다. [API 호환성 검토](REAM_API_COMPATIBILITY.md)와 [테스트 구성안](REGRESSION_TEST_PLAN.md)을 함께 참고한다.

2026-10-26. 레포 분리와 Office 엔진 교체는 서로 다른 변경이다. **분리 전 앱 코드와 현재 패키지는 비교한 범위에서 같았고, Ream 교체안은 결과가 달랐다.**

## 비교 기준

| 구성 | 정확한 기준 | 실행 구성 |
|---|---|---|
| 분리 전 | 앱 저장소 `2026-C6-M09-Parser-Review-Rebuild`, 커밋 `8c565d89a4d6f1fede6893a645f0f0ccdf8fe007`의 `Researchers/Services/DocumentParsing/` | 커밋에서 소스 추출, 모듈 Researchers, 기본 actor isolation MainActor 유지 |
| 분리 후 | `swift-omni-parser` 커밋 `ddc987b24e5489e633188db03c7028bb8c3a9bfe` | 현재 로컬 패키지를 SwiftPM 경로 의존성으로 직접 import OmniParser |
| Ream 교체 | `Research/ReamReplacement/`의 검증용 구현 | 해당 패키지를 경로 의존성으로 직접 import OmniParser |

8c565d8은 분리 시 복사된 파서 소스와 완전히 일치하는 앱 저장소의 재구성 커밋이다. 오래된 스택 HEAD 35b9f43에는 이후 코드 축소 전 파일이 포함돼 있어 그 커밋을 분리 직전 기준으로 오인하지 않았다. 그 작업 트리의 현재 파서 파일도 분리본과 같지만, 미커밋 변경은 건드리지 않고 깨끗한 8c565d8의 Git blob을 검증에 사용했다.

Xcode 27.1, iOS 27.0 iPhone 17 Simulator, Swift 언어 모드 5.0, tools 6.2. 파서만 격리해 동일 테스트를 세 구성에 실행했다. 원래 앱 UI·TCA·Watch·번들 고지·서명·배포 설정의 통합 동등성을 검사한 것은 아니다.

## 1. 레포 분리로 달라진 점

- 파서 **Swift 파일 42개가 바이트 단위로 일치**했다. 최초 분리 커밋 db908f7 이후 현재까지도 파서 Sources는 바뀌지 않았다.
- 직접 패키지 의존성 SwiftSoup 2.14.3, OpenDocument.core 7.5.2, hwp-swift 0.19.0, OLEKit 0.3.1의 버전과 리비전이 전부 일치했다.
- OfficeOxide XCFramework의 기기·시뮬레이터 아카이브, 헤더, 모듈맵, Info.plist **7파일 SHA-256이 모두 일치**했다.
- 호출 측은 앱 내부 타입 대신 `import OmniParser`와 SwiftPM 제품 의존성을 사용한다. 제품·모듈 경계, 빌드/배포 방식이 변경된 것이다.
- 앱의 기본 MainActor와 SwiftPM의 기본 isolation 설정 차이는 있다. 파서 타입/메서드는 nonisolated로 작성돼 있고, 두 설정에서 실제 실행 결과를 비교했다.
- 분리된 운영 패키지에는 원래 앱의 XCTest 타깃·샘플이 포함되지 않았다. 이번 검증은 별도 로컬 하네스에 있다. 패키지에서 자동 회귀가 제공된다는 뜻은 아니다.

결론: **분리로 인해 파서 구현·엔진·지원 형식이 바뀐 근거는 없고, 이번 실행에서도 기능 차이가 발견되지 않았다.** 기존 구현의 제약까지 함께 옮겨졌다. 예를 들어 RTF의 표/내장 그림은 원래 구현하지 않았으며 분리 후에도 추가되지 않았다.

## 2. 동일 입력 실행 결과

같은 테스트 파일을 세 구성에 복사하고 import만 컴파일 조건으로 선택했다. 기존 문서 SHA-256을 매 실행 확인했으며 외부 샘플을 새로 다운로드하지 않았다.

- 기존 corpus: **65개 고유 파일, 71개 호출**. 기존 manifest 두 개에 HWP/HWPX 6개가 중복돼 고유 문서 수와 호출 수를 구분했다.
- 추가 구조 fixture: 직접 생성한 병합 셀·빈 셀·표 위 그림 PPT와 XLSX 서식 **4파일**.
- DOC 이미지/OCR 옵션 4조합과 혼합 배치 4개 결과를 추가했다. 총 **83개 결과 기록**, 그중 손상 DOC 1건은 의도한 개별 실패다.
- 각 구성의 XCTest **3개 모두 PASS**. 이는 입력 해시·확인 문구·순서·fullText 일관성·옵션·개별 실패 assertion 통과이며, 구성 간 동등성은 아래 별도 fingerprint 비교로 판정했다.

| 비교 항목 | 분리 전 → 분리 후 | 현재 엔진 → Ream |
|---|---:|---:|
| 전체 의미 fingerprint/오류 결과 일치 | **83/83** | **53/83** |
| PNG 바이트 해시까지 포함한 기록 일치 | 82/83 | 52/83 |
| Office 21문서 전체 텍스트 일치 | **21/21** | **10/21** |
| Office 21문서 블록 일치 | **21/21** | **0/21** |
| Office 그림 개수·PNG 바이트 일치 | **21/21** | **21/21** |

의미 fingerprint는 형식·전체 텍스트·블록 종류/텍스트/순서/원본 위치·OCR 신뢰도/원래 인식 문자열·이미지 ID/설명/방향/위치/정규화 픽셀·경고 코드/메시지/위치를 포함한다. 원시 PNG 바이트는 별도 성분으로 비교했다. 분리 전후의 1건 차이는 baseball PNG의 인코딩 바이트다. 픽셀을 sRGB RGBA로 디코딩한 결과는 같았다. 같은 샘플의 앞선 독립 실험에서 ICC 프로필 차이를 확인했지만, 이번 공통 하네스에서는 PNG chunk별 원인을 다시 분석하지 않았다. 모든 결과 바이트가 같다고 표현하지 않는다.

53/83은 정확도나 문서 성공률이 아니다. Ream의 위치 표기·경고 문장이 다른 것만으로도 전체 fingerprint는 달라진다. 반대로 확인 문구 테스트 통과만으로 전체 텍스트/표/앵커가 동등하다고 판정하지 않는다.

## 3. Ream 교체로 달라지거나 아직 보장하지 못하는 부분

| 영역 | 실제 확인한 차이·상태 | 판단 |
|---|---|---|
| DOC/DOCX 본문·표 | DOC 그림 문서와 DOCX 2개에서 fullText 차이. table_footnotes DOCX는 기존 3셀 → Ream 6셀 | 내용·단락/공백·추가 요소의 차이를 원본 정답으로 판정해야 함. 셀 증가를 기능 향상으로 단정하지 않음 |
| XLS/XLSX | XLS 3개와 XLSX 2개에서 fullText 차이. AverageTaxRates는 1,108셀 → 1,360셀 | 서식 문자열·빈 셀·수식 캐시·추가 셀을 구별하는 정답 필요. 같은 결과 계약은 아직 아님 |
| PPT/PPTX 본문 | WithMaster PPT와 PPTX 2개에서 fullText 차이 | 마스터·제목·순서·구분자의 차이를 정답과 대조해야 함 |
| 병합·빈 셀·그림 셀 | 자체 병합 PPT는 기존 8셀 → Ream 6셀과 span, 빈 셀은 양쪽 4셀. 그림 셀 PPT는 기존 0셀 → Ream 2셀+그림 1개 | 자체 fixture의 Ream 병합/그림 assertions는 통과. 모든 실제 문서에 일반화하지 않음 |
| 원본 위치·읽기 순서 | Office 21/21 블록 fingerprint가 다름. part 이름, 페이지, 셀/병합·도형 좌표 체계가 달라질 수 있음 | 위치를 키로 사용하는 소비 코드에는 호환성 검토 필요 |
| 삽입 그림 | 테스트한 Office 21개에서 그림 개수와 반환 PNG 바이트 일치. 5개 문서는 이미지 ID/위치 등 메타데이터가 다름 | 이 샘플에서는 그림 소실을 발견하지 않음. 모든 포맷/그림 종류의 앵커 동등성은 미보장 |
| 이미지/OCR 옵션 | 기본 false/false 및 4조합 동작. DOC OCR 유무와 그림 반환 개수 assertion 통과 | OCR 블록의 부모 위치/ID 체계까지 같은 것은 아님. 한영·회전 전체 회귀는 이번 미실행 |
| 경고 | Office 21/21 경고 성분이 다름. Ream loss가 현재 어댑터에서 uncertainReadingOrder로 매핑됨 | 기존의 손실 종류를 그대로 보존하는 경고 API가 아님. 경고만으로 미추출 요소를 구현 완료로 볼 수 없음 |
| 정밀 레이아웃·노트 | Ream 어댑터가 원본의 모든 노트/텍스트박스/중첩·병합 구조를 전달하는지는 미검증 | 현재 구현상 전체 기능 동등성 미확인 |
| 취소·자원 제한 | Ream 체크포인트/명시적 할당 계측, 최대 2 JS 컨텍스트와 실제 ZIP 해제 검사 추가 | 기존 엔진과 제한이 적용되는 지점이 다름. 전체 JS heap/RSS 강제 상한은 아님 |
| HWP/HWPX·PDF·이미지·텍스트 | 구현과 의존성을 유지. 기존 비Office 42문서는 의미 결과 일치 | 비교한 옵션은 이미지 true/OCR false. 기능 전수 검증과 구분 |
| 실행 비용 | 기존 15문서 Release 배치 중앙값 0.053초/169MiB, Ream 0.614초/274MiB | 앱은 작아지지만 성능/메모리는 악화. 별도 보고서 참조 |

Office 21개 중 fullText가 달라진 **11개**의 파일명과 성분별 일치 여부는 `SplitParity/office-differences.csv`에 기록했다. 전체 문서가 열리는 것과 모든 요소가 유지되는 것은 다른 판정이다. 이 검증에서 실제로 어떤 원문 요소가 빠졌는지 전수 확정한 것은 아니므로, 차이를 모두 누락이나 모두 개선으로 분류하지 않았다.

## 근거 및 재현

연구 폴더: `${OMNI_RESEARCH_ROOT}/SplitParity`.

- `source-comparison.json`: 소스 42파일·의존성 4개·Office 바이너리 7파일 해시/리비전.
- `ParityTests.swift`: 세 구성의 공통 assertion 및 fingerprint 코드. 본문은 출력하지 않고 해시/개수만 출력.
- `before/`, `after/`, `ream/`: 독립된 검증 구성. 원래 작업 트리는 수정하지 않음.
- `before-test.log`, `after-test.log`, `ream-test.log`, 각 DerivedData의 xcresult: 실제 실행 결과.
- `parity-results.json`, `office-differences.csv`, `compare.py`: 83건의 구성별 결과와 비교.

```bash
bash ${OMNI_RESEARCH_ROOT}/SplitParity/reproduce.sh
```

같은 Mac의 기존 의존성 캐시·Xcode·부팅된 Simulator가 필요하다. before와 after는 SourcePackagesOriginal, Ream은 SourcePackagesReam을 사용해 캐시 충돌을 피한다. 스크립트는 세 실행이 끝난 뒤 비교하며 어느 실행이 실패해도 성공으로 집계하지 않는다.

실기기·대용량·전체 앱 통합·전체 원본 정답 회귀는 이번 범위에서 실행하지 않았다. 운영 파서·의존성·앱 소스는 수정하지 않았고 커밋·푸시하지 않았다. [교체 앱 용량 및 Release 성능](REAM_REPLACEMENT_RESULTS.md)은 별도 실험 결과다.
