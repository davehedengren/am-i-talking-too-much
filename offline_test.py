"""Offline diarization + speaker match for a recorded audio file."""

from __future__ import annotations

import argparse
import os
from collections import defaultdict
from typing import Dict, Tuple

import numpy as np
import torchaudio
from pyannote.audio import Pipeline
from dotenv import load_dotenv

from speaker_id import SpeakerEmbedder, SpeakerEmbeddingConfig, cosine_similarity, load_embedding


def load_audio(filepath: str) -> Tuple[np.ndarray, int]:
    """Load audio file into mono float32 numpy array."""
    waveform, sample_rate = torchaudio.load(filepath)
    if waveform.ndim == 2 and waveform.shape[0] > 1:
        waveform = waveform.mean(dim=0, keepdim=True)
    if waveform.ndim == 2:
        waveform = waveform.squeeze(0)
    return waveform.numpy().astype(np.float32), int(sample_rate)


def slice_audio(audio: np.ndarray, sample_rate: int, start: float, end: float) -> np.ndarray:
    start_idx = max(0, int(start * sample_rate))
    end_idx = min(len(audio), int(end * sample_rate))
    if end_idx <= start_idx:
        return np.array([], dtype=np.float32)
    return audio[start_idx:end_idx]


def main() -> None:
    parser = argparse.ArgumentParser(description="Offline speaker diarization + match.")
    parser.add_argument("audio_path", help="Path to audio file (e.g., .m4a)")
    parser.add_argument("--embedding", default="speaker_embedding.json", help="Path to enrolled embedding JSON")
    parser.add_argument("--min-duration", type=float, default=1.0, help="Min segment duration to evaluate")
    parser.add_argument("--threshold", type=float, default=0.65, help="Similarity threshold for 'you'")
    args = parser.parse_args()

    load_dotenv()
    token = os.getenv("HUGGING_FACE_API_KEY")
    if not token:
        raise SystemExit("HUGGING_FACE_API_KEY not set.")

    enrolled_embedding = load_embedding(args.embedding)
    embedder = SpeakerEmbedder(
        config=SpeakerEmbeddingConfig(similarity_threshold=args.threshold),
        auth_token=token,
    )

    print("Loading audio...")
    audio, sample_rate = load_audio(args.audio_path)

    print("Running diarization...")
    pipeline = Pipeline.from_pretrained("pyannote/speaker-diarization-3.1", token=token)
    diarization = pipeline(args.audio_path)

    speaker_durations: Dict[str, float] = defaultdict(float)
    speaker_scores: Dict[str, list[float]] = defaultdict(list)

    for turn, _, speaker in diarization.itertracks(yield_label=True):
        duration = turn.end - turn.start
        if duration < args.min_duration:
            continue
        segment_audio = slice_audio(audio, sample_rate, turn.start, turn.end)
        if segment_audio.size == 0:
            continue
        segment_embedding = embedder.embedding_from_audio(segment_audio, sample_rate)
        similarity = cosine_similarity(segment_embedding, enrolled_embedding)
        speaker_durations[speaker] += duration
        speaker_scores[speaker].append(similarity)

    if not speaker_durations:
        raise SystemExit("No diarized segments found. Try lowering --min-duration.")

    avg_scores = {spk: float(np.mean(scores)) for spk, scores in speaker_scores.items()}
    you_speaker = max(avg_scores.items(), key=lambda item: item[1])[0]

    total_speech = sum(speaker_durations.values())
    you_time = speaker_durations[you_speaker]
    you_pct = (you_time / total_speech) * 100 if total_speech > 0 else 0.0

    print(f"Speakers found: {len(speaker_durations)}")
    print(f"Identified 'you' speaker: {you_speaker} (avg similarity {avg_scores[you_speaker]:.3f})")
    print(f"You time: {you_time:.1f}s / Total speech: {total_speech:.1f}s ({you_pct:.1f}%)")
    print("Per-speaker summary:")
    for spk, dur in sorted(speaker_durations.items(), key=lambda item: item[1], reverse=True):
        score = avg_scores.get(spk, 0.0)
        print(f"  {spk}: {dur:.1f}s, avg similarity {score:.3f}")


if __name__ == "__main__":
    main()
