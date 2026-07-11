"""Line-by-line Python mirror of the Swift VoiceCore implementation.

Used to verify the Swift port's algorithms against the checked-in fixtures
(no Swift toolchain in this environment). Every function transliterates the
corresponding Swift code, including the SplitMix64 PRNG, so if this passes,
the Swift logic is algorithmically correct.
"""

import json
import math
from pathlib import Path

FIXTURES = Path(__file__).resolve().parents[1] / "VoiceCore/Tests/VoiceCoreTests/Fixtures"

MASK = (1 << 64) - 1


class SplitMix64:
    def __init__(self, seed):
        self.state = seed & MASK

    def next_u64(self):
        self.state = (self.state + 0x9E3779B97F4A7C15) & MASK
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK
        return (z ^ (z >> 31)) & MASK

    def next_double(self):
        return (self.next_u64() >> 11) * (2.0 ** -53)

    def next_int(self, upper):
        return self.next_u64() % upper


# --- FFT.swift ---
def fft_forward(real, imag):
    n = len(real)
    assert n > 0 and (n & (n - 1)) == 0
    j = 0
    for i in range(n - 1):
        if i < j:
            real[i], real[j] = real[j], real[i]
            imag[i], imag[j] = imag[j], imag[i]
        mask = n >> 1
        while j & mask:
            j &= ~mask
            mask >>= 1
        j |= mask
    length = 2
    while length <= n:
        half = length // 2
        angle_step = -2.0 * math.pi / length
        for start in range(0, n, length):
            for k in range(half):
                angle = angle_step * k
                wr, wi = math.cos(angle), math.sin(angle)
                e, o = start + k, start + k + half
                tr = wr * real[o] - wi * imag[o]
                ti = wr * imag[o] + wi * real[o]
                real[o] = real[e] - tr
                imag[o] = imag[e] - ti
                real[e] += tr
                imag[e] += ti
        length <<= 1


# --- MFCC.swift ---
def hz_to_mel(hz):
    return 2595 * math.log10(1 + hz / 700)


def mel_to_hz(mel):
    return 700 * (10 ** (mel / 2595) - 1)


def hamming_window(size):
    return [0.54 - 0.46 * math.cos(2 * math.pi * n / (size - 1)) for n in range(size)]


