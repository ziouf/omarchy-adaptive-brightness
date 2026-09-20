#!/usr/bin/env bash
set -euo pipefail
systemctl --user disable --now adaptive-brightness 2>/dev/null || true
rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/adaptive-brightness.service"
systemctl --user daemon-reload
echo "adaptive-brightness service removed"
