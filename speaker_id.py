"""Local speaker embedding and matching using pyannote.audio."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional, Tuple
import json
import numpy as np
import torch
from pyannote.audio import Model, Inference


@dataclass
class SpeakerEmbeddingConfig:
    model_id: str = "pyannote/embedding"
    similarity_threshold: float = 0.65


class SpeakerEmbedder:
    """Generate speaker embeddings from audio using a local pyannote model."""

    def __init__(self, config: SpeakerEmbeddingConfig, auth_token: Optional[str] = None):
        self.config = config
        self.device = self._select_device()
        self.model = Model.from_pretrained(config.model_id, use_auth_token=auth_token)
        self.model.to(self.device)
        self.inference = Inference(self.model, window="whole", device=self.device)

    @staticmethod
    def _select_device() -> str:
        if torch.backends.mps.is_available():
            return "mps"
        if torch.cuda.is_available():
            return "cuda"
        return "cpu"

    def embedding_from_audio(self, audio_data: np.ndarray, sample_rate: int) -> np.ndarray:
        waveform = torch.tensor(audio_data, dtype=torch.float32).to(self.device)
        if waveform.ndim == 1:
            waveform = waveform.unsqueeze(0)
        embedding = self.inference({"waveform": waveform, "sample_rate": sample_rate})
        return np.asarray(embedding, dtype=np.float32)


def save_embedding(embedding: np.ndarray, filepath: str) -> None:
    """Persist embedding to disk as JSON."""
    payload = {"embedding": embedding.tolist()}
    with open(filepath, "w") as file:
        json.dump(payload, file)


def load_embedding(filepath: str) -> np.ndarray:
    """Load embedding from disk."""
    with open(filepath, "r") as file:
        payload = json.load(file)
    return np.asarray(payload["embedding"], dtype=np.float32)


def cosine_similarity(a: np.ndarray, b: np.ndarray) -> float:
    """Compute cosine similarity between two vectors."""
    denom = float(np.linalg.norm(a) * np.linalg.norm(b))
    if denom == 0.0:
        return 0.0
    return float(np.dot(a, b) / denom)


def match_embedding(
    audio_data: np.ndarray,
    sample_rate: int,
    embedder: SpeakerEmbedder,
    enrolled_embedding: np.ndarray,
    threshold: Optional[float] = None,
) -> Tuple[bool, float]:
    """Compare audio segment embedding against enrolled voice."""
    similarity_threshold = threshold if threshold is not None else embedder.config.similarity_threshold
    current_embedding = embedder.embedding_from_audio(audio_data, sample_rate)
    similarity = cosine_similarity(current_embedding, enrolled_embedding)
    confidence = max(0.0, min(1.0, (similarity + 1.0) / 2.0))
    return similarity >= similarity_threshold, confidence
