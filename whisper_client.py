"""OpenAI Whisper API client for transcription."""

from openai import OpenAI
from typing import Optional
import os


class WhisperClient:
    """Client for OpenAI Whisper transcription API."""

    def __init__(self, api_key: Optional[str] = None):
        """
        Initialize the Whisper client.

        Args:
            api_key: OpenAI API key. If not provided, uses OPENAI_API_KEY env var.
        """
        self.api_key = api_key or os.getenv("OPENAI_API_KEY")
        if not self.api_key:
            raise ValueError("OpenAI API key required. Set OPENAI_API_KEY or pass api_key.")

        self.client = OpenAI(api_key=self.api_key)

    def transcribe(self, audio_filepath: str, language: str = "en") -> dict:
        """
        Transcribe audio file using Whisper API.

        Args:
            audio_filepath: Path to the audio file (WAV, MP3, etc.)
            language: Language code (default: "en" for English)

        Returns:
            Dictionary with transcription result:
            {
                "text": str,          # Full transcription
                "segments": list,     # Word/segment level timestamps (if available)
                "success": bool,
                "error": str or None
            }
        """
        try:
            with open(audio_filepath, "rb") as audio_file:
                response = self.client.audio.transcriptions.create(
                    model="whisper-1",
                    file=audio_file,
                    language=language,
                    response_format="verbose_json",
                    timestamp_granularities=["segment"]
                )

            return {
                "text": response.text,
                "segments": response.segments if hasattr(response, 'segments') else [],
                "success": True,
                "error": None
            }

        except Exception as e:
            return {
                "text": "",
                "segments": [],
                "success": False,
                "error": str(e)
            }

    def transcribe_simple(self, audio_filepath: str, language: str = "en") -> str:
        """
        Simple transcription that returns just the text.

        Args:
            audio_filepath: Path to the audio file
            language: Language code

        Returns:
            Transcription text, or empty string on error
        """
        result = self.transcribe(audio_filepath, language)
        return result["text"]


def test_api_key(api_key: str) -> tuple[bool, str]:
    """
    Test if an OpenAI API key is valid.

    Args:
        api_key: OpenAI API key to test

    Returns:
        Tuple of (is_valid, message)
    """
    try:
        client = OpenAI(api_key=api_key)
        # Just list models to verify the key works
        client.models.list()
        return True, "API key is valid"
    except Exception as e:
        return False, f"Invalid API key: {str(e)}"
