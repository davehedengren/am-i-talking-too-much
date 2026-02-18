"""Voice feature extraction and matching for speaker identification."""

import numpy as np
from scipy.fft import fft
from scipy.signal import spectrogram
from scipy.special import expit
from typing import Optional, Tuple
import json
from sklearn.mixture import GaussianMixture


class VoiceProfile:
    """Represents a voice profile with GMM parameters."""

    def __init__(self, gmm: GaussianMixture, threshold_score: float):
        self.gmm = gmm
        self.threshold_score = threshold_score

    def to_dict(self) -> dict:
        """Convert profile to dictionary for serialization."""
        return {
            'weights': self.gmm.weights_.tolist(),
            'means': self.gmm.means_.tolist(),
            'covariances': self.gmm.covariances_.tolist(),
            'precisions_cholesky': self.gmm.precisions_cholesky_.tolist(),
            'threshold_score': self.threshold_score
        }

    @classmethod
    def from_dict(cls, data: dict) -> 'VoiceProfile':
        """Create profile from dictionary."""
        gmm = GaussianMixture(n_components=len(data['weights']), covariance_type='diag')
        gmm.weights_ = np.array(data['weights'])
        gmm.means_ = np.array(data['means'])
        gmm.covariances_ = np.array(data['covariances'])
        gmm.precisions_cholesky_ = np.array(data['precisions_cholesky'])
        # For diag, precisions is 1/covariances (guard against zero)
        gmm.precisions_ = 1.0 / np.maximum(gmm.covariances_, 1e-10)
        return cls(gmm=gmm, threshold_score=data.get('threshold_score', -20.0))


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
    mel_spectrum = np.where(mel_spectrum == 0, 1e-10, mel_spectrum)
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
    Create a voice profile from audio samples using GMM.

    Args:
        audio_data: numpy array of audio samples (should be several seconds)
        sample_rate: Sample rate in Hz

    Returns:
        VoiceProfile object
    """
    # Extract MFCC features
    # MFCCs are (num_frames, num_coefficients)
    mfcc = extract_mfcc(audio_data, sample_rate, num_mfcc=20)
    
    # Train GMM with Diagonal Covariance
    # 'diag' has far fewer parameters than 'full', preventing overfitting on short clips
    # We want at least 20 frames per component to estimate mean/var reliably
    n_frames = mfcc.shape[0]
    max_components = n_frames // 20
    n_components = min(16, max_components)
    if n_components < 1:
        n_components = 1
        
    gmm = GaussianMixture(n_components=n_components, covariance_type='diag', 
                          random_state=42, n_init=3)
    gmm.fit(mfcc)
    
    # Calculate baseline score (average log likelihood) on training data
    scores = gmm.score_samples(mfcc)
    avg_score = np.mean(scores)
    std_score = np.std(scores)

    # Set threshold using standard deviation: short test chunks (2-3s) have
    # higher variance than the training window, so a fixed margin is unreliable.
    # Using 1.5 * std accommodates natural score variance while still
    # rejecting genuinely different speakers.
    threshold_score = avg_score - 1.5 * std_score

    return VoiceProfile(gmm=gmm, threshold_score=threshold_score)


def match_voice(audio_segment: np.ndarray, profile: VoiceProfile,
                sample_rate: int = 16000, threshold_confidence: float = 0.5) -> Tuple[bool, float]:
    """
    Check if an audio segment matches a voice profile using GMM log-likelihood.

    Args:
        audio_segment: numpy array of audio samples
        profile: VoiceProfile to match against
        sample_rate: Sample rate in Hz
        threshold_confidence: (Unused in GMM decision logic directly, but kept for interface compatibility)

    Returns:
        Tuple of (is_match, confidence_score)
    """
    # Skip very quiet segments (threshold low enough for Bluetooth mics)
    rms = np.sqrt(np.mean(audio_segment ** 2))
    if rms < 0.0005:
        return False, 0.0

    # Extract features from segment
    mfcc = extract_mfcc(audio_segment, sample_rate, num_mfcc=20)
    
    if mfcc.shape[0] < 5:
        # Not enough frames to judge
        return False, 0.0

    # Compute log-likelihood of the segment under the GMM
    scores = profile.gmm.score_samples(mfcc)
    avg_score = np.mean(scores)
    
    # Distance from threshold
    # if avg_score > profile.threshold_score, it's a match
    # We want to map this to a 0-1 confidence
    # Let's say:
    #   score == threshold -> 0.5
    #   score == threshold + 5 -> 0.9
    #   score == threshold - 5 -> 0.1
    
    diff = avg_score - profile.threshold_score
    
    # Sigmoid function centered at 0 (which represents the threshold)
    # Scale factor 0.5 means a difference of 2 units drives it significantly
    confidence = float(expit(0.5 * diff))
    
    is_match = diff > 0
    
    return is_match, float(confidence)


def save_profile(profile: VoiceProfile, filepath: str) -> None:
    """Save voice profile to JSON file."""
    with open(filepath, 'w') as f:
        json.dump(profile.to_dict(), f)


def load_profile(filepath: str) -> VoiceProfile:
    """Load voice profile from JSON file."""
    with open(filepath, 'r') as f:
        data = json.load(f)
    return VoiceProfile.from_dict(data)
