# 파싱 회귀 테스트 자산

이 폴더는 OmniParserTests의 리소스이며 OmniParser 제품이나 소비 앱에 포함되는 런타임 자산이 아니다. 테스트는 원격 문서를 다운로드하지 않는다. 기존 샘플은 앱 저장소 `8c565d89a4d6f1fede6893a645f0f0ccdf8fe007`에서 내용 변경 없이 이관했고, 새 자체 회귀 입력은 아래에 구분했다.

- `Manifest.json`: 고유 입력 65개. RealWorld 60개와 자체 Office/HWP 5개. 현재 파일 해시·확인 문구·기존 최소 기대값.
- `RealWorld/RealWorldManifest.json`: 외부 60개 파일의 원본 URL·고정 커밋·해시·라이선스 근거·발췌/변경 이력. 원격 원본 해시와 현재 파일 해시는 다를 수 있다.
- `RealWorld/GoldenAssertions.json`: 기존 원본 대조에 근거한 부분 정답. 전체 문서의 완전한 정답이나 새로운 권리 검토 완료를 뜻하지 않는다.
- `Generated/`: 병합/빈 셀/그림 셀 PPT, XLSX 서식, 경로 탈출·선언 크기 불일치 ZIP. 실제 사용자 문서가 아닌 자체 작성 내용이다. 구조 샘플과 위험 샘플의 provenance JSON을 구분했다.
- `LegacyImage.png`: 자체 Office·OCR 마커 그림. 다중 프레임 TIFF와 일반/스캔/혼합 PDF는 이를 사용해 테스트 중 메모리에서 생성한다.
- `PDFAdjacentText/`: 네이티브 `ITEM 12`와 별도 숫자 `12` 그림을 가까이 배치한 자체 PDF다. 외부 자산 없이 만든 968바이트 입력이며 자체 MIT 조건을 적용한다. 출처·해시·생성 방식을 `Provenance.json`에 기록했다. 기존 65문서 대조 코퍼스와 구분하며 이 파일은 새 PDF 위치·중복 회귀 실행에 필요하다.
- `Licenses/`: 외부 원본 LICENSE/NOTICE/README 15파일을 내용 변경 없이 보존했다. 기존 출처 안내에서 ResearchersTests 경로는 분리 전 저장소의 경로다. 현재 경로는 Tests/OmniParserTests/Fixtures다.

Generated의 Office 샘플은 Ream 테스트 빌더(고정 리비전 `253cb67f1f7f8d3f7493f4f2ba09a8855fe16d24`와 실험용 빌더 옵션 수정)로 생성했다. Ream을 패키지 의존성이나 테스트 실행 의존성으로 추가하지 않았다. 빌더의 MIT 고지도 `Licenses/Ream-builder-MIT.txt`에 보존했다. 생성 당시 스크립트는 로컬 `Research/reamkit/build-replacement-fixtures.ts`에 있으며 공개 저장소에 포함된 재생성 도구는 아니다. 포함된 입력만으로 테스트는 실행된다.

외부 자산에 OmniParser의 MIT를 일괄 적용하지 않는다. HWP/HWPX 원본 README·출처·원래 라이선스를 함께 보존하며, 공공누리 문구나 플래그만으로 다른 라이선스를 선언하지 않는다. 라이선스 사본 보존은 파일별 별도 권리 허락을 새로 받았다는 뜻이 아니다.

XLS 차트 캐시 결함은 OfficeSourceTruthTests가 현재 실패로 검출한다. 파서 출력을 정답으로 복사하거나 실패를 skip/expected-failure로 감추지 않는다. 검증은 원본 기반 기대값과 기존 구현의 결과 비교를 구분한다.

대용량 스캔, LibreOffice 변환 출력, 원문 진단 덤프, 측정 로그와 Ream 실행 JS 번들은 포함하지 않았다. 이 파일들이 필요한 대규모 성능 검증과 현재의 기능 회귀는 별개다.
