# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

"Am I Talking Too Much?" is a conversation monitoring application that tracks speaking time to help users avoid dominating discussions. It uses voice calibration and GMM-based voice profile matching to identify when the user is speaking vs. others. Two implementations share the same algorithm and profile format: Python/Streamlit (repo root) and a native iOS/SwiftUI app (`ios/`).

## Common Commands

### Python/Streamlit Version
```bash
# Install dependencies
pip install -r requirements.txt

# Run the application
streamlit run app.py
```

### iOS Version
```bash
# Generate the Xcode project (requires XcodeGen)
cd ios && xcodegen generate

# Run the DSP core tests (macOS/Xcode required)
cd ios/VoiceCore && swift test

# Regenerate Swift parity fixtures after changing voice_matcher.py
python3 ios/scripts/generate_fixtures.py
```

## Architecture

The app flows through two stages: Voice Calibration → Conversation Tracking

**Python core modules:**
- `app.py` - Main Streamlit application with UI and orchestration
- `audio_recorder.py` - Audio capture, level metering, speech detection (16kHz sample rate)
- `voice_matcher.py` - MFCC feature extraction (20 coefficients), GMM training, and log-likelihood scoring
- `whisper_client.py` - Optional OpenAI Whisper transcription client (disabled by default)
- `speaker_id.py` - Optional pyannote-based speaker embeddings (requires HuggingFace token)

**iOS modules (`ios/`):**
- `VoiceCore/` - Platform-neutral SwiftPM package: numerical port of `voice_matcher.py` (MFCC, diag-covariance GMM, profile, matching). Its tests assert parity against fixtures generated from the Python code.
- `App/Sources/` - SwiftUI app: AVAudioEngine capture at 16kHz mono, calibration and tracking screens
- `project.yml` - XcodeGen spec; the `.xcodeproj` is generated, not checked in

**Voice matching approach:** GMM trained on MFCC features; match decision based on log-likelihood score vs. calibration threshold

## Cross-Platform Parity (important)

`voice_matcher.py` and `ios/VoiceCore` implement the same math and must stay in lockstep: 512/256 framing, Hamming window, 26 mel filters, 20 MFCCs, diag GMM, threshold = mean − 1.5·std, sigmoid(0.5·margin) confidence, speech gate RMS 0.005, match gate RMS 0.01. `voice_profile.json` uses the same JSON schema on both platforms and is interchangeable. If you change the Python DSP/matching code, update the Swift port and regenerate fixtures with `ios/scripts/generate_fixtures.py`.

## Key Design Decisions

- **Fully local operation** - Transcription disabled by default, voice matching runs entirely on-device
- **Privacy-first** - No conversation audio stored, only speaking time metrics
- **Optional APIs** - OpenAI Whisper integration available but not required (Python only; the iOS app is GMM-only)
- Voice profile stored in `voice_profile.json` for persistence across sessions (both platforms)
