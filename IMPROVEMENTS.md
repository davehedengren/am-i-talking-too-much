# iOS App — Improvement Backlog

Prioritized notes from the 2026-07 review. Check items off as they land; add
findings from field tests at the bottom.

## 0. Active investigation

- [ ] **Annotated eval harness (do before any further matcher/gate tuning).**
      Recording side SHIPPED: Settings → Diagnostics → **Ground Truth
      Recorder** captures raw pipeline audio (exact tracker path: 16 kHz mono,
      `.measurement`) with live Me/Others/Quiet/Unsure label taps, timestamped
      on the audio clock. Sessions save to `Documents/GroundTruth/<timestamp>/`
      (`audio.wav` + `labels.json`), shareable from the app and visible in
      Files/Finder (`UIFileSharingEnabled`).
      Replay harness SHIPPED too: `tools/eval/run.sh <audio.wav> <labels.json>`
      compiles the real pipeline sources (VoiceCore + NoiseFloor/VoicedTrim +
      neural embedder) into a macOS binary, enrolls from the first long "me"
      segment (excluded from scoring), replays every chunk, and reports score
      distributions, confusion matrices, threshold sweeps (balanced-accuracy
      and share-honest), and median-3 smoothing. Session data stays local
      (`tools/eval/data/` is gitignored — raw conversation audio).
- [ ] **Speaker-verification embedding (ECAPA-TDNN / x-vector via Core ML).**
      First ground-truth session (2026-07-20) shows AudioFeaturePrint can't
      fully separate speakers in the same room: me-sims 0.74–0.91 vs
      others-sims 0.55–0.90 overlap heavily; best achievable balanced accuracy
      ~82%, others-rejection only ~64% at full recall. Threshold tuning cannot
      fix an overlapping distribution — a model trained specifically for
      speaker verification is the measured next step. Validate via the harness
      before shipping.

