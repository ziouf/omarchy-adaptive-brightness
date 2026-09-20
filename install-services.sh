#!/usr/bin/env bash
# Install the adaptive-brightness user service. The unit points at the
# plugin's scripts under ~/.config/omarchy/plugins/, so install the plugin
# there first (or adjust PLUGIN_DIR).
set -euo pipefail
src="$(cd "$(dirname "$0")" && pwd)"
dest="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/adaptive-brightness.service"
mkdir -p "$(dirname "$dest")"
cp "$src/systemd/adaptive-brightness.service" "$dest"
systemctl --user daemon-reload
echo "installed $dest (start with: systemctl --user start adaptive-brightness)"
