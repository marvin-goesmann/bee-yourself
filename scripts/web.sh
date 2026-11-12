#!/bin/sh
set -e
cd "$(dirname "$0")/.."
toolchain="${SWIFT_WASM_TOOLCHAIN:-$HOME/Library/Developer/Toolchains/swift-6.3.2-RELEASE.xctoolchain}"
"$toolchain/usr/bin/swift" build -c release --swift-sdk swift-6.3.2-RELEASE_wasm --scratch-path .build-wasm \
  -Xlinker --export-dynamic -Xswiftc -Xclang-linker -Xswiftc -mexec-model=reactor
wasm-opt -Oz --strip-debug --strip-producers .build-wasm/release/BeeMeadow.wasm -o site/bee.wasm
ls -lh site/bee.wasm
