# 로컬 연구 경로 별칭

공개 문서에 개인 절대 경로를 남기지 않기 위해 당시 실행 경로의 접두부만 다음 변수로 표기했다. 실제 입력·명령 옵션·측정 결과는 바꾸지 않았다.

| 변수 | 의미 |
|---|---|
| OMNI_SOURCE_ROOT | 현재 OmniParser 저장소 루트 |
| OMNI_RESEARCH_ROOT | 검증용 캐시 루트. 이 Mac에서는 HOME/Library/Caches/OmniParser/Research |
| OMNI_CACHE_ROOT | SwiftPM 의존성 캐시들의 부모. 이 Mac에서는 HOME/Library/Caches/OmniParser |
| PARSER_APP_ROOT | 분리 전 앱 코드·샘플을 확인한 기존 앱 저장소 체크아웃 |

```bash
OMNI_SOURCE_ROOT="$PWD"
OMNI_CACHE_ROOT="$HOME/Library/Caches/OmniParser"
OMNI_RESEARCH_ROOT="$OMNI_CACHE_ROOT/Research"
# PARSER_APP_ROOT는 본인의 앱 저장소 체크아웃 경로로 지정한다.
```

예전 조사 보고서의 실행 스크립트·원시 결과·진단 덤프·독립 후보 체크아웃은 해당 연구 캐시에 보관했던 기록이며 공개 저장소에 모두 포함한 것은 아니다. 그 문서의 명령만으로 새 머신에서 당시 캐시가 자동 재생성되는 것은 아니다. 운영 회귀 테스트와 입력은 Tests/OmniParserTests에 포함돼 있으며, 최신 OdrCore 전체 재빌드는 ODR_NATIVE_REBUILD.md에 필요한 패치·절차를 구분했다.

## 후속 기능 검증 결과

2026-10-27 이후 RTF·부분 복구 검증의 원시 로그와 xcresult는 캐시 대신 `HOME/Documents/Codex/OmniParserVerification/2026-10-27`에 보관했다. 10월 30일 실행도 이 폴더 아래 날짜가 붙은 파일로 구분한다. 이전 캐시 기록은 현재 환경에 없을 수 있으며 새 결과와 재현 명령은 [최종 검증 기록](COMPLETION_VERIFICATION.md)을 따른다. 이 출력 폴더나 임시 호스트 앱은 패키지 Git에 넣지 않는다.
