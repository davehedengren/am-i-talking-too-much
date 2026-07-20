# iOS App — Improvement Backlog

Prioritized notes from the 2026-07 review. Check items off as they land; add
findings from field tests at the bottom.

## 0. Active investigation

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

- 2026-07-18: location resolved as "unknown" → fixed (auth race, PR #5).
- 2026-07-18: "You spoke" 0 s after neural merge → diagnostics in PR #7, root
  cause TBD (see section 0).
- 2026-07-20: speech read as "(silence)" on device while calibration meter
  moved fine → fixed thresholds didn't fit real-device levels (`.measurement`
  mode has no AGC). Adaptive noise-floor gate + dead-band removal shipped;
  watch `RMS`/`Gate` debug lines to tune `NoiseFloor` constants. Likely also
  the root cause of (or a contributor to) the 0 s issue above.
