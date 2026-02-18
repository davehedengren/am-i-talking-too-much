"""Audio recording utilities using sounddevice."""

import logging
import numpy as np
import sounddevice as sd
import soundfile as sf
import tempfile
import os
from typing import Optional

logger = logging.getLogger(__name__)


SAMPLE_RATE = 16000  # 16kHz for Whisper compatibility
CHANNELS = 1


def record_audio(duration: float, sample_rate: int = SAMPLE_RATE, device: Optional[int] = None) -> np.ndarray:
    """
    Record audio for a specified duration.

    Args:
        duration: Recording duration in seconds
        sample_rate: Sample rate in Hz (default 16kHz for Whisper)
        device: Audio input device ID (None for default)

    Returns:
        numpy array of audio samples
    """
    audio = sd.rec(
        int(duration * sample_rate),
        samplerate=sample_rate,
        channels=CHANNELS,
        dtype=np.float32,
        device=device
    )
    sd.wait()
    return audio.flatten()


def get_audio_level(duration: float = 0.1, device: Optional[int] = None) -> float:
    """
    Get current audio input level (for level meter).

    Args:
        duration: Sample duration in seconds
        device: Audio input device ID

    Returns:
        RMS level (0.0 to 1.0 range, clamped)
    """
    try:
        audio = sd.rec(
            int(duration * SAMPLE_RATE),
            samplerate=SAMPLE_RATE,
            channels=CHANNELS,
            dtype=np.float32,
            device=device
        )
        sd.wait()
        audio_flat = audio.flatten()
        if len(audio_flat) == 0:
            return 0.0
        rms = calculate_rms(audio_flat)
        # Handle NaN
        if np.isnan(rms):
            return 0.0
        # Scale up significantly for visual feedback (typical speech RMS is 0.01-0.05)
        # Use 50x multiplier so normal speech shows ~50-100%
        return min(max(rms * 50, 0.0), 1.0)
    except Exception:
        logger.debug("Failed to read audio level", exc_info=True)
        return 0.0


def set_default_device(device_id: int) -> None:
    """Set the default input device."""
    sd.default.device[0] = device_id


def save_audio(audio_data: np.ndarray, filepath: str, sample_rate: int = SAMPLE_RATE) -> str:
    """
    Save audio data to a WAV file.

    Args:
        audio_data: numpy array of audio samples
        filepath: Path to save the file
        sample_rate: Sample rate in Hz

    Returns:
        Path to saved file
    """
    sf.write(filepath, audio_data, sample_rate)
    return filepath


def load_audio(filepath: str) -> tuple[np.ndarray, int]:
    """
    Load audio from a WAV file.

    Args:
        filepath: Path to the audio file

    Returns:
        Tuple of (audio_data, sample_rate)
    """
    audio_data, sample_rate = sf.read(filepath)
    return audio_data.astype(np.float32), sample_rate


def save_to_temp_file(audio_data: np.ndarray, sample_rate: int = SAMPLE_RATE) -> str:
    """
    Save audio to a temporary WAV file.

    Args:
        audio_data: numpy array of audio samples
        sample_rate: Sample rate in Hz

    Returns:
        Path to temporary file
    """
    temp_file = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    temp_path = temp_file.name
    temp_file.close()
    sf.write(temp_path, audio_data, sample_rate)
    return temp_path


def get_audio_devices() -> list[dict]:
    """Get list of available audio input devices."""
    devices = sd.query_devices()
    input_devices = []
    for i, device in enumerate(devices):
        if device['max_input_channels'] > 0:
            input_devices.append({
                'id': i,
                'name': device['name'],
                'channels': device['max_input_channels'],
                'sample_rate': device['default_samplerate']
            })
    return input_devices


def calculate_rms(audio_data: np.ndarray) -> float:
    """Calculate RMS (root mean square) amplitude of audio."""
    return float(np.sqrt(np.mean(audio_data ** 2)))


def detect_speech(audio_data: np.ndarray, threshold: float = 0.01) -> bool:
    """
    Simple speech detection based on RMS amplitude.

    Args:
        audio_data: numpy array of audio samples
        threshold: RMS threshold for speech detection

    Returns:
        True if speech detected, False otherwise
    """
    rms = calculate_rms(audio_data)
    return rms > threshold
