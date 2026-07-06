# fr-dennis — FR170 Music running-economy Connect IQ fields

## What this is

A suite of Connect IQ **data fields** for the Garmin Forerunner 170 Music (device id
`fr170m`) that surface two running-economy metrics Garmin doesn't expose natively:

- **Power/HR** — `currentPower / currentHeartRate` (W/bpm)
- **EF (speed-based)** — `currentSpeed / currentHeartRate × 1000`. **Not** the same as the
  GAP-based EF used in the user's separate after-run report (GAP isn't available live via
  Connect IQ) — always label this distinctly as "EF (speed-based)" wherever it's user-facing.

## Critical architecture decision: 3 separate apps, not 1

Originally built as a single full-screen custom `WatchUi.DataField` that drew everything
(instant/split/graph, both metrics) itself. **The user rejected this** — they don't want a
dedicated full-screen slot; they want fields droppable into their existing "Laufen" /
"Laufbahn" / "Laufband" activity screens next to stock fields like Pace / Ru.Leist. / HF,
looking and sizing exactly like those native fields.

That requires **`WatchUi.SimpleDataField`** (native label-above-value rendering, sized by
whatever grid slot the user puts it in), not a custom-drawn canvas. Two hard constraints this
runs into, confirmed via the installed SDK and Garmin forums:

1. **One `<iq:application>` per manifest.xml** — a single Connect IQ project can only expose
   ONE field/app. Confirmed by inspecting real manifests (e.g. the bundled `MoxyField` sample).
   There is no way to bundle multiple distinct selectable fields into one installed app.
2. **Most Forerunner-class devices allow max 2 custom Connect IQ fields per screen** (native
   fields are unlimited; this cap is specifically for 3rd-party Connect IQ fields). Confirmed
   via Garmin forums; FR170 is assumed to follow the same tier as FR165/955 etc. — not
   independently verified on this exact device yet.

**Consequence:** this repo is a monorepo of independent Connect IQ projects, each its own
manifest/app-id/build/sideload, sharing no runtime code (small enough logic that duplication is
fine — a Barrel library would be the DRY way to share it later if this grows):

