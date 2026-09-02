#!/usr/bin/env bash
# jsg-custom-dock installer.
#
# Builds from source and installs:
#   * Binary at $BIN_DIR/jsg-custom-dock (system /usr/bin or user ~/.local/bin)
#   * Symlink at ~/.local/bin/jsg-custom-dock pointing at the binary
#   * Default config at $CFG_DIR/omarchy/dock.toml (skipped if user already has one)
#   * Hyprland snippet at $CFG_DIR/hypr/jsg-custom-dock.lua (user) or /etc/hypr/ (system)
#
# Idempotent: re-running is safe. Existing user config is never overwritten.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ASSETS="$REPO_ROOT/assets"
PKG="jsg-custom-dock"

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
echo "==> Building $PKG (release)"
if ! command -v cargo >/dev/null 2>&1; then
    echo "error: cargo not found. Install Rust via:"
    echo "  mise install rust@stable"
    echo "  or https://rustup.rs/"
    exit 1
fi
(cd "$REPO_ROOT" && cargo build --release)

# 2. Install binary --------------------------------------------------------
BIN_TARGET="$BIN_DIR/$PKG"
echo "==> Installing binary to $BIN_TARGET"
install -Dm0755 "$REPO_ROOT/target/release/$PKG" "$BIN_TARGET"

# Symlink for ~/.local/bin so both paths work.
mkdir -p "$USER_BIN"
if [[ ! -e "$USER_BIN/$PKG" ]]; then
    echo "==> Symlinking $USER_BIN/$PKG -> $BIN_TARGET"
    ln -s "$BIN_TARGET" "$USER_BIN/$PKG"
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
#   * Per-user -> ~/.config/hypr/jsg-custom-dock.lua, loaded as `require("hypr.jsg-custom-dock")`
#   * System  -> /etc/hypr/jsg-custom-dock.lua, loaded as absolute path
# Omarchy's bootstrap adds ~/.config/?/?.lua and $OMARCHY_PATH/?.lua to
# package.path, so per-user installs are picked up automatically.
SNIPPET="$HYPR_DIR/jsg-custom-dock.lua"
echo "==> Installing Hyprland snippet to $SNIPPET"
install -Dm0644 "$ASSETS/jsg-custom-dock.lua" "$SNIPPET"

# 5. Wire up Hyprland (best-effort) ----------------------------------------
# Two paths:
#   * Per-user: `require("hypr.jsg-custom-dock")` (Omarchy's package.path resolves it)
#   * System:   `require("/etc/hypr/jsg-custom-dock")` absolute (no package.path entry)
#
# If hyprland.lua exists and the require isn't already there, append it.
# Then attempt hyprctl reload if a Hyprland session is reachable.
if [[ "$INSTALL_KIND" == "system" ]]; then
    WIRE_LINE='require("/etc/hypr/jsg-custom-dock")'
else
    WIRE_LINE='require("hypr.jsg-custom-dock")'
fi

MARKER="-- $PKG: managed by install.sh; safe to delete if you uninstall."

if [[ -f "$USER_HYPR" ]]; then
    # Detect by the marker comment, not the require string. Catches any
    # whitespace variant of the require line, including manual edits.
    if grep -F -- "$MARKER" "$USER_HYPR" >/dev/null 2>&1; then
        echo "==> Hyprland config already wired (marker found)"
        RELOAD_NEEDED=0
    else
        # Append with a marker so future installs can detect and (if needed)
        # remove the line, and so the user knows where it came from.
        printf '\n%s\n%s\n' "$MARKER" "$WIRE_LINE" >> "$USER_HYPR"
        echo "==> Appended to $USER_HYPR:"
        echo "    $WIRE_LINE"
        RELOAD_NEEDED=1
    fi
else
    echo
    echo "==> No $USER_HYPR found."
    echo "    Create one and add this line to load the dock rules:"
    echo
    echo "    $WIRE_LINE"
    RELOAD_NEEDED=0
fi

# Reload only if we changed something AND Hyprland is reachable. A fresh
# install on a machine without a running session shouldn't trigger anything.
# Also check configerrors after reload: hyprctl reload doesn't validate Lua
# syntax, so a bad edit can leave the session in an inconsistent state.
if [[ "$RELOAD_NEEDED" -eq 1 ]] && command -v hyprctl >/dev/null 2>&1; then
    if hyprctl reload >/dev/null 2>&1; then
        echo "==> Hyprland reloaded"
        errs=$(hyprctl configerrors 2>&1 || true)
        if [[ -n "$errs" ]]; then
            echo "==> WARNING: Hyprland reported config errors:"
            echo "$errs" | sed 's/^/    /'
        fi
    else
        echo "==> hyprctl reload failed (no active session?); reload manually after first login"
    fi
fi

echo
echo "==> Done ($INSTALL_KIND install)."
echo "    Test: $PKG ls"