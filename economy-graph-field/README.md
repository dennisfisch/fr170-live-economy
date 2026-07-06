# Economy Graph — Connect IQ Data Field

Full-screen Connect IQ data field for the **Garmin Forerunner 170 Music** (device id `fr170m`).

> **Status:** this still contains the original all-in-one implementation (NOW/SPLIT rows +
> 30s graph) from before the project was split into 3 separate apps — see `/CLAUDE.md` at the
> repo root for why. It has **not yet been stripped down to graph-only**. Not part of today's
> build scope (`ef-field/` is). Treat the content below as accurate for what's in this folder
> right now, not as a finished spec.

## Metrics

- **Power/HR** — `currentPower / currentHeartRate` (W/bpm), smoothed with an exponential moving
  average over roughly 3 samples.
- **EF (live, speed-based)** — `currentSpeed / currentHeartRate × 1000`.

  **This is not the same as the grade-adjusted-pace (GAP) based EF used in the separate
  after-run report.** Garmin's GAP is not exposed live via the Connect IQ API, so this field falls
  back to raw speed. It is labeled `EF (speed-based)` everywhere in the UI and settings to avoid
  confusion with the report's GAP-based EF.

  An optional **grade-adjust** toggle (app settings) applies a rough correction from barometric
  altitude change: `grade = Δaltitude / Δdistance`, `factor = clamp(1 + 3×grade, 0.5, 2.0)`,
  `EF_adjusted = EF × factor`. This is a simple heuristic, not a real GAP model — treat it as
  "better than nothing," not authoritative.

## Layout (current, pre-split-out)

1. **Now** (top): smoothed instantaneous EF and Power/HR.
2. **Split** (middle): lap average of both metrics since the last lap/reset.
3. **Last 30s** (bottom): sparkline of one metric (default Power/HR, switchable in settings) with
   min/max labels.

If the field ends up in a small multi-field slot instead of a full-screen slot, it degrades to two
text lines (no graph).

**Planned end state** (not yet done): drop the NOW/SPLIT rows entirely (those live in
`ef-field`/`power-hr-field` now), widen the ring buffer to ~180 samples (3 min) for a more
legible trend than 30s, keep only the graph.

## Project layout

```
manifest.xml                          product: fr170m (Forerunner 170 Music)
monkey.jungle
source/
  EconomyGraphApp.mc                   AppBase entry point
  EconomyGraphView.mc                  DataField: compute() + onUpdate()
  RingBuffer.mc                        fixed-capacity circular buffer (30 samples)
resources/
  strings/strings.xml
  settings/properties.xml              persisted app settings (defaults)
  settings/settings.xml                Garmin Connect Mobile settings UI
  drawables/                           launcher icon (required by manifest even for datafield type)
```

## Setup

1. Install the Connect IQ SDK Manager: https://developer.garmin.com/connect-iq/sdk/
   Use it to accept the SDK license and download the current SDK core plus the
   **Forerunner 170 Music** (`fr170m`) device definition. Installs to
   `~/Library/Application Support/Garmin/ConnectIQ/` on macOS, not `~/.Garmin/`.
2. Generate a developer key (once), keep it outside the repo — the root `developer_key.der` is
   shared across all sub-projects in this repo:
   ```
   openssl genrsa -out developer_key.pem 4096
   openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
   ```
3. Add the SDK's `bin/` to your `PATH` (or reference full paths below).

## Build

```
monkeyc -f monkey.jungle -d fr170m -o bin/EconomyGraph-fr170m.prg -y ../developer_key.der
```
(run from inside `economy-graph-field/`)

## Simulator

```
connectiq                                              # launches the simulator
monkeydo bin/EconomyGraph-fr170m.prg fr170m
```

To run a test activity: **Simulation → Activity Data**, leave Data Source on "Data Simulation",
click **Start** (begins the on-watch timer), then click the ▶ play control next to the slider at
the bottom of that panel (this is what actually advances simulated time/sensors — Start alone
does not). EF (speed+HR based) populates within a few seconds this way.

**Running Power does not populate in "Data Simulation" mode** — confirmed on SDK 9.2.0: speed and
heart rate ramp up and EF computes correctly, but `currentPower` stays null the entire run, so
Power/HR and the default 30s graph stay on "collecting...". To get real power data, either load a
recorded FIT file with a Running Power stream via **Data Source → FIT/GPX Playable File**, or test
on-device. See **Known limitations** below.

### Gotcha: `has`-guard optional Activity.Info fields

`info.currentPower`, `currentSpeed`, `currentHeartRate`, and `altitude` are all conditionally
present depending on device/firmware. Accessing one directly without a guard compiles fine but
**crashes at runtime** with `Symbol Not Found Error` the instant `compute()` runs on a device/sim
where the field isn't populated yet. Always guard:

```
var power = (info has :currentPower) ? info.currentPower : null;
```

This bit us during initial testing — the field crashed immediately in the simulator until every
optional field read was guarded this way.

## Sideload

1. Connect the watch via USB.
2. Copy the built `.prg` to `GARMIN/APPS/` on the device volume.
3. Eject, disconnect, and select the field from a data screen's field picker on the watch.

## Known limitations

- **GAP is not live.** The live EF here is speed-based, not grade-adjusted-pace-based like the
  offline report. The optional grade-adjust toggle is a rough linear heuristic, not a GAP model.
- **Data field memory budget is small.** The ring buffer is capped at 30 samples and reused
  in place; avoid growing it or adding per-tick allocations in `onUpdate`.
- **Simulator's "Data Simulation" mode does not synthesize Running Power.** Confirmed on SDK
  9.2.0: speed and heart rate are fabricated and ramp up fine (EF works), but `currentPower` stays
  null for the whole run. The field correctly stays on "collecting..." for the (default) Power/HR
  graph rather than crashing — but you'll want a real FIT replay with a power stream, or on-device
  testing, before trusting Power/HR numbers.
- Null handling: metrics only accumulate when heart rate, speed (and, for Power/HR, power) are
  present and speed is above a small moving threshold (0.5 m/s), to avoid divide-by-noise while
  stopped.
