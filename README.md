# omarchy-adaptive-brightness

Adaptive screen brightness for Omarchy: measures ambient light and drives the
backlight within user-set min/max bounds.

Sensor priority (maximum hardware compatibility):

1. **IIO ambient light sensor** (`/sys/bus/iio/devices/*/in_illuminance_input`)
   — used automatically on machines that have one (lux, log-mapped).
2. **Built-in webcam fallback** — one gray frame every interval, mean luminance.
   The camera's auto-exposure is locked before each capture (control names
   `auto_exposure`/`exposure_auto` both tried) so ambient light is not
   normalized away; machines whose camera refuses the lock still work, just
   with noisier readings. Capture devices are autodetected by test-capturing
   each `/dev/video*`, so IR/metadata nodes are skipped.

Backlight control via `brightnessctl` (works on Intel/AMD/ACPI backlight
`uaccess` setups — the Omarchy default).

## Install

```bash
git clone https://github.com/<you>/omarchy-adaptive-brightness \
  ~/.config/omarchy/plugins/ziouf.adaptive-brightness
~/.config/omarchy/plugins/ziouf.adaptive-brightness/install-services.sh
```

Optional Display-panel integration (toggle row + min/max bounds slider):

```bash
omarchy plugin clone omarchy.monitor
cp ~/.config/omarchy/plugins/ziouf.adaptive-brightness/panel/*.qml \
   ~/.config/omarchy/plugins/cyril.monitor/
```

`panel/` is a fork of the built-in `omarchy.monitor` panel: after Omarchy
updates change that panel, re-run `omarchy plugin clone` (into a scratch dir)
and re-apply these files' changes.

Launcher toggle: add to `~/.config/omarchy/extensions/omarchy-menu.jsonc`
(see the `trigger.toggle.adaptive-brightness` entry in this repo's README
history) or use `scripts/toggle` directly.

## Usage

- Toggle: Display panel row, `scripts/toggle`, or the launcher entry.
- Bounds: when adaptive is on, the Display panel brightness slider becomes a
  two-handle slider (min/max). Keyboard: focus the brightness row, Enter
  switches which handle `h`/`l` edits.
- Config: `~/.config/adaptive-brightness.conf`
  (`MIN_BRIGHT`, `MAX_BRIGHT`, `GAIN`, `INTERVAL`, `EMA_ALPHA`, `DEADBAND`,
  `LUX_MAX`, `EXPOSURE`, `CAM`, `BACKLIGHT`). Re-read on every tick.
- Diagnostics: `scripts/check` prints the detected sensor and backlight.

## Known limitations

- Webcam mode briefly wakes the camera each interval (privacy light blinks).
  Increase `INTERVAL` if that bothers you.
- HDMI/DP external backlights need DDC/CI (`ddcutil`) — not covered.
- Very dark scenes with bright objects can read bright; tune `GAIN`.

## Tests

```bash
bash tests/run.sh
```
