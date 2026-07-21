# Turn Annotator

Label who's speaking in a recorded conversation — after the fact, while
listening back — instead of tapping labels live mid-conversation. Produces the
same `labels.json` the in-app Ground Truth Recorder writes, ready for
`tools/eval/run.sh`.

## Use

Open `annotate.html` in a browser (double-click; no server, no install,
nothing leaves your machine).

1. **Load audio** — any format the browser can play (the app recorder's WAV,
   a Voice Memos m4a, an mp3).
2. Press **space** and listen. Tap **M / O / Q / U** (me / others / quiet /
   unsure) the moment the speaker changes — each tap drops a marker at the
   playhead. The waveform paints itself in the label colors, so unlabeled or
   mislabeled stretches are visible at a glance.
3. Fix up: drag marker lines to nudge boundaries, click a time in the table to
   jump there, change a label from its dropdown, ⌫ deletes, ⌘Z undoes.
   Slower/faster playback and zoom help with rapid exchanges.
4. **Export labels.json**, and — if the audio didn't come from the app —
   **Export 16 kHz WAV** to get harness-ready audio.

Then:

```bash
tools/eval/run.sh recording.16k.wav recording.labels.json
```

You can also **Load labels** to refine an existing file (e.g. clean up a
session that was live-tapped in the app).

## Tips for a useful session

- Include a **contiguous ≥ 12 s stretch of just you** — the harness enrolls
  from the first long "me" segment and excludes it from scoring.
- Use **unsure** for overlap/crosstalk; those spans are excluded from scoring
  rather than polluting the labels.
- Prefer recordings made with the app's Ground Truth Recorder when possible:
  it uses the exact tracker audio path (16 kHz, `.measurement` mode, no
  automatic gain control). Phone-app recordings (Voice Memos etc.) work and
  are fine for matcher research, but their gain processing differs slightly
  from what the live pipeline hears.
