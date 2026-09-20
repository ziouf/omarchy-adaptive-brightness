#!/usr/bin/env bash
# Shared logic for ziouf.adaptive-brightness. Pure functions are unit-tested
# in tests/run.sh; everything touching hardware lives in the callers.

CONF_FILE="${ADAPTIVE_BRIGHTNESS_CONF:-$HOME/.config/adaptive-brightness.conf}"
STATE_DIR="${ADAPTIVE_BRIGHTNESS_STATE:-$HOME/.local/state/adaptive-brightness}"

conf_defaults() {
  MIN_BRIGHT=10      # floor applied by the adaptive loop (%)
  MAX_BRIGHT=100     # ceiling applied by the adaptive loop (%)
  GAIN=1.6           # webcam luminance multiplier (calibrate per camera)
  INTERVAL=15        # seconds between measurements in the loop
  EMA_ALPHA=0.3      # smoothing factor 0..1 (higher = more reactive)
  DEADBAND=3         # ignore changes smaller than this (%, anti-flicker)
  LUX_MAX=5000       # lux mapped to MAX_BRIGHT on the ALS curve
  EXPOSURE=250       # manual webcam exposure (100µs units) when locking AE
  CAM=""             # override webcam device (empty = autodetect)
  BACKLIGHT=""       # override brightnessctl device (empty = autodetect)
}

read_conf() {
  conf_defaults
  [ -f "$CONF_FILE" ] && . "$CONF_FILE"
  # sanitize numerics so a broken conf cannot wedge the loop
  case "$MIN_BRIGHT" in (''|*[!0-9]*) MIN_BRIGHT=10;; esac
  case "$MAX_BRIGHT" in (''|*[!0-9]*) MAX_BRIGHT=100;; esac
  case "$INTERVAL"  in (''|*[!0-9]*) INTERVAL=15;; esac
  case "$DEADBAND"  in (''|*[!0-9]*) DEADBAND=3;; esac
}

clamp100() {
  local n=$1
  (( n < 1 )) && n=1
  (( n > 100 )) && n=100
  echo "$n"
}

# valid_range MIN MAX -> 0 when usable (integers, 1..100, 5-point gap)
valid_range() {
  local min=$1 max=$2
  [[ "$min" =~ ^[0-9]+$ && "$max" =~ ^[0-9]+$ ]] || return 1
  (( min >= 1 && max <= 100 && max - min >= 5 ))
}

# map_lux LUX MIN MAX LUX_MAX -> target % (log curve: human perception is
# logarithmic; 1 lux ≈ MIN, LUX_MAX ≈ MAX)
map_lux() {
  awk -v l="$1" -v lo="$2" -v hi="$3" -v lmax="$4" 'BEGIN{
    if (l < 0) l = 0
    if (lmax <= 1) lmax = 2
    f = log(l + 1) / log(lmax)
    if (f < 0) f = 0; if (f > 1) f = 1
    printf "%d", lo + f * (hi - lo) + 0.5
  }'
}

# map_webcam MEAN MIN MAX GAIN -> target % (mean 0..255 of a gray frame)
map_webcam() {
  awk -v m="$1" -v lo="$2" -v hi="$3" -v g="$4" 'BEGIN{
    f = m * g / 255
    if (f < 0) f = 0; if (f > 1) f = 1
    printf "%d", lo + f * (hi - lo) + 0.5
  }'
}

# ema NEW PREV ALPHA -> smoothed value (PREV empty -> NEW)
ema() {
  awk -v n="$1" -v p="$2" -v a="$3" 'BEGIN{
    if (p == "" || p !~ /^-?[0-9.]+$/) { printf "%d", n; exit }
    printf "%d", a * n + (1 - a) * p + 0.5
  }'
}

# ---- sensor detection (hardware) ----------------------------------------

# detect_als -> prints sysfs path of an illuminance input file, or nothing.
# Scans IIO devices for the standard `in_illuminance_input` attribute
# (acpi_als, alsps, stk3310, ... all expose it).
detect_als() {
  local d
  for d in /sys/bus/iio/devices/iio:device*; do
    [ -r "$d/in_illuminance_input" ] && { echo "$d/in_illuminance_input"; return 0; }
  done
  return 1
}

# detect_cam -> prints a /dev/videoN that yields a real capture. Tries the
# cached device first. IR/metadata nodes fail the test capture, so this is
# portable across laptops without hardcoding names.
detect_cam() {
  local cache="$STATE_DIR/cam" v
  if [ -n "$CAM" ]; then echo "$CAM"; return 0; fi
  if [ -s "$cache" ] && cam_probe "$(<"$cache")" 2>/dev/null; then
    cat "$cache"; return 0
  fi
  for v in /dev/video*; do
    [ -e "$v" ] || continue
    if cam_probe "$v"; then
      mkdir -p "$STATE_DIR"; echo "$v" > "$cache"
      echo "$v"; return 0
    fi
  done
  return 1
}

cam_probe() {
  timeout 5 ffmpeg -hide_banner -loglevel error -y -f v4l2 -i "$1" \
    -frames:v 1 -vf "scale=1x1,format=gray" -f rawvideo - 2>/dev/null |
    grep -q .
}

# cam_luminance DEV -> mean gray 0..255 of one frame
cam_luminance() {
  ffmpeg -hide_banner -loglevel error -y -f v4l2 -i "$1" \
    -frames:v 1 -vf "scale=16:9,format=gray" -f rawvideo - 2>/dev/null |
    od -An -tu1 |
    awk '{for(i=1;i<=NF;i++){s+=$i;n++}} END{if(!n) exit 1; printf "%.1f", s/n}'
}

# Lock manual exposure so auto-exposure does not normalize away the ambient
# light we are trying to measure. Control name varies by kernel/driver:
# uvcvideo renamed exposure_auto -> auto_exposure. Failures are non-fatal
# (some cams refuse; measurements get noisier but keep working).
cam_lock_exposure() {
  command -v v4l2-ctl >/dev/null || return 0
  local dev=$1 name
  for name in auto_exposure exposure_auto; do
    if v4l2-ctl -d "$dev" -c "$name=1" 2>/dev/null; then
      v4l2-ctl -d "$dev" -c exposure_time_absolute="$EXPOSURE" 2>/dev/null
      echo "$name"
      return 0
    fi
  done
  return 0
}

cam_restore_exposure() {
  command -v v4l2-ctl >/dev/null || return 0
  local dev=$1 name=$2
  [ -n "$name" ] && v4l2-ctl -d "$dev" -c "$name=3" 2>/dev/null
}

# ---- backlight -----------------------------------------------------------

# bl_pct -> current backlight level in % (1..100)
bl_pct() {
  local args=()
  [ -n "$BACKLIGHT" ] && args=(-D "$BACKLIGHT")
  local cur max
  cur=$(brightnessctl "${args[@]}" get 2>/dev/null) || return 1
  max=$(brightnessctl "${args[@]}" max 2>/dev/null) || return 1
  awk -v c="$cur" -v m="$max" 'BEGIN{printf "%d", c/m*100 + 0.5}'
}

bl_set() {
  local args=()
  [ -n "$BACKLIGHT" ] && args=(-D "$BACKLIGHT")
  brightnessctl "${args[@]}" set "$1%" >/dev/null 2>&1
}
