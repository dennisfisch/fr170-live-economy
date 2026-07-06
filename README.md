# Live Running Economy — Connect IQ Data Field

Full-screen Connect IQ data field for the **Garmin Forerunner 170 / 170 Music** that shows two
running-economy metrics live, each in three time windows: instantaneous, current split/lap average,
and a 30-second sparkline.

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

## Layout

1. **Now** (top): smoothed instantaneous EF and Power/HR.
2. **Split** (middle): lap average of both metrics since the last lap/reset.
3. **Last 30s** (bottom): sparkline of one metric (default Power/HR, switchable in settings) with
   min/max labels.

If the field ends up in a small multi-field slot instead of a full-screen slot, it degrades to two
text lines (no graph).

## Project layout

```
manifest.xml                          products: forerunner170, forerunner170music
monkey.jungle
source/
  LiveRunningEconomyApp.mc             AppBase entry point
  LiveRunningEconomyView.mc            DataField: compute() + onUpdate()
  RingBuffer.mc                        fixed-capacity circular buffer (30 samples)
resources/
  strings/strings.xml
  settings/properties.xml              persisted app settings (defaults)
  settings/settings.xml                Garmin Connect Mobile settings UI
```

## Setup

1. Install the Connect IQ SDK Manager: https://developer.garmin.com/connect-iq/sdk/
   Use it to accept the SDK license and download the current SDK core plus the
   **Forerunner 170** and **Forerunner 170 Music** device definitions.
2. Generate a developer key (once), keep it outside the repo:
   ```
   openssl genrsa -out developer_key.pem 4096
   openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
   ```
3. Add the SDK's `bin/` to your `PATH` (or reference full paths below).

## Build

```
monkeyc -f monkey.jungle -d forerunner170        -o bin/LiveRunningEconomy-fr170.prg      -y developer_key.der
monkeyc -f monkey.jungle -d forerunner170music   -o bin/LiveRunningEconomy-fr170music.prg  -y developer_key.der
```

## Simulator

```
connectiq                 # launches the simulator
monkeydo bin/LiveRunningEconomy-fr170.prg forerunner170
```

In the simulator, use the sensor/FIT-replay panel to feed Running Power (and HR/speed) so
`currentPower` is non-null. If your simulator build doesn't support power replay, sideload to a
real FR170 and record a short outdoor/treadmill run instead — see **Known limitations** below.

## Sideload

1. Connect the watch via USB.
2. Copy the built `.prg` to `GARMIN/APPS/` on the device volume.
3. Eject, disconnect, and select the field from a data screen's field picker on the watch.

## Known limitations

- **GAP is not live.** The live EF here is speed-based, not grade-adjusted-pace-based like the
  offline report. The optional grade-adjust toggle is a rough linear heuristic, not a GAP model.
- **Data field memory budget is small.** The ring buffer is capped at 30 samples and reused
  in place; avoid growing it or adding per-tick allocations in `onUpdate`.
- **Simulator power replay is unverified on this machine** at the time of writing — confirm your
  SDK/simulator version can replay Running Power for FR170 before relying on it for testing;
  otherwise test on-device.
- Null handling: metrics only accumulate when heart rate, speed (and, for Power/HR, power) are
  present and speed is above a small moving threshold (0.5 m/s), to avoid divide-by-noise while
  stopped.
