#!/usr/bin/env bash
# omarchy-dock installer.
#
# Builds from source and installs:
#   * Binary at $BIN_DIR/omarchy-dock (system /usr/bin or user ~/.local/bin)
#   * Symlink at ~/.local/bin/omarchy-dock pointing at the binary
#   * Default config at $CFG_DIR/omarchy/dock.toml (skipped if user already has one)
#   * Hyprland snippet at $CFG_DIR/hypr/omarchy-dock.lua (user) or /etc/hypr/ (system)
#
# Idempotent: re-running is safe. Existing user config is never overwritten.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ASSETS="$REPO_ROOT/assets"

# Resolve install paths: system-wide if root, per-user otherwise.
if [[ $EUID -eq 0 ]]; then
    BIN_DIR="/usr/bin"
    CFG_DIR="/etc"
    HYPR_DIR="/etc/hypr"
    INSTALL_KIND="system"
else
    BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
    CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
    HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
    INSTALL_KIND="user"
fi

USER_BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"
USER_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/dock.toml"
USER_HYPR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua"

# 1. Build -----------------------------------------------------------------
echo "==> Building omarchy-dock (release)"
if ! command -v cargo >/dev/null 2>&1; then
    echo "error: cargo not found. Install Rust via:"
    echo "  mise install rust@stable"
    echo "  or https://rustup.rs/"
    exit 1
fi
(cd "$REPO_ROOT" && cargo build --release)

# 2. Install binary --------------------------------------------------------
BIN_TARGET="$BIN_DIR/omarchy-dock"
echo "==> Installing binary to $BIN_TARGET"
install -Dm0755 "$REPO_ROOT/target/release/omarchy-dock" "$BIN_TARGET"

# Symlink for ~/.local/bin so both paths work.
mkdir -p "$USER_BIN"
if [[ ! -e "$USER_BIN/omarchy-dock" ]]; then
    echo "==> Symlinking $USER_BIN/omarchy-dock -> $BIN_TARGET"
    ln -s "$BIN_TARGET" "$USER_BIN/omarchy-dock"
fi

# 3. Default config --------------------------------------------------------
# Install a default at the system location (or per-user), and seed the user's
# config dir only if absent. User edits win on re-install.
SYSTEM_CFG="$CFG_DIR/omarchy/dock.toml"
echo "==> Installing default config to $SYSTEM_CFG"
install -Dm0644 "$ASSETS/dock.toml" "$SYSTEM_CFG"

if [[ ! -e "$USER_CFG" ]]; then
    echo "==> Seeding user config at $USER_CFG"
    mkdir -p "$(dirname "$USER_CFG")"
    install -Dm0644 "$ASSETS/dock.toml" "$USER_CFG"
else
    echo "==> User config already exists; leaving $USER_CFG alone"
fi

# 4. Hyprland snippet ------------------------------------------------------
# Place the snippet where Hyprland's standard require() resolver can find it:
#   * Per-user -> ~/.config/hypr/omarchy-dock.lua, loaded as `require("hypr.omarchy-dock")`
#   * System  -> /etc/hypr/omarchy-dock.lua, loaded as `require("hypr.omarchy-dock")`
# Omarchy's bootstrap adds ~/.config/?/?.lua and $OMARCHY_PATH/?.lua to
# package.path, so per-user installs are picked up automatically.
SNIPPET="$HYPR_DIR/omarchy-dock.lua"
echo "==> Installing Hyprland snippet to $SNIPPET"
install -Dm0644 "$ASSETS/omarchy-dock.lua" "$SNIPPET"

# 5. Wire up Hyprland (best-effort) ----------------------------------------
# The require() path differs between install kinds:
#   * Per-user: `require("hypr.omarchy-dock")` (Omarchy's package.path resolves it)
#   * System:   `require("hypr.omarchy-dock")` works only if /etc/hypr is on the
#               path. On stock Omarchy it isn't, so we fall back to an absolute
#               require() for system installs.
if [[ "$INSTALL_KIND" == "system" ]]; then
    WIRE_LINE="require(\"$SNIPPET\")"
else
    WIRE_LINE='require("hypr.omarchy-dock")'
fi

if [[ -f "$USER_HYPR" ]]; then
    if grep -F "$WIRE_LINE" "$USER_HYPR" >/dev/null 2>&1; then
        echo "==> Hyprland config already wired"
    else
        echo
        echo "==> To finish setup, add this line to $USER_HYPR"
        echo "    (anywhere after the Omarchy requires):"
        echo
        echo "    $WIRE_LINE"
        echo
        echo "    Then run: hyprctl reload"
    fi
else
    echo
    echo "==> No $USER_HYPR found."
    echo "    Once you create one, add this line to load the dock rules:"
    echo
    echo "    $WIRE_LINE"
fi

echo
echo "==> Done ($INSTALL_KIND install)."
echo "    Test: omarchy-dock ls"