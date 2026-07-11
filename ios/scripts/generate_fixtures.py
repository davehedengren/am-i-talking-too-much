"""Generate parity fixtures for the Swift VoiceCore port.

Runs the repo's actual Python implementation (voice_matcher.py) on
deterministic synthetic "voice" audio and records expected outputs so the
Swift unit tests can verify numerical parity.
"""

import json
import sys
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))

from voice_matcher import (  # noqa: E402
    create_voice_profile, extract_mfcc, match_voice,
)

FIXTURES = REPO / "ios/VoiceCore/Tests/VoiceCoreTests/Fixtures"
FIXTURES.mkdir(parents=True, exist_ok=True)

SR = 16000


def synth_voice(rng, duration, f0, formants, tilt):
    """Synthesize a crude voiced signal: harmonic stack shaped by formant
    resonances, with vibrato, syllabic amplitude modulation, and noise."""
    n = int(duration * SR)
    t = np.arange(n) / SR
    f0_t = f0 * (1 + 0.015 * np.sin(2 * np.pi * 5.2 * t))
    phase = 2 * np.pi * np.cumsum(f0_t) / SR
    sig = np.zeros(n)
    h = 1
    while f0 * h < SR / 2 - 300:
        fh = f0 * h
        gain = sum(np.exp(-((fh - fc) ** 2) / (2 * bw ** 2)) for fc, bw in formants)
        gain += tilt / h
        sig += gain * np.sin(h * phase + rng.uniform(0, 2 * np.pi))
        h += 1
    env = 0.55 + 0.45 * np.sin(2 * np.pi * 3.1 * t + rng.uniform(0, 6))
    sig = sig * env + 0.01 * rng.standard_normal(n)
    sig = 0.1 * sig / np.max(np.abs(sig))
    return sig


rng = np.random.default_rng(42)

VOICE_A = dict(f0=118.0, formants=[(500, 80), (1500, 120), (2500, 150)], tilt=0.5)
VOICE_B = dict(f0=235.0, formants=[(850, 100), (2200, 150), (3300, 200)], tilt=0.2)

# Round stored audio and compute every expected value from the ROUNDED
# audio, so Swift consumes byte-identical inputs.
a_train = np.round(synth_voice(rng, 10.0, **VOICE_A), 6)
a_eval = np.round(synth_voice(rng, 1.0, **VOICE_A), 6)
b_eval = np.round(synth_voice(rng, 1.0, **VOICE_B), 6)

profile = create_voice_profile(a_train, SR)

mfcc_a_eval = extract_mfcc(a_eval, SR, num_mfcc=20)
mfcc_b_eval = extract_mfcc(b_eval, SR, num_mfcc=20)
mfcc_a_train = extract_mfcc(a_train, SR, num_mfcc=20)

scores_user = profile.gmm.score_samples(mfcc_a_eval)
scores_other = profile.gmm.score_samples(mfcc_b_eval)

is_user, conf_user = match_voice(a_eval, profile, SR)
is_other, conf_other = match_voice(b_eval, profile, SR)

print(f"threshold={profile.threshold_score:.4f}")
print(f"user:  avg={scores_user.mean():.4f} match={is_user} conf={conf_user:.4f}")
print(f"other: avg={scores_other.mean():.4f} match={is_other} conf={conf_other:.4f}")
assert is_user and not is_other, "synthetic voices are not discriminable; tune synth params"

with open(FIXTURES / "mfcc_parity.json", "w") as f:
    json.dump({
        "sample_rate": SR,
        "audio": a_eval.tolist(),
        "expected_mfcc": mfcc_a_eval.tolist(),
    }, f)

with open(FIXTURES / "gmm_parity.json", "w") as f:
    json.dump({
        "profile": profile.to_dict(),
        "other_audio": b_eval.tolist(),
        "expected_scores_user": scores_user.tolist(),
        "expected_scores_other": scores_other.tolist(),
        "match_user": {"is_match": bool(is_user), "confidence": float(conf_user)},
        "match_other": {"is_match": bool(is_other), "confidence": float(conf_other)},
    }, f)

with open(FIXTURES / "training_features.json", "w") as f:
    json.dump({
        "train_features": np.round(mfcc_a_train, 6).tolist(),
        "eval_user_features": np.round(mfcc_a_eval, 6).tolist(),
        "eval_other_features": np.round(mfcc_b_eval, 6).tolist(),
        "python_threshold": float(profile.threshold_score),
    }, f)

for p in sorted(FIXTURES.glob("*.json")):
    print(f"{p.name}: {p.stat().st_size / 1024:.0f} KB")
