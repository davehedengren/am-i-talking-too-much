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
    similarity_threshold: float = 0.45


class SpeakerEmbedder:
    """Generate speaker embeddings from audio using a local pyannote model."""

    MODEL_URL = "https://huggingface.co/pyannote/embedding"

    def __init__(self, config: SpeakerEmbeddingConfig, auth_token: Optional[str] = None):
        self.config = config
        self.device = self._select_device()
        try:
            self.model = Model.from_pretrained(config.model_id, token=auth_token)
        except Exception as e:
            err = str(e)
            if "401" in err or "Unauthorized" in err:
                raise RuntimeError(
                    f"HuggingFace returned 401 Unauthorized. "
                    f"Please accept the model license at {self.MODEL_URL} "
                    f"and verify your HUGGING_FACE_API_KEY is valid."
                ) from e
            if "403" in err or "Forbidden" in err or "gated" in err.lower():
                raise RuntimeError(
                    f"HuggingFace returned 403 Forbidden. "
                    f"Your token may lack 'read' scope, or was created before you "
                    f"accepted the license. Try creating a new token with 'read' "
                    f"permission at https://huggingface.co/settings/tokens after "
                    f"accepting the license at {self.MODEL_URL}"
                ) from e
            raise
        self.model.to(self.device)
        self.inference = Inference(self.model, window="whole", device=self.device)

    @staticmethod
    def _select_device() -> torch.device:
        if torch.backends.mps.is_available():
            return torch.device("mps")
        if torch.cuda.is_available():
            return torch.device("cuda")
        return torch.device("cpu")

    def embedding_from_audio(self, audio_data: np.ndarray, sample_rate: int) -> np.ndarray:
        waveform = torch.tensor(audio_data, dtype=torch.float32).to(self.device)
        if waveform.ndim == 1:
            waveform = waveform.unsqueeze(0)
        embedding = self.inference({"waveform": waveform, "sample_rate": sample_rate})
        return np.asarray(embedding, dtype=np.float32)

    def enroll_from_audio(self, audio_data: np.ndarray, sample_rate: int,
                          chunk_duration: float = 2.0) -> np.ndarray:
        """Create an enrollment embedding by averaging chunk embeddings.

        This produces an embedding that is comparable to the short chunks
        used during real-time tracking, unlike a single embedding from
        the full recording which lives in a different region of the
        embedding space.
        """
        chunk_size = int(chunk_duration * sample_rate)
        embeddings = []
        for start in range(0, len(audio_data) - chunk_size + 1, chunk_size):
            chunk = audio_data[start:start + chunk_size]
            embeddings.append(self.embedding_from_audio(chunk, sample_rate))
        if not embeddings:
            # Audio shorter than one chunk — fall back to full recording
            return self.embedding_from_audio(audio_data, sample_rate)
        avg = np.mean(embeddings, axis=0)
        avg = avg / np.linalg.norm(avg)  # L2-normalize
        return avg


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