- [ ] **"You spoke" stuck at 0 s with neural matching** (found on-device 2026-07-18).
      Diagnostics landed in PR #7: the Debug Log now prints the raw decision per
      speech chunk — `sim 0.912 thr 0.894` (neural) or `ll -18.3 thr -20.1`
      (classic) — plus `EMBED FAILED` / `dim mismatch` / gate markers, and the
      tracking screen shows which matcher is live.
      **Next:** run a short session, read the `sim`/`thr` lines, then either
      (a) tune `NeuralVoiceEnroller.marginFloor` (currently 0.08),
      (b) fix the embedding path if `EMBED FAILED` appears, or
      (c) conclude AudioFeaturePrint is not speaker-discriminative enough
      (it's trained for sound classes, not speakers) and switch to a proper
      speaker-embedding Core ML model (ECAPA-TDNN / x-vector).

## 1. Correctness / UX

- [x] **Tracking silently dies on navigation** → `ensureMonitoring(matcher:isNeural:)`
      is idempotent: History pushes are a no-op mid-session, the neural toggle
      swaps the matcher without resetting totals, and `.onDisappear` only stops
      an idle meter (background audio mode keeps the mic alive while tracking).
- [x] **Live "it's working" indicator while tracking** → audio-reactive level
      meter runs during tracking (`LiveLevel` isolated in its own observable so
      ~10 Hz updates re-render only the meter subview), plus a per-chunk chip:
      You (green) / Others (blue) / quiet (gray).
- [x] **Adaptive speech gate** (`NoiseFloor.swift`): rolling ambient-noise
      floor replaces the fixed `speechGateRMS = 0.005`, which read real-device
      speech (no AGC in `.measurement` mode) as silence and would have counted
      party music as speech. Also removed the matcher-side `minimumRMS = 0.01`
      second gate that created a dead band (0.005–0.01) where quiet speech
      could only ever count as "others". Constants (`speechFactor` 2.5, floor
      creep 5%/chunk) are first-cut — tune from the `Gate:` values now in the
      debug log. Follow-up option: SoundAnalysis speech classifier.
- [ ] **Crash/force-quit loses the whole session.** `makeDraft()` only runs on
      Stop. Autosave a recovery draft every few minutes; offer to restore on
      next launch.
- [ ] **Temporal smoothing of chunk decisions.** MEASURED 2026-07-20 session:
      median-of-3 did NOT help (balanced accuracy dropped slightly on both
      matchers) — real conversational turns are often 1–4 s, shorter than the
      smoothing window, so it blurs turn boundaries more than it fixes flips.
      Revisit only with more labeled data and longer-turn sessions.

## 2. Performance / battery

- [ ] **Temp WAV written to disk every 2 s** during neural tracking
      (`NeuralVoiceEmbedder.windowEmbeddings`). Feed `AVAudioPCMBuffer`s in
      memory via `AnyTemporalSequence` instead of `AudioReader.read(contentsOf:)`.
- [ ] **Live chart grows unbounded.** `percentageHistory` gains a point per
      speech chunk and the whole `Chart` re-renders every 2 s; hours-long
      sessions accumulate thousands of marks. Decimate or window the live view
      (saved sessions already bucket via `Session.buildBuckets`).

## 3. Robustness

- [ ] **`HistoryStore.persist()` swallows write errors** (`try?`). Surface a
      one-time warning (e.g. disk full) instead of silently dropping sessions.
- [ ] **Neural enrollment failure is quiet.** Settings now shows a warning
      (PR #7), but calibration itself could tell the user "neural profile could
      not be created" at save time.

## 4. Testing / structure

- [ ] **App target has zero tests.** `Session.buildBuckets`, enroller math, and
      `SessionStore` have all had bugs caught only by ad-hoc `swiftc` runs.
      Move pure logic into VoiceCore (or a new small `AppCore` SwiftPM package)
      so `swift test` covers it headlessly; or add an app unit-test target to
      `project.yml`.

## 5. Product ideas

- [x] **On-phone haptic nudge** (first cut) — warning haptic when your share
      is over 55% with ≥60 s of speech accumulated, at most every 2 min
      (`TrackerViewModel.nudgeIfDominating`). Foreground only; constants
      tunable. Later: sustained-window logic, a setting to disable, Watch tap.
- [ ] **History aggregates/trends** — average share across events, trend over
      time, best/worst events. Small header section on `HistoryListView`.
- [ ] **Edit session title after save**; currently title is only set in the
      save sheet.
- [ ] **Export/share a session** (image of the chart or CSV).
- [ ] **In-app About screen** mirroring the "why letting others speak matters"
      research section of `HOW_IT_WORKS.md` (Settings → About).
- [ ] **Watch companion (later)** — glanceable live share + wrist haptic nudge
      via WatchConnectivity; phone stays the microphone and brain. (Watch as
      the mic was investigated and rejected: no long-running background audio
      on watchOS, battery unrealistic.)

## 6. Housekeeping

- [x] Privacy manifest declares the UserDefaults required-reason API (CA92.1) — PR #7.
- [x] Debug log labeled every score "gmm" regardless of matcher — PR #7.
- [x] Active matcher visible while tracking ("Listening (Neural)…") — PR #7.
- [ ] Stale local branches (`feat/ios-event-history`, `cleanup/code-review-fixes`,
      `fix/speaker-embedding-auth-error`) and old open PR #2 — prune/close.
- [ ] `CLAUDE.md` / `ios/README.md` don't yet describe the neural matcher,
      event history, or the A/B toggle — update docs.

## Field-test findings (append here)

- 2026-07-21: **first ground-truth evaluation** (114 s session, 2 speakers,
  42 scored chunks, true share 21%). Neural clearly beats GMM: balanced 80%
  vs 57% at calibrated thresholds; GMM me/others log-likelihoods are nearly
  indistinguishable (medians −65.2 vs −67.3) while neural separates partially
  (0.877 vs 0.695) with an overlap zone. Neural at calibrated threshold:
  100% me-recall but only 61% others-rejection → predicted share 52% vs true
  21% (overestimates in groups). The calibrated neural threshold is within
  0.01 of the balanced-accuracy optimum, so tuning isn't the bottleneck — the
  embedding is (see speaker-verification item). A share-honest threshold
  (0.86) exists but overfits one session and sits above the enrollment
  self-similarity mean; not shipped. Median-3 smoothing: no gain.

- 2026-07-18: location resolved as "unknown" → fixed (auth race, PR #5).
- 2026-07-18: "You spoke" 0 s after neural merge → diagnostics in PR #7, root
  cause TBD (see section 0).
- 2026-07-20: speech read as "(silence)" on device while calibration meter
  moved fine → fixed thresholds didn't fit real-device levels (`.measurement`
  mode has no AGC). Adaptive noise-floor gate + dead-band removal shipped;
  watch `RMS`/`Gate` debug lines to tune `NoiseFloor` constants. Likely also
  the root cause of (or a contributor to) the 0 s issue above.
- 2026-07-20: solo test showed ~80% of own speech attributed as "You" on BOTH
  matchers — identical rates pointed upstream of the matchers: clock-cut 2 s
  chunks straddling pauses were scored whole, and the silent tail diluted the
  score below threshold. Fix: `VoicedTrim` scores only the voiced frames
  (≥1.05 s required, else the chunk is dropped as too ambiguous to attribute).
  `Voiced:` % now in the debug log. Deliberately did NOT loosen thresholds —
  false-accept side is unmeasured until the group test.
- 2026-07-20 (later): **splice-scoring REGRESSED solo accuracy to ~50–60%** —
  reverted to whole-chunk scoring. Two mechanisms: (1) `NoiseFloor` v1 crept
  +5%/chunk with no quiet chunks to pull it down, so a sustained monologue
  ratcheted the gate to ~0.023 by minute two (above much speech) — replaced
  with a windowed minimum over each chunk's quietest 100 ms frame, which
  inter-word gaps anchor even mid-monologue; (2) splicing voiced frames
  corrupts MFCC frames at the seams and mismatches profiles trained on
  untrimmed calibration audio. Lesson recorded: no more blind pipeline tuning
  — build the annotated eval harness first (section 0).
