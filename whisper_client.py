"""Local Whisper client using standard openai-whisper."""

import whisper
import os
import logging
import torch

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class WhisperClient:
    """Client for local Whisper transcription."""

    def __init__(self, model_size: str = "base.en", device: str | None = None, compute_type: str = "int8"):
        """
        Initialize the local Whisper model.

        Args:
            model_size: Size of the model (tiny, base, small, medium, large)
            device: "cpu", "cuda", or "mps". None to auto-detect.
            compute_type: Ignored for standard whisper (handled internally/dtype)
        """
        # Auto-detect device only when not explicitly set
        if device is None:
            if torch.backends.mps.is_available():
                device = "mps"
                logger.info("MPS (Metal) detected. Using GPU acceleration.")
            elif torch.cuda.is_available():
                device = "cuda"
                logger.info("CUDA detected. Using GPU acceleration.")
            else:
                device = "cpu"

        self.device = device
        logger.info(f"Loading Whisper model: {model_size} on {self.device}...")

        try:
            self.model = whisper.load_model(model_size, device=self.device)
            logger.info("Whisper model loaded successfully.")
        except Exception:
            logger.error(f"Failed to load Whisper model on {self.device}")
            raise

    def transcribe(self, audio_filepath: str) -> dict:
        """
        Transcribe audio file using local Whisper model.

       Args:
            audio_filepath: Path to the audio file (WAV, MP3, etc.)

        Returns:
            Dictionary with transcription result
        """
        try:
            # Transcribe
            result = self.model.transcribe(
                audio_filepath,
                fp16=False # consistent for CPU/MPS compatibility
            )
            
            text = result.get("text", "").strip()
            segments = result.get("segments", [])
            
            return {
                "text": text,
                "segments": segments,
                "success": True,
                "error": None
            }

        except Exception as e:
            logger.error(f"Transcription error: {e}")
            return {
                "text": "",
                "segments": [],
                "success": False,
                "error": str(e)
            }