def mel_filterbank(num_filters, fft_size, sample_rate):
    high_mel = hz_to_mel(sample_rate / 2)
    mel_points = [high_mel * i / (num_filters + 1) for i in range(num_filters + 2)]
    bin_points = [int(math.floor((fft_size + 1) * mel_to_hz(m) / sample_rate)) for m in mel_points]
    fb = [[0.0] * (fft_size // 2 + 1) for _ in range(num_filters)]
    for i in range(num_filters):
        left, center, right = bin_points[i], bin_points[i + 1], bin_points[i + 2]
        for j in range(left, center):
            fb[i][j] = (j - left) / (center - left)
        for j in range(center, right):
            fb[i][j] = (right - j) / (right - center)
    return fb


def dct_matrix(num_mfcc, num_filters):
    return [
        [math.cos(math.pi * i * (j + 0.5) / num_filters) for j in range(num_filters)]
        for i in range(num_mfcc)
    ]


def mfcc_extract(audio, sample_rate=16000, num_mfcc=13, frame_size=512, hop_size=256):
    samples = list(audio)
    if len(samples) >= frame_size:
        num_frames = 1 + (len(samples) - frame_size) // hop_size
    else:
        samples += [0.0] * (frame_size - len(samples))
        num_frames = 1
    window = hamming_window(frame_size)
    fb = mel_filterbank(26, frame_size, sample_rate)
    dct = dct_matrix(num_mfcc, 26)
    num_bins = frame_size // 2 + 1

    out = []
    for f in range(num_frames):
        start = f * hop_size
        real = [samples[start + i] * window[i] for i in range(frame_size)]
        imag = [0.0] * frame_size
        fft_forward(real, imag)
        power = [real[k] * real[k] + imag[k] * imag[k] for k in range(num_bins)]
        mel_log = []
        for row in fb:
            s = sum(power[k] * row[k] for k in range(num_bins))
            mel_log.append(math.log(1e-10 if s == 0 else s))
        out.append([sum(mel_log[j] * dct[i][j] for j in range(26)) for i in range(num_mfcc)])
    return out


# --- GaussianMixture.swift ---
def log_sum_exp(values):
    m = max(values)
    if m == -math.inf:
        return -math.inf
    return m + math.log(sum(math.exp(v - m) for v in values))


def score_samples(weights, means, prec_chol, X):
    k = len(weights)
    log_w = [math.log(w) if w > 0 else -math.inf for w in weights]
    log_det = [sum(math.log(p) for p in prec_chol[c]) for c in range(k)]
    scores = []
    for x in X:
        d = len(x)
        weighted = []
        for c in range(k):
            maha = sum(((x[j] - means[c][j]) * prec_chol[c][j]) ** 2 for j in range(d))
            weighted.append(-0.5 * (d * math.log(2 * math.pi) + maha) + log_det[c] + log_w[c])
        scores.append(log_sum_exp(weighted))
    return scores


REG_COVAR = 1e-6
TOL = 1e-3
MAX_ITER = 100
ULP = 2.220446049250313e-16


def sq_dist(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b))


def kmeans(X, k, rng):
    n, d = len(X), len(X[0])
    centers = [list(X[rng.next_int(n)])]
    min_d = [sq_dist(x, centers[0]) for x in X]
    while len(centers) < k:
        total = sum(min_d)
        if total > 0:
            target = rng.next_double() * total
            cum = 0.0
            idx = 0
            for i in range(n):
                cum += min_d[i]
                if cum >= target:
                    idx = i
                    break
        else:
            idx = rng.next_int(n)
        c = list(X[idx])
        centers.append(c)
        for i in range(n):
            min_d[i] = min(min_d[i], sq_dist(X[i], c))
    labels = [0] * n
    for _ in range(30):
        changed = False
        for i in range(n):
            best, bd = 0, math.inf
            for c in range(k):
                dist = sq_dist(X[i], centers[c])
                if dist < bd:
                    bd, best = dist, c
            if labels[i] != best:
                labels[i] = best
                changed = True
        if not changed:
            break
        sums = [[0.0] * d for _ in range(k)]
        counts = [0] * k
        for i in range(n):
            counts[labels[i]] += 1
            for j in range(d):
                sums[labels[i]][j] += X[i][j]
        for c in range(k):
            if counts[c] > 0:
                centers[c] = [s / counts[c] for s in sums[c]]
    return labels


def estimate_parameters(X, resp):
    n, d, k = len(X), len(X[0]), len(resp[0])
    counts = [0.0] * k
    for i in range(n):
        for c in range(k):
            counts[c] += resp[i][c]
    safe = [max(c, 10 * ULP) for c in counts]
    means = [[0.0] * d for _ in range(k)]
    for i in range(n):
        for c in range(k):
            if resp[i][c] > 0:
                r = resp[i][c]
                for j in range(d):
                    means[c][j] += r * X[i][j]
    for c in range(k):
        for j in range(d):
            means[c][j] /= safe[c]
    cov = [[0.0] * d for _ in range(k)]
    for i in range(n):
        for c in range(k):
            if resp[i][c] > 0:
                r = resp[i][c]
                for j in range(d):
                    diff = X[i][j] - means[c][j]
                    cov[c][j] += r * diff * diff
    for c in range(k):
        for j in range(d):
            cov[c][j] = cov[c][j] / safe[c] + REG_COVAR
    weights = [c / n for c in counts]
    return weights, means, cov


def fit_single(X, k, rng):
    n, d = len(X), len(X[0])
    labels = kmeans(X, k, rng)
    resp = [[0.0] * k for _ in range(n)]
    for i in range(n):
        resp[i][labels[i]] = 1.0
    weights, means, cov = estimate_parameters(X, resp)
    lower = -math.inf
    for _ in range(MAX_ITER):
        prec = [[1 / math.sqrt(max(v, 1e-300)) for v in row] for row in cov]
        log_w = [math.log(w) if w > 0 else -math.inf for w in weights]
        log_det = [sum(math.log(p) for p in prec[c]) for c in range(k)]
        total = 0.0
        for i in range(n):
            weighted = []
            for c in range(k):
                maha = sum(((X[i][j] - means[c][j]) * prec[c][j]) ** 2 for j in range(d))
                weighted.append(-0.5 * (d * math.log(2 * math.pi) + maha) + log_det[c] + log_w[c])
            norm = log_sum_exp(weighted)
            total += norm
            for c in range(k):
                resp[i][c] = math.exp(weighted[c] - norm)
        new_lower = total / n
        weights, means, cov = estimate_parameters(X, resp)
        if abs(new_lower - lower) < TOL:
            lower = new_lower
            break
        lower = new_lower
    prec = [[1 / math.sqrt(max(v, 1e-300)) for v in row] for row in cov]
    return (weights, means, cov, prec), lower


def gmm_fit(X, num_components, num_inits=3, seed=42):
    k = min(num_components, len(X))
    rng = SplitMix64(seed)
    best, best_lb = None, -math.inf
    for _ in range(max(1, num_inits)):
        model, lb = fit_single(X, k, rng)
        if lb > best_lb:
            best_lb, best = lb, model
    return best


# --- VoiceMatcher.swift ---
def rms(audio):
    return math.sqrt(sum(a * a for a in audio) / len(audio)) if audio else 0.0


def match(audio, profile):
    if rms(audio) < 0.01:
        return False, 0.0
    feats = mfcc_extract(audio, 16000, num_mfcc=20)
    if len(feats) < 5:
        return False, 0.0
    scores = score_samples(profile["weights"], profile["means"], profile["precisions_cholesky"], feats)
    avg = sum(scores) / len(scores)
    margin = avg - profile["threshold_score"]
    try:
        conf = 1 / (1 + math.exp(-0.5 * margin))
    except OverflowError:
        conf = 0.0
    return margin > 0, conf


# ---------------- verification ----------------
def check_close(actual, expected, atol, rtol=1e-6, label=""):
    assert len(actual) == len(expected), f"{label}: length {len(actual)} != {len(expected)}"
    worst = 0.0
    for a, e in zip(actual, expected):
        tol = max(atol, rtol * abs(e))
        err = abs(a - e)
        worst = max(worst, err - tol)
        assert err <= tol, f"{label}: |{a} - {e}| = {err} > {tol}"
    return worst


mfcc_fx = json.loads((FIXTURES / "mfcc_parity.json").read_text())
gmm_fx = json.loads((FIXTURES / "gmm_parity.json").read_text())
train_fx = json.loads((FIXTURES / "training_features.json").read_text())

# 1. MFCC parity
got = mfcc_extract(mfcc_fx["audio"], mfcc_fx["sample_rate"], num_mfcc=20)
exp = mfcc_fx["expected_mfcc"]
assert len(got) == len(exp), f"frames {len(got)} vs {len(exp)}"
max_err = 0.0
for g, e in zip(got, exp):
    check_close(g, e, atol=1e-4, label="mfcc")
    max_err = max(max_err, max(abs(a - b) for a, b in zip(g, e)))
print(f"1. MFCC parity OK ({len(got)} frames, max abs err {max_err:.2e})")

# 2. GMM score parity
profile = gmm_fx["profile"]
user_feats = got
other_feats = mfcc_extract(gmm_fx["other_audio"], 16000, num_mfcc=20)
su = score_samples(profile["weights"], profile["means"], profile["precisions_cholesky"], user_feats)
so = score_samples(profile["weights"], profile["means"], profile["precisions_cholesky"], other_feats)
check_close(su, gmm_fx["expected_scores_user"], atol=1e-3, label="user scores")
check_close(so, gmm_fx["expected_scores_other"], atol=1e-3, rtol=1e-5, label="other scores")
print(f"2. GMM score parity OK (user avg {sum(su)/len(su):.4f}, other avg {sum(so)/len(so):.4f})")

# 3. Match decisions
mu, cu = match(mfcc_fx["audio"], profile)
mo, co = match(gmm_fx["other_audio"], profile)
assert mu == gmm_fx["match_user"]["is_match"] and abs(cu - gmm_fx["match_user"]["confidence"]) < 1e-4
assert mo == gmm_fx["match_other"]["is_match"] and abs(co - gmm_fx["match_other"]["confidence"]) < 1e-4
print(f"3. Match decisions OK (user {mu}/{cu:.4f}, other {mo}/{co:.4f})")

# 4. Swift-style training discrimination (the TrainingTests assertions)
X = train_fx["train_features"]
k = max(1, min(16, len(X) // 20))
w, m, cv, pc = gmm_fit(X, k)
train_scores = score_samples(w, m, pc, X)
avg = sum(train_scores) / len(train_scores)
var = sum((s - avg) ** 2 for s in train_scores) / len(train_scores)
threshold = avg - 1.5 * math.sqrt(var)
u = score_samples(w, m, pc, train_fx["eval_user_features"])
o = score_samples(w, m, pc, train_fx["eval_other_features"])
ua, oa = sum(u) / len(u), sum(o) / len(o)
assert ua > threshold, f"user {ua} !> threshold {threshold}"
assert oa < threshold, f"other {oa} !< threshold {threshold}"
assert ua > oa + 50
print(f"4. Swift-trainer discrimination OK (threshold {threshold:.2f}, user {ua:.2f}, other {oa:.2f}; python threshold {train_fx['python_threshold']:.2f})")

# 5. Determinism
w2, m2, _, _ = gmm_fit(X[:200], 4, seed=42)
w3, m3, _, _ = gmm_fit(X[:200], 4, seed=42)
assert w2 == w3 and m2 == m3
assert abs(sum(w) - 1.0) < 1e-9
print("5. Determinism + weight normalization OK")

print("\nALL CHECKS PASSED")
