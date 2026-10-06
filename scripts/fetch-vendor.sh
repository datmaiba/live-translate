#!/usr/bin/env bash
# Downloads prebuilt sherpa-onnx + onnxruntime static xcframeworks and the speaker-embedding model.
# Pinned versions + SHA-256 so builds are reproducible. Run from the repo root.
set -euo pipefail

SHERPA_VERSION=1.13.8
ORT_VERSION=1.28.2

fetch() { # url dest sha256
  local url=$1 dest=$2 sum=$3
  if [ -f "$dest" ] && echo "$sum  $dest" | shasum -a 256 -c - >/dev/null 2>&1; then
    echo "cached: $dest"; return
  fi
  curl -fsSL --retry 3 -o "$dest" "$url"
  echo "$sum  $dest" | shasum -a 256 -c -
}

mkdir -p Vendor LiveTranslate/Resources/Models

fetch "https://github.com/k2-fsa/sherpa-onnx/releases/download/xcframework/sherpa-onnx-v${SHERPA_VERSION}-ios-static.xcframework.zip" \
  Vendor/sherpa.zip 6b8e769cb153343270fdccbe92e3b3db0d1c421d67fa0989ab01fdf5b2fcf2de
fetch "https://github.com/csukuangfj/onnxruntime-libs/releases/download/v${ORT_VERSION}/onnxruntime-ios-static-xcframework-${ORT_VERSION}.xcframework.zip" \
  Vendor/onnxruntime.zip 2c2299acbb461d26d4bac4bc85985d40e7c7177ed6072703ae0846d88b0b4599
fetch "https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx" \
  LiveTranslate/Resources/Models/speaker-campplus.onnx aa3cfc16963a10586a9393f5035d6d6b57e98d358b347f80c2a30bf4f00ceba2

rm -rf Vendor/sherpa-onnx.xcframework Vendor/onnxruntime.xcframework
unzip -qo Vendor/sherpa.zip -d Vendor
unzip -qo Vendor/onnxruntime.zip -d Vendor
ls -d Vendor/*.xcframework
