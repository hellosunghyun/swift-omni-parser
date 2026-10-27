#!/bin/bash
set -euo pipefail
# 기존 배포물을 건드리지 않고, 지정한 로컬 소스로 새 검토용 번들을 만든다.
root="$(cd "$(dirname "$0")" && pwd)"
revision=5d183f4de990de254f32976bf952e548bcd25972
rust_commit=8bab26f4f68e0e26f0bb7960be334d5b520ea452
cargo_commit=c980f4866141969fab6254a680546a277789d6f0

if [[ "${1:-}" == --verify ]]; then
  cd "$root"
  shasum -a 256 -c SHA256SUMS
  exit
fi
if [[ $# != 4 || "$1" != --source || "$3" != --output ]]; then
  echo '사용법: bash build.sh --source /로컬/office_oxide --output /새로운/검토번들' >&2
  echo '기존 배포물 확인: bash build.sh --verify' >&2
  exit 2
fi
source_root="$(cd "$2" && pwd)"
output="$4"
[[ ! -e "$output" ]] || { echo '출력 경로가 이미 있습니다. 기존 자료를 보존합니다.' >&2; exit 2; }
[[ "$(git -C "$source_root" rev-parse HEAD)" == "$revision" ]] || {
  echo 'office_oxide 소스 커밋이 고정 리비전과 다릅니다.' >&2; exit 2;
}
git -C "$source_root" diff --quiet HEAD || { echo '소스의 추적 변경을 확인하세요.' >&2; exit 2; }
for tool in rustc cargo python3 xcrun xcodebuild lipo; do
  command -v "$tool" >/dev/null || { echo "필요한 도구가 없습니다: $tool" >&2; exit 2; }
done
[[ "$(rustc -vV | sed -n 's/^release: //p')" == 1.97.1 ]] || {
  echo 'Rust 1.97.1이 필요합니다. 도구를 자동 설치하거나 변경하지 않습니다.' >&2; exit 2;
}
[[ "$(rustc -vV | sed -n 's/^commit-hash: //p')" == "$rust_commit" ]] || {
  echo 'Rust 컴파일러 커밋이 제작 기준과 다릅니다.' >&2; exit 2;
}
[[ "$(cargo -vV | sed -n 's/^commit-hash: //p')" == "$cargo_commit" ]] || {
  echo 'Rust 1.97.1 배포에 대응하는 Cargo 커밋이 필요합니다.' >&2; exit 2;
}
[[ "$(xcodebuild -version)" == $'Xcode 27.1\nBuild version 27A9275' ]] || {
  echo 'Xcode 27.1 (27A9275)이 필요합니다. DEVELOPER_DIR을 확인하세요.' >&2; exit 2;
}
for sdk in iphoneos iphonesimulator; do
  [[ "$(xcrun --sdk "$sdk" --show-sdk-version)" == 27.1 ]] || exit 2
done
rust_source="$(rustc --print sysroot)/lib/rustlib/src/rust"
[[ -d "$rust_source/library" && -f "$rust_source/library/Cargo.lock" ]] || {
  echo '같은 도구 체인의 rust-src와 library/Cargo.lock이 필요합니다.' >&2; exit 2;
}
# build-std의 Cargo 설정은 사용자·저장소의 임의 환경을 상속하지 않는다.
for variable in RUSTFLAGS CARGO_ENCODED_RUSTFLAGS RUSTC_WRAPPER RUSTC_WORKSPACE_WRAPPER CARGO_BUILD_TARGET; do
  [[ -z "${!variable:-}" ]] || { echo "재현성을 위해 $variable 설정을 해제하세요." >&2; exit 2; }
done
mkdir "$output"
output="$(cd "$output" && pwd)"
mkdir "$output/source"
git -C "$source_root" archive "$revision" | tar -x -C "$output/source"
cd "$output/source"
git apply "$root/compat.patch"
export CARGO_TARGET_DIR="$output/target"
export CARGO_NET_OFFLINE=true
export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
for config in "$CARGO_HOME/config" "$CARGO_HOME/config.toml" .cargo/config .cargo/config.toml; do
  [[ ! -f "$config" ]] || { echo "알 수 없는 Cargo 설정을 상속할 수 없습니다: $config" >&2; exit 2; }
done
export SOURCE_DATE_EPOCH="$(git -C "$source_root" show -s --format=%ct "$revision")"
export ZERO_AR_DATE=1
export TZ=UTC
export LC_ALL=C
export RUSTFLAGS="--remap-path-prefix=$output=/omni-rebuild --remap-path-prefix=$rust_source=/rust-source"
export CARGO_INCREMENTAL=0
export IPHONEOS_DEPLOYMENT_TARGET=10.0
export RUSTC_BOOTSTRAP=1
# 기존 아카이브의 native 최소 버전 10.0을 유지하며 앱의 iOS 27.0 설정은 바꾸지 않는다.
# registry/vendor 캐시는 미리 준비해야 한다. 실패해도 결과·소스를 삭제하지 않는다.
cargo metadata --offline --locked --format-version 1 > "$output/cargo-metadata.json"
cargo metadata --offline --locked --format-version 1 --features std/backtrace,std/panic-unwind \
  --manifest-path "$rust_source/library/Cargo.toml" > "$output/std-metadata.json"
python3 "$root/rebuild_manifest.py" --preflight "$output" "$root" "$rust_source" "$revision"
for target in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
  cargo build --offline --locked --release --lib -Z build-std=std,panic_abort \
    -Z build-std-features=backtrace,panic-unwind \
    --target "$target" --message-format=json-render-diagnostics > "$output/build-$target.jsonl"
done
lipo -create "$CARGO_TARGET_DIR/aarch64-apple-ios-sim/release/liboffice_oxide.a" \
  "$CARGO_TARGET_DIR/x86_64-apple-ios/release/liboffice_oxide.a" -output "$output/simulator.a"
xcodebuild -create-xcframework \
  -library "$CARGO_TARGET_DIR/aarch64-apple-ios/release/liboffice_oxide.a" -headers "$root/include" \
  -library "$output/simulator.a" -headers "$root/include" -output "$output/OfficeOxide.xcframework"
python3 "$root/rebuild_manifest.py" "$output" "$root" "$rust_source" "$revision"
echo "검토용 번들: $output"
echo 'SHA256SUMS·BUILD_MANIFEST.json·구성요소 고지와 회귀 결과를 검토한 뒤 별도로 채택하세요.'
