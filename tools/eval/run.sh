#!/bin/bash
# Build and run the ground-truth eval harness on macOS.
# Usage: tools/eval/run.sh <audio.wav> <labels.json>
#
# Compiles the real pipeline sources (VoiceCore + the app's pure analysis
# files) together with eval.swift into one module, so what's measured is what
# ships. `import VoiceCore` lines are stripped because everything is compiled
# as a single module.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="${TMPDIR:-/tmp}/amitalking-eval-build"
rm -rf "$BUILD" && mkdir -p "$BUILD"

SOURCES=(
  ios/VoiceCore/Sources/VoiceCore/FFT.swift
  ios/VoiceCore/Sources/VoiceCore/MFCC.swift
  ios/VoiceCore/Sources/VoiceCore/GaussianMixture.swift
  ios/VoiceCore/Sources/VoiceCore/SeededRandom.swift
  ios/VoiceCore/Sources/VoiceCore/VoiceMatcher.swift
  ios/VoiceCore/Sources/VoiceCore/VoiceProfile.swift
  ios/VoiceCore/Sources/VoiceCore/WavCodec.swift
  ios/App/Sources/NoiseFloor.swift
  ios/App/Sources/VoicedTrim.swift
  ios/App/Sources/NeuralVoiceProfile.swift
  ios/App/Sources/NeuralVoiceEnroller.swift
  ios/App/Sources/NeuralVoiceEmbedder.swift
)

for src in "${SOURCES[@]}"; do
  sed 's/^import VoiceCore$//' "$ROOT/$src" > "$BUILD/$(basename "$src")"
done
cp "$ROOT/tools/eval/eval.swift" "$BUILD/"

swiftc -O -parse-as-library "$BUILD"/*.swift -o "$BUILD/eval"
"$BUILD/eval" "$1" "$2"
