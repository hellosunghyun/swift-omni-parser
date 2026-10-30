# wmf-emf-renderer 0.2.1

OmniParser는 RTF 등에 포함된 WMF·EMF를 온디바이스에서 래스터화하기 위해 이 MIT 라이브러리를 사용합니다. 새 native binary나 npm runtime 의존성은 없습니다.

- 원본 저장소: https://github.com/congduan/WmfEmfViewer/tree/434e8b07bcf2ddf3676bc65706ea50e7dc6930c9/packages/wmf-emf-renderer
- 배포 원본: https://registry.npmjs.org/wmf-emf-renderer/-/wmf-emf-renderer-0.2.1.tgz
- npm gitHead: `434e8b07bcf2ddf3676bc65706ea50e7dc6930c9`
- npm integrity SHA512: `i3sjOA35k+ayF4SZDWczXCcltpi7Bema4JcyUZ1vnpFWFdzPWRyCFWcbdlOZyOUDXGWD4+nm8OA2u1fNjKzXnA==`
- 원본 `index.js` SHA256: `543bb78b70617569f28905e7b2e0c174330f87bfa3cdf38fa828ba093813ecc9`
- 변환본 `renderer.js` SHA256: `36dea09a79c9d3b2526352e6dc9047152896c64cb0cd088bfdc2f3ebd650fc95`

`upstream/index.js`와 `upstream/package.json`은 npm 원문을 보존한 검토용 사본입니다. SwiftPM은 이 폴더를 앱 리소스로 포함하지 않습니다. 앱에 포함되는 것은 `Sources/OmniParser/Resources/Vector/renderer.js`와 같은 폴더의 MIT `LICENSE.txt`입니다. 상업용·비공개 앱에 사용할 수 있으며, 배포 시 MIT 원문과 저작권 고지를 유지해야 합니다. 라이브러리 원문은 이 폴더의 `LICENSE`에도 보존했습니다.

## 로컬 변경과 재생성

`prepare.cjs`는 개발 시 Node에 포함된 Acorn parser로 JavaScript AST를 읽습니다. 제품에는 Node·Acorn을 추가하지 않습니다. 119개 모든 for/for-in/for-of/while/do-while의 본문 시작에 `__omniBudget()`을 삽입하고, 다시 AST를 읽어 119개 모두 보호되는지 확인합니다. 본문이 한 문장인 루프도 block으로 감쌉니다. 문자열·주석은 수정하지 않습니다. 또한 단일 `f.family` 출력 지점을 `_SvgContext._esc(f.family)`로 감싸 SVG font-family XML escaping을 보완합니다. unknown/unimplemented 로그 네 곳과 실제 처리가 없는 process 메서드 44곳은 부분 지원 flag를 남깁니다. 문서 header와 명백한 comment 세 메서드는 제외합니다. 부분 그림은 보존하면서 호스트에 위치 경고를 제공하기 위한 변경입니다. WMF TextOut의 좌표 읽기 두 곳은 홀수 바이트 문자열 뒤의 WORD padding을 건너뛰도록 보완합니다. SVG의 node·defs 배열 초기화 두 곳은 `__omniNodes([])`로 감싸 문자열을 저장하기 전에 누적 출력 크기를 제한합니다. 예상 원본 hash·루프 수·수정 지점 수가 다르면 생성에 실패합니다.

저장소 루트에서 실행합니다.

```sh
node --expose-internals ThirdParty/wmf-emf-renderer/prepare.cjs ThirdParty/wmf-emf-renderer/upstream/index.js Sources/OmniParser/Resources/Vector/renderer.js
```

Swift의 별도 JS bootstrap은 취소·시간·연산량 검사, typed-array 생성 크기 제한, 한국어 문자 디코딩, base64 bridge를 제공합니다. upstream WMF TextOut의 단일 바이트 문자열 처리는 선택된 DBCS charset에 맞는 TextDecoder wrapper로 보완합니다. 공개 iOS JavaScriptCore에는 실행시간 제한 설정 API가 없어 협력형 루프 검사를 사용합니다. 이는 프로세스 전체의 절대 메모리 상한이나 강제 선점 중단을 보장하는 API가 아닙니다. 입력·레코드·이미지 크기 검사, 출력 SVG allowlist 검사와 직렬 실행을 함께 적용합니다.

## 지원 경계

upstream은 모든 Windows GDI·EMF+ 레코드의 완전한 재현을 보장하지 않습니다. Windows 글꼴이 설치되어 있지 않으면 iOS 글꼴로 대체됩니다. SVG에 외부 URL, 스크립트, foreignObject, filter, use, 미지원 속성, 엔티티가 있으면 거부합니다. 오류는 호스트 파서가 위치가 있는 경고와 나머지 문서 결과로 처리합니다. HTML 화면·네트워크 다운로드·문서 실행에는 사용하지 않습니다.
