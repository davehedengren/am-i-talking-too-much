# Am I Talking Too Much?

A privacy-first conversation tracker that monitors your speaking percentage in real time. Calibrate your voice, start a conversation, and get instant feedback on whether you're dominating the discussion.

Built with Python and Streamlit. All voice matching runs locally on your machine — no audio is stored or sent anywhere.

## Quick Start

```bash
pip install -r requirements.txt
streamlit run app.py
```

## How It Works

1. **Voice Calibration** — Record a 10-second sample of your voice. The app builds a GMM (Gaussian Mixture Model) profile from your MFCC features.
2. **Conversation Tracking** — The app listens in 2-second chunks, detects speech, and matches each chunk against your voice profile. You get a live percentage and color-coded feedback:
   - **Green** (< 40%) — Great listening
   - **Yellow** (40–55%) — Balanced
   - **Red** (> 55%) — Talking a lot

Your voice profile is saved to `voice_profile.json` so you only calibrate once.

## Optional Features

### Speaker Embeddings (pyannote)

For more accurate speaker identification, you can enable local speaker embeddings via a HuggingFace model:

1. Get a [HuggingFace token](https://huggingface.co/settings/tokens)
2. Create a `.env` file: `HUGGING_FACE_API_KEY=your_token_here`
3. Re-calibrate your voice — an embedding will be created automatically

The app falls back to the built-in GMM matcher if no token is set.

### Whisper Transcription

Live transcription is available but disabled by default. Toggle it on in the sidebar during tracking. Uses the local `openai-whisper` model (no API key needed).

## Running Tests

```bash
pytest test/
```

The voice discrimination test requires fixture audio files in `test/fixtures/` (not checked in due to size). See `test/test_voice_discrimination.py` for details.

## License

MIT