- `ef-field/` — SimpleDataField, EF only. Settings: which time window to show.
- `power-hr-field/` — SimpleDataField, Power/HR only. Same settings pattern. **Not started.**
- `economy-graph-field/` — full-screen custom field, sparkline trend graph, metric selectable
  via settings. This is the OLD original all-in-one implementation, filenames renamed
  (`EconomyGraphApp.mc`/`EconomyGraphView.mc`) but **not yet stripped down to graph-only** —
  still contains the NOW/SPLIT row-drawing code from the original design. Needs: remove
  NOW/SPLIT rows (those are now `ef-field`/`power-hr-field`'s job), widen the ring buffer from
  30 samples (30s) to something like 180 (3 min) for a more legible trend, keep the
  EF/grade-adjust computation since the graph needs it too.

### Today's actual scope (per explicit user instruction)

**Only `ef-field`.** Exactly 2 modes, matching the 2-custom-field-per-screen limit so the user
can place both simultaneously:
- **Split** — lap average EF since last lap/reset
- **Whole Activity** — average EF since activity start (never reset by lap, only by
  `onTimerReset`)

No "Live/instant" mode today (may come later). No Power/HR field today. No Graph field today.
User will pick which of the 2 EF instances go where.

Likely implementation shape (not yet built): `ef-field/manifest.xml` (own app id, one
`<iq:product id="fr170m"/>`, `type="datafield"`, needs `launcherIcon` even though it's a
datafield — see gotcha below), `ef-field/source/EFFieldApp.mc` (AppBase), `EFFieldView.mc`
(`SimpleDataField`, `compute(info)` returns the Float for whichever mode is configured, guard
all optional `Activity.Info` fields per the gotcha below), settings dropdown "EF window": Split
/ Activity, label text probably just "EF" (native fields typically show short labels).

## Verified facts about this dev environment

- **SDK install path on this Mac**: `~/Library/Application Support/Garmin/ConnectIQ/`, **not**
  `~/.Garmin/ConnectIQ/` as most docs/tutorials assume. SDK version 9.2.0 at time of writing.
  `monkeyc`/`monkeydo`/`connectiq` binaries are under
  `.../Sdks/connectiq-sdk-mac-9.2.0-.../bin/`.
- **Device id is `fr170m`**, not `forerunner170` or `forerunner170music` as initially guessed.
  Confirmed via `Devices/fr170m/compiler.json`: `displayName: "Forerunner® 170 Music"`,
  resolution 390×390 round, touch-capable, `datafield` app type memory limit 262144 bytes.
- User only cares about the Music variant — no need to also target a non-music `fr170` product.
- Developer key generated at repo root (`developer_key.pem`/`.der`, gitignored) — reused across
  all sub-projects; each sub-project's manifest needs its own unique app `id` (UUID), but they
  can share this same signing key.

## Real gotchas hit while building (don't re-derive these the hard way)

1. **`import Toybox.Lang;` is required per-file**, not project-wide, or bare `Number`/`Float`/
   `Boolean`/`String`/`Array` type annotations fail to resolve at compile time. Aliasing
   `using Toybox.Lang as Lang;` does NOT fix it — you need the bare `import` statement in every
   `.mc` file that uses type annotations.
2. **`launcherIcon` is required in the manifest even for `type="datafield"`** on this SDK/device
   — compiler errors "A launcher icon must be specified" without it. Needs a
   `resources/drawables/drawables.xml` + actual PNG (54×54 for this device, per
   `compiler.json`'s `launcherIcon` field).
3. **`getInitialView()` must NOT have an explicit return type annotation** — annotating it as
   `Array<Ui.Views or Ui.InputDelegates>?` fails with "Cannot override ... with a different
   return type" against `AppBase`'s own (differently-shaped) declared signature. Just omit the
   `as ...` on this one override.
4. **Class member fields with non-nullable types must be initialized at declaration**, not
   inside a helper method called from `initialize()` — e.g. `private var _splitEfSum as Float = 0.0;`
   not `_splitEfSum` set later via a `resetSplit()` call, or the compiler flags "may not be
   initialized but does not accept Null" even though the call always runs.
5. **`has`-guard every optional `Activity.Info` field before reading it**:
   `var power = (info has :currentPower) ? info.currentPower : null;` — NOT just a null-check
   on the value. Skipping the `has` check compiles fine but **crashes at runtime** with
   `Symbol Not Found Error` the instant `compute()` runs on a device/sim/firmware combo where
   the field isn't populated. This is different from (and in addition to) ordinary null
   handling. Bit us immediately in first simulator test.
6. **Layout: use `dc.getFontHeight(font)` to space stacked text, never hardcoded pixel
   offsets.** A `+ 20` guess for label-below-value spacing overlapped badly on this device's
   actual (390×390, higher-res-than-expected) font rendering — see screenshots in git history
   around the "sieht das gut aus?" exchange. Always measure, never guess, when doing manual
   canvas layout in a full-screen field.
7. **`Application.Properties.getValue("key")`** is the current (non-deprecated) way to read
   settings; `AppBase.getProperty()` still works but emits a deprecation warning.
8. Font constant is `Gfx.FontDefinition` type, not `Number` — matters if you pass a font through
   a helper function parameter.

## Simulator quirks (SDK 9.2.0, this machine)

- To actually run a simulated activity: **Simulation → Activity Data**, Data Source =
  "Data Simulation", click **Start** (begins on-watch timer) — but that alone does NOT advance
  simulated sensors. You must ALSO click the **▶ play button** next to the slider at the bottom
  of that same panel; that's what actually advances simulated time/sensor values. Easy to miss.
- **"Data Simulation" mode fabricates speed and heart rate but never populates
  `currentPower`.** Confirmed empirically: EF computed and updated live correctly the whole
  run; Power/HR and the (then-existing) default graph metric sat on "collecting..."/`--` the
  entire time because `currentPower` stayed null. To test Power/HR for real, need either a real
  recorded FIT file with a Running Power stream (`Data Source → FIT/GPX Playable File`) or an
  on-device test. No bundled SDK sample FIT has a running-power stream to test with.
- GUI automation via `osascript`/System Events works but needs **both** Accessibility AND the
  app actually being frontmost (`set frontmost to true`) before UI element queries succeed —
  and needs the user to explicitly grant Accessibility permission to the terminal app (Ghostty
  here) in System Settings, a plain "-1719" error otherwise. Screenshots: `screencapture -R
  x,y,w,h` with the window's AppleScript-reported point-space bounds works reliably; that region
  flag correctly handles Retina 2x scaling internally (screenshot pixels = 2× the point bounds
  here).

## Repo/process notes

- GitHub: `dennisfisch/fr170-live-economy`, public, pushed.
- Commit style so far: descriptive bodies explaining *why* a fix was needed (the actual bug
  hit), not just *what* changed — keep doing this, it's what let this file get written
  accurately.
- User reviews actual rendered simulator screenshots critically (caught the font overlap bug
  immediately) — don't report a UI feature "done" without an actual screenshot check.
