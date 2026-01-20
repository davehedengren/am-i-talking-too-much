"""Voice feature extraction and matching for speaker identification."""

import numpy as np
from scipy.fft import fft
from scipy.signal import spectrogram
from typing import Optional
import json


class VoiceProfile:
    """Represents a voice profile with extracted features."""

    def __init__(self, mfcc_mean: np.ndarray, mfcc_std: np.ndarray,
                 spectral_centroid: float, spectral_rolloff: float):
        self.mfcc_mean = mfcc_mean
        self.mfcc_std = mfcc_std
        self.spectral_centroid = spectral_centroid
        self.spectral_rolloff = spectral_rolloff

    def to_dict(self) -> dict:
        """Convert profile to dictionary for serialization."""
        return {
            'mfcc_mean': self.mfcc_mean.tolist(),
            'mfcc_std': self.mfcc_std.tolist(),
            'spectral_centroid': self.spectral_centroid,
            'spectral_rolloff': self.spectral_rolloff
        }

    @classmethod
    def from_dict(cls, data: dict) -> 'VoiceProfile':
        """Create profile from dictionary."""
        return cls(
            mfcc_mean=np.array(data['mfcc_mean']),
            mfcc_std=np.array(data['mfcc_std']),
            spectral_centroid=data['spectral_centroid'],
            spectral_rolloff=data['spectral_rolloff']
        )


def _hz_to_mel(hz: float) -> float:
    """Convert frequency from Hz to Mel scale."""
    return 2595 * np.log10(1 + hz / 700)


def _mel_to_hz(mel: float) -> float:
    """Convert frequency from Mel scale to Hz."""
    return 700 * (10 ** (mel / 2595) - 1)


