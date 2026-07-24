#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE_TARGET="aarch64-apple-ios"
SIMULATOR_TARGET="aarch64-apple-ios-sim"
OUTPUT_DIR="${SCRIPT_DIR}/build/swift"
BINDINGS_DIR="${OUTPUT_DIR}/bindings"
HEADERS_DIR="${OUTPUT_DIR}/headers"
XCFRAMEWORK_PATH="${OUTPUT_DIR}/MewmewCore.xcframework"

cd "${SCRIPT_DIR}"

rustup target add "${DEVICE_TARGET}" "${SIMULATOR_TARGET}"
cargo build --release --target "${DEVICE_TARGET}"
cargo build --release --target "${SIMULATOR_TARGET}"

rm -rf "${BINDINGS_DIR}" "${HEADERS_DIR}"
mkdir -p "${BINDINGS_DIR}" "${HEADERS_DIR}"
cargo run --release --bin uniffi-bindgen -- generate \
  --library "${SCRIPT_DIR}/target/${DEVICE_TARGET}/release/libmewmew_core.a" \
  --language swift \
  --out-dir "${BINDINGS_DIR}"

install -m 0644 \
  "${BINDINGS_DIR}/mewmew_coreFFI.h" \
  "${HEADERS_DIR}/mewmew_coreFFI.h"
install -m 0644 \
  "${BINDINGS_DIR}/mewmew_coreFFI.modulemap" \
  "${HEADERS_DIR}/module.modulemap"

rm -rf "${XCFRAMEWORK_PATH}"
xcodebuild -create-xcframework \
  -library "${SCRIPT_DIR}/target/${DEVICE_TARGET}/release/libmewmew_core.a" \
  -headers "${HEADERS_DIR}" \
  -library "${SCRIPT_DIR}/target/${SIMULATOR_TARGET}/release/libmewmew_core.a" \
  -headers "${HEADERS_DIR}" \
  -output "${XCFRAMEWORK_PATH}"

echo "Swift bindings: ${BINDINGS_DIR}/mewmew_core.swift"
echo "C headers: ${HEADERS_DIR}"
echo "XCFramework: ${XCFRAMEWORK_PATH}"
