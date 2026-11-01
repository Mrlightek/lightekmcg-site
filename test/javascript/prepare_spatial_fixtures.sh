#!/usr/bin/env bash
set -euo pipefail
fixture_root="${STUDIO_VISION_CACHE:-/tmp/lightek-spatial-runtime}"
mkdir -p "$fixture_root"
fetch_fixture() {
  local fixture_name="$1" fixture_url="$2"
  if [[ ! -s "$fixture_root/$fixture_name" ]]; then
    curl --fail --location --retry 2 --max-time 90 --silent --show-error "$fixture_url" -o "$fixture_root/$fixture_name.part"
    mv "$fixture_root/$fixture_name.part" "$fixture_root/$fixture_name"
  fi
}
fetch_fixture vision_bundle.mjs https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.32/vision_bundle.mjs
fetch_fixture vision_wasm_internal.js https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.32/wasm/vision_wasm_internal.js
fetch_fixture vision_wasm_internal.wasm https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.32/wasm/vision_wasm_internal.wasm
fetch_fixture vision_wasm_nosimd_internal.js https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.32/wasm/vision_wasm_nosimd_internal.js
fetch_fixture vision_wasm_nosimd_internal.wasm https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.32/wasm/vision_wasm_nosimd_internal.wasm
fetch_fixture face_landmarker.task https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task
fetch_fixture selfie_segmenter.tflite https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter/float16/1/selfie_segmenter.tflite
fetch_fixture portrait.jpg https://storage.googleapis.com/mediapipe-assets/portrait.jpg
ffmpeg -v error -y -f lavfi -i color=c=blue:s=320x240:r=24:d=4 -c:v libvpx -an /tmp/spatial-blue.webm
ffmpeg -v error -y -f lavfi -i color=c=red:s=320x240:r=24:d=4 -c:v libvpx -an /tmp/spatial-red.webm