def _create_mel_filterbank(num_filters: int, fft_size: int,
                           sample_rate: int) -> np.ndarray:
    """Create a Mel filterbank matrix."""
    low_freq_mel = 0
    high_freq_mel = _hz_to_mel(sample_rate / 2)

    mel_points = np.linspace(low_freq_mel, high_freq_mel, num_filters + 2)
    hz_points = np.array([_mel_to_hz(m) for m in mel_points])

    bin_points = np.floor((fft_size + 1) * hz_points / sample_rate).astype(int)

    filterbank = np.zeros((num_filters, fft_size // 2 + 1))

    for i in range(num_filters):
        for j in range(bin_points[i], bin_points[i + 1]):
            filterbank[i, j] = (j - bin_points[i]) / (bin_points[i + 1] - bin_points[i])
        for j in range(bin_points[i + 1], bin_points[i + 2]):
            filterbank[i, j] = (bin_points[i + 2] - j) / (bin_points[i + 2] - bin_points[i + 1])

    return filterbank


def extract_mfcc(audio_data: np.ndarray, sample_rate: int = 16000,
                 num_mfcc: int = 13, frame_size: int = 512,
                 hop_size: int = 256) -> np.ndarray:
    """
    Extract MFCC features from audio.

    Args:
        audio_data: numpy array of audio samples
        sample_rate: Sample rate in Hz
        num_mfcc: Number of MFCC coefficients to extract
        frame_size: FFT frame size
        hop_size: Hop size between frames

    Returns:
        2D array of MFCC features (num_frames x num_mfcc)
    """
    # Ensure audio is 1D
    if len(audio_data.shape) > 1:
        audio_data = audio_data.flatten()

    # Frame the audio
    num_frames = 1 + (len(audio_data) - frame_size) // hop_size
    if num_frames < 1:
        # Pad short audio
        audio_data = np.pad(audio_data, (0, frame_size - len(audio_data)))
        num_frames = 1

    frames = np.zeros((num_frames, frame_size))
    for i in range(num_frames):
        start = i * hop_size
        frames[i] = audio_data[start:start + frame_size]

    # Apply Hamming window
    window = np.hamming(frame_size)
    frames = frames * window

    # FFT and power spectrum
    fft_result = fft(frames, axis=1)
    power_spectrum = np.abs(fft_result[:, :frame_size // 2 + 1]) ** 2

    # Mel filterbank
    mel_filterbank = _create_mel_filterbank(26, frame_size, sample_rate)
    mel_spectrum = np.dot(power_spectrum, mel_filterbank.T)
    mel_spectrum = np.where(mel_spectrum == 0, np.finfo(float).eps, mel_spectrum)
    mel_spectrum = np.log(mel_spectrum)

    # DCT to get MFCCs
    num_filters = mel_spectrum.shape[1]
    dct_matrix = np.zeros((num_mfcc, num_filters))
    for i in range(num_mfcc):
        for j in range(num_filters):
            dct_matrix[i, j] = np.cos(np.pi * i * (j + 0.5) / num_filters)

    mfcc = np.dot(mel_spectrum, dct_matrix.T)

    return mfcc


def extract_spectral_features(audio_data: np.ndarray,
                              sample_rate: int = 16000) -> tuple[float, float]:
    """
    Extract spectral centroid and rolloff.

    Args:
        audio_data: numpy array of audio samples
        sample_rate: Sample rate in Hz

    Returns:
        Tuple of (spectral_centroid, spectral_rolloff)
    """
    # Compute magnitude spectrum
    fft_result = np.abs(fft(audio_data))
    fft_result = fft_result[:len(fft_result) // 2]

    # Frequency bins
    freqs = np.linspace(0, sample_rate / 2, len(fft_result))

    # Spectral centroid
    if np.sum(fft_result) > 0:
        centroid = np.sum(freqs * fft_result) / np.sum(fft_result)
    else:
        centroid = 0.0

    # Spectral rolloff (85% of spectral energy)
    cumsum = np.cumsum(fft_result)
    if cumsum[-1] > 0:
        rolloff_idx = np.searchsorted(cumsum, 0.85 * cumsum[-1])
        rolloff = freqs[min(rolloff_idx, len(freqs) - 1)]
    else:
        rolloff = 0.0

    return float(centroid), float(rolloff)


def create_voice_profile(audio_data: np.ndarray,
                         sample_rate: int = 16000) -> VoiceProfile:
    """
    Create a voice profile from audio samples.

    Args:
        audio_data: numpy array of audio samples (should be several seconds)
        sample_rate: Sample rate in Hz

    Returns:
        VoiceProfile object
    """
    # Extract MFCC features
    mfcc = extract_mfcc(audio_data, sample_rate)
    mfcc_mean = np.mean(mfcc, axis=0)
    mfcc_std = np.std(mfcc, axis=0)

    # Extract spectral features
    centroid, rolloff = extract_spectral_features(audio_data, sample_rate)

    return VoiceProfile(
        mfcc_mean=mfcc_mean,
        mfcc_std=mfcc_std,
        spectral_centroid=centroid,
        spectral_rolloff=rolloff
    )


def match_voice(audio_segment: np.ndarray, profile: VoiceProfile,
                sample_rate: int = 16000, threshold: float = 0.6) -> tuple[bool, float]:
    """
    Check if an audio segment matches a voice profile.

    Args:
        audio_segment: numpy array of audio samples
        profile: VoiceProfile to match against
        sample_rate: Sample rate in Hz
        threshold: Similarity threshold (0-1) for positive match

    Returns:
        Tuple of (is_match, confidence_score)
    """
    # Skip very quiet segments
    rms = np.sqrt(np.mean(audio_segment ** 2))
    if rms < 0.01:
        return False, 0.0

    # Extract features from segment
    mfcc = extract_mfcc(audio_segment, sample_rate)
    segment_mfcc_mean = np.mean(mfcc, axis=0)

    centroid, rolloff = extract_spectral_features(audio_segment, sample_rate)

    # Compare MFCC (using cosine similarity)
    norm_profile = np.linalg.norm(profile.mfcc_mean)
    norm_segment = np.linalg.norm(segment_mfcc_mean)

    if norm_profile > 0 and norm_segment > 0:
        mfcc_similarity = np.dot(profile.mfcc_mean, segment_mfcc_mean) / (norm_profile * norm_segment)
    else:
        mfcc_similarity = 0.0

    # Compare spectral features (normalized difference)
    if profile.spectral_centroid > 0:
        centroid_diff = abs(centroid - profile.spectral_centroid) / profile.spectral_centroid
        centroid_similarity = max(0, 1 - centroid_diff)
    else:
        centroid_similarity = 0.5

    if profile.spectral_rolloff > 0:
        rolloff_diff = abs(rolloff - profile.spectral_rolloff) / profile.spectral_rolloff
        rolloff_similarity = max(0, 1 - rolloff_diff)
    else:
        rolloff_similarity = 0.5

    # Combined similarity score (weighted average)
    similarity = 0.6 * mfcc_similarity + 0.2 * centroid_similarity + 0.2 * rolloff_similarity

    # Clamp to [0, 1]
    similarity = float(np.clip(similarity, 0, 1))

    return similarity >= threshold, similarity


def save_profile(profile: VoiceProfile, filepath: str) -> None:
    """Save voice profile to JSON file."""
    with open(filepath, 'w') as f:
        json.dump(profile.to_dict(), f)


def load_profile(filepath: str) -> VoiceProfile:
    """Load voice profile from JSON file."""
    with open(filepath, 'r') as f:
        data = json.load(f)
    return VoiceProfile.from_dict(data)
