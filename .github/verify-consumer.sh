#!/bin/bash
set -euo pipefail
# 버전 의존성의 해석도 검사하므로 로컬 path 의존성 빌드로 대신하지 않는다.
if [[ $# != 1 || -e "$1" ]]; then
  echo '사용법: bash .github/verify-consumer.sh /새로운/소비자검증폴더' >&2
  exit 2
fi
root="$(git rev-parse --show-toplevel)"
mkdir "$1"
output="$(cd "$1" && pwd)"
# 아직 게시하지 않은 커밋도 SemVer 소비자의 제약으로 검사한다. 이 태그는 로컬 mirror 안에만 만든다.
git clone --quiet --bare --no-hardlinks "$root" "$output/swift-omni-parser.git"
git --git-dir="$output/swift-omni-parser.git" update-ref refs/tags/0.0.0-consumer-check "$(git -C "$root" rev-parse HEAD)"
mkdir -p "$output/Consumer/Sources/OmniParserConsumer"
python3 - "$output" <<'PY'
import json, pathlib, sys
output = pathlib.Path(sys.argv[1])
url = json.dumps((output / 'swift-omni-parser.git').as_uri())
manifest = '''// swift-tools-version: 6.2
import PackageDescription
let package = Package(
  name: "OmniParserConsumer",
  platforms: [.iOS("27.0")],
  products: [.library(name: "OmniParserConsumer", targets: ["OmniParserConsumer"])],
  dependencies: [.package(url: __URL__, exact: "0.0.0-consumer-check")],
  targets: [.target(name: "OmniParserConsumer", dependencies: [
    .product(name: "OmniParser", package: "swift-omni-parser")
  ])],
  swiftLanguageModes: [.v5]
)
'''.replace('__URL__', url)
(output / 'Consumer/Package.swift').write_text(manifest)
(output / 'Consumer/Sources/OmniParserConsumer/Consumer.swift').write_text('''import Foundation
import OmniParser

public func parseLocalDocument(_ url: URL) async throws -> String {
  let result = try await DocumentParser.parse(.url(url))
  return result.fullText
}
''')
PY
cd "$output/Consumer"
xcodebuild build -scheme OmniParserConsumer -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$output/DerivedData" -packageAuthorizationProvider netrc \
  -skipMacroValidation CODE_SIGNING_ALLOWED=NO
