# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

"Am I Talking Too Much?" is a Python/Streamlit conversation monitoring application that tracks speaking time to help users avoid dominating discussions. It uses voice calibration and GMM-based voice profile matching to identify when the user is speaking vs. others.

## Common Commands

### Python/Streamlit Version
```bash
# Install dependencies
pip install -r requirements.txt

# Run the application
streamlit run app.py
```

## Architecture

The app flows through two stages: Voice Calibration → Conversation Tracking

**Core modules:**
- `app.py` - Main Streamlit application with UI and orchestration
- `audio_recorder.py` - Audio capture, level metering, speech detection (16kHz sample rate)
- `voice_matcher.py` - MFCC feature extraction (20 coefficients), GMM training, and log-likelihood scoring
- `whisper_client.py` - Optional OpenAI Whisper transcription client (disabled by default)
- `speaker_id.py` - Optional pyannote-based speaker embeddings (requires HuggingFace token)

**Voice matching approach:** GMM trained on MFCC features; match decision based on log-likelihood score vs. calibration threshold

## Key Design Decisions

- **Fully local operation** - Transcription disabled by default, voice matching runs entirely on-device
- **Privacy-first** - No conversation audio stored, only speaking time metrics
- **Optional APIs** - OpenAI Whisper integration available but not required
- Voice profile stored in `voice_profile.json` (Python) for persistence across sessions
