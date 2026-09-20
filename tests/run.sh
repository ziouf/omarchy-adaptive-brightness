#!/usr/bin/env bash
# Minimal assert-based tests for the pure functions in scripts/lib.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
export ADAPTIVE_BRIGHTNESS_CONF=/dev/null ADAPTIVE_BRIGHTNESS_STATE=/tmp/ab-test.$$
. scripts/lib.sh

fails=0
ok()   { echo "ok - $1"; }
bad()  { echo "FAIL - $1"; fails=$((fails+1)); }
t()    { local desc=$1 want=$2 got=$3; [ "$want" = "$got" ] && ok "$desc" || bad "$desc (want $want, got $got)"; }

# valid_range
valid_range 10 90 && ok "valid_range ok" || bad "valid_range 10 90"
valid_range 90 10 && bad "valid_range inverted" || ok "valid_range inverted"
valid_range 50 54 && bad "valid_range gap<5" || ok "valid_range gap<5"
valid_range 0 90 && bad "valid_range min 0" || ok "valid_range min 0"
valid_range 10 101 && bad "valid_range max 101" || ok "valid_range max 101"
valid_range "a" 9 && bad "valid_range non-numeric" || ok "valid_range non-numeric"
valid_range "" "" && bad "valid_range empty" || ok "valid_range empty"

# clamp100
t "clamp100 low"    1   "$(clamp100 -5)"
t "clamp100 high"   100 "$(clamp100 400)"
t "clamp100 mid"    42  "$(clamp100 42)"

# map_lux: 1 lux ~ MIN, LUX_MAX ~ MAX, log curve in between
t "map_lux floor"  10 "$(map_lux 0   10 90 5000)"
t "map_lux ceil"   90 "$(map_lux 5000 10 90 5000)"
mid=$(map_lux 70 10 90 5000)   # sqrt-ish midpoint of log curve
[ "$mid" -gt 40 ] && [ "$mid" -lt 60 ] && ok "map_lux log mid=$mid" || bad "map_lux log mid=$mid"

# map_webcam (black/white point)
t "map_webcam night"  10 "$(map_webcam 0 10 90 8 150)"    # below black -> min
t "map_webcam day"    90 "$(map_webcam 222 10 90 8 150)"  # daylight -> max
t "map_webcam half"   50 "$(map_webcam 79 10 90 8 150)"   # midpoint

# ema
t "ema first (no prev)" 42 "$(ema 42 "" 0.3)"
t "ema smooth"          30 "$(ema 20 40 0.5)"
t "ema passthrough"     42 "$(ema 42 42 0.3)"

# set-range -> get-range roundtrip
export ADAPTIVE_BRIGHTNESS_CONF=/tmp/ab-conf.$$
scripts/set-range 20 80
t "set-range roundtrip" "20 80" "$(scripts/get-range)"
scripts/set-range 80 20 2>/dev/null && bad "set-range rejects inverted" || ok "set-range rejects inverted"
rm -f "$ADAPTIVE_BRIGHTNESS_CONF"

rm -rf /tmp/ab-test.$$
if [ "$fails" -gt 0 ]; then echo "$fails test(s) failed"; exit 1; fi
echo "all tests passed"
