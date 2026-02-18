"""Integration test: calibrate on one LibriVox speaker, verify discrimination against another.

Downloads two public-domain LibriVox readings (different speakers), creates a voice
profile from Speaker A, then checks that:
  1. Chunks of Speaker A are recognised as "you"
  2. Chunks of Speaker B are recognised as "not you"
  3. An interleaved (spliced) mix is scored correctly per-chunk

Audio fixtures are cached in test/fixtures/ so they are only downloaded once.
"""

from __future__ import annotations

import os
import sys
import urllib.request
from pathlib import Path

import numpy as np
import torchaudio

# Allow imports from project root
PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from voice_matcher import create_voice_profile, match_voice, VoiceProfile

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures"

# Two solo readers from LibriVox Short Poetry Collection 264
SPEAKER_A_URL = "https://archive.org/download/spc264_2506_librivox/spc264_dream_ad_128kb.mp3"
SPEAKER_B_URL = "https://archive.org/download/spc264_2506_librivox/spc264_atcarnac_bk_128kb.mp3"

SPEAKER_A_PATH = FIXTURES_DIR / "speaker_a.mp3"
SPEAKER_B_PATH = FIXTURES_DIR / "speaker_b.mp3"

TARGET_SR = 16000  # Must match the app's sample rate


def _download_if_missing(url: str, dest: Path) -> None:
    if dest.exists() and dest.stat().st_size > 1000:
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {dest.name} ...")
    urllib.request.urlretrieve(url, str(dest))


def _load_mono_16k(path: Path) -> np.ndarray:
    """Load audio file, convert to mono float32 at 16 kHz."""
    waveform, sr = torchaudio.load(str(path))
    # To mono
    if waveform.shape[0] > 1:
        waveform = waveform.mean(dim=0, keepdim=True)
    # Resample
    if sr != TARGET_SR:
        waveform = torchaudio.transforms.Resample(sr, TARGET_SR)(waveform)
    return waveform.squeeze(0).numpy().astype(np.float32)


def _chunk_audio(audio: np.ndarray, chunk_seconds: float = 3.0) -> list[np.ndarray]:
    """Split audio into fixed-length chunks, dropping the last short one."""
    chunk_len = int(chunk_seconds * TARGET_SR)
    chunks = []
    for start in range(0, len(audio) - chunk_len + 1, chunk_len):
        chunks.append(audio[start : start + chunk_len])
    return chunks


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


def test_voice_discrimination():
    """Calibrate on Speaker A, then score chunks of both speakers."""
    # Ensure fixtures exist
    _download_if_missing(SPEAKER_A_URL, SPEAKER_A_PATH)
    _download_if_missing(SPEAKER_B_URL, SPEAKER_B_PATH)

    audio_a = _load_mono_16k(SPEAKER_A_PATH)
    audio_b = _load_mono_16k(SPEAKER_B_PATH)

    print(f"Speaker A: {len(audio_a)/TARGET_SR:.1f}s")
    print(f"Speaker B: {len(audio_b)/TARGET_SR:.1f}s")

    # --- Calibrate on Speaker A (use first 10s as the app does) ---
    calibration_audio = audio_a[: TARGET_SR * 10]
    profile = create_voice_profile(calibration_audio, TARGET_SR)
    print(f"Profile created: {profile.gmm.n_components} GMM components, threshold={profile.threshold_score:.2f}")

    # --- Score Speaker A chunks ---
    chunks_a = _chunk_audio(audio_a[TARGET_SR * 10 :])  # skip calibration portion
    a_results = []
    for chunk in chunks_a:
        is_match, conf = match_voice(chunk, profile, TARGET_SR)
        a_results.append((is_match, conf))

    a_correct = sum(1 for m, _ in a_results if m)
    a_total = len(a_results)
    a_accuracy = a_correct / a_total if a_total else 0
    print(f"\nSpeaker A (should match 'you'):")
    print(f"  {a_correct}/{a_total} chunks matched ({a_accuracy:.0%})")
    for i, (m, c) in enumerate(a_results):
        print(f"  chunk {i}: match={m}, confidence={c:.3f}")

    # --- Score Speaker B chunks ---
    chunks_b = _chunk_audio(audio_b)
    b_results = []
    for chunk in chunks_b:
        is_match, conf = match_voice(chunk, profile, TARGET_SR)
        b_results.append((is_match, conf))

    b_correct = sum(1 for m, _ in b_results if not m)
    b_total = len(b_results)
    b_accuracy = b_correct / b_total if b_total else 0
    print(f"\nSpeaker B (should NOT match 'you'):")
    print(f"  {b_correct}/{b_total} chunks rejected ({b_accuracy:.0%})")
    for i, (m, c) in enumerate(b_results):
        print(f"  chunk {i}: match={m}, confidence={c:.3f}")

    # --- Interleaved (spliced) test ---
    # Take up to 10 chunks from each, interleave A-B-A-B
    n_interleave = min(10, len(chunks_a), len(chunks_b))
    interleaved_results = []
    print(f"\nInterleaved test ({n_interleave} pairs, A-B-A-B...):")
    for i in range(n_interleave):
        # Speaker A chunk
        m_a, c_a = match_voice(chunks_a[i % len(chunks_a)], profile, TARGET_SR)
        # Speaker B chunk
        m_b, c_b = match_voice(chunks_b[i], profile, TARGET_SR)
        interleaved_results.append({"a_match": m_a, "a_conf": c_a, "b_match": m_b, "b_conf": c_b})
        label_a = "CORRECT" if m_a else "WRONG"
        label_b = "CORRECT" if not m_b else "WRONG"
        print(f"  pair {i}: A match={m_a} conf={c_a:.3f} [{label_a}] | B match={m_b} conf={c_b:.3f} [{label_b}]")

    interleaved_a_correct = sum(1 for r in interleaved_results if r["a_match"])
    interleaved_b_correct = sum(1 for r in interleaved_results if not r["b_match"])
    interleaved_total = len(interleaved_results)

    print(f"\n{'='*60}")
    print(f"RESULTS SUMMARY")
    print(f"{'='*60}")
    print(f"Speaker A recognition:  {a_accuracy:.0%} ({a_correct}/{a_total})")
    print(f"Speaker B rejection:    {b_accuracy:.0%} ({b_correct}/{b_total})")
    print(f"Interleaved A correct:  {interleaved_a_correct}/{interleaved_total}")
    print(f"Interleaved B correct:  {interleaved_b_correct}/{interleaved_total}")

    overall = (a_correct + b_correct) / (a_total + b_total) if (a_total + b_total) else 0
    print(f"Overall accuracy:       {overall:.0%}")
    print(f"{'='*60}")

    # Assertions — we expect at least 60% accuracy on each speaker
    assert a_accuracy >= 0.6, f"Speaker A recognition too low: {a_accuracy:.0%}"
    assert b_accuracy >= 0.6, f"Speaker B rejection too low: {b_accuracy:.0%}"
    print("\nPASSED — voice discrimination test succeeded.")


if __name__ == "__main__":
    test_voice_discrimination()
