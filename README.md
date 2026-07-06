# fr170-live-economy

Connect IQ data fields for the **Garmin Forerunner 170 Music** (`fr170m`) surfacing two
running-economy metrics live: **Power/HR** (W/bpm) and **EF (speed-based)** (not the same as the
GAP-based EF used in a separate after-run report — GAP isn't available live via Connect IQ).

See **[`CLAUDE.md`](CLAUDE.md)** for full project context, architecture decisions, and every
gotcha hit while building this — read that first if you're picking this project back up.

## Why three separate apps

Connect IQ only allows **one field per app** (one `<iq:application>` per manifest), and most
Forerunner-class devices allow a maximum of **2 custom Connect IQ fields per screen**. Since the
goal is to drop these into existing "Laufen"/"Laufbahn"/"Laufband" activity screens next to
native fields like Pace or Ru.Leist. (not take over the whole screen), that means separate
small apps, not one big custom-drawn field:

| Project | Type | Status |
|---|---|---|
| [`ef-field/`](ef-field/) | `SimpleDataField`, native label+value | **Today's focus.** Not yet built. |
| `power-hr-field/` | `SimpleDataField`, native label+value | Not started — later |
| [`economy-graph-field/`](economy-graph-field/) | full-screen custom `DataField`, sparkline | Original all-in-one implementation, not yet trimmed to graph-only — later |

## Today's scope

**Only `ef-field`.** Exactly 2 selectable modes (matching the 2-custom-field-per-screen limit,
so both can be placed on one screen at once):

- **Split** — lap average EF since the last lap/reset
- **Whole Activity** — average EF since the activity started (survives laps, only resets on
  `onTimerReset`)

No "live/instant" mode, no Power/HR field, no graph today — see `CLAUDE.md` for the full plan.

## Setup (shared across all sub-projects)

1. Install the Connect IQ SDK Manager: https://developer.garmin.com/connect-iq/sdk/ — accept
   the license, download the SDK core plus the **Forerunner 170 Music** (`fr170m`) device.
   Installs to `~/Library/Application Support/Garmin/ConnectIQ/` on macOS (not `~/.Garmin/`).
2. Generate a developer key once at the repo root (gitignored, shared by every sub-project):
   ```
   openssl genrsa -out developer_key.pem 4096
   openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
   ```
3. Each sub-project has its own `manifest.xml`/`monkey.jungle`/README with its own build command
   — see that sub-project's README.

## License

MIT — see [`LICENSE`](LICENSE).
