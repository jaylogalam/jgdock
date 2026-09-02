#!/usr/bin/env bash
# jgdock installer (user-only).
#
# Builds from source and installs:
#   - Binary at ~/.local/bin/jgdock
#   - Default config at ~/.config/jgdock/dock.toml (skipped if user has one)
#   - Hyprland snippet at ~/.config/jgdock/jgdock.lua (+ windowrules.lua,
#     bindings.lua side files), loaded via require("jgdock") after a
#     package.path prepend written into hyprland.lua
#
# Refuses to run as root: there's no system install mode. Running as root
# would write to /usr/bin /etc and produce a config the same user couldn't
# uninstall cleanly. Run as the user who will own the binary.
#
# Subcommands:
#   install (default)  Build + install from local source.
#   update             git fetch + fast-forward merge, then build + install.
#                      Use this on devices that already have the repo cloned
#                      to pick up changes pushed to the remote.
#   uninstall          Remove the binary, symlink, Hyprland snippet, and
#                      the require block from hyprland.lua. Prompts before
#                      removing the user config. Does NOT delete the source
#                      directory or cargo registry.
#
# Idempotent: re-running is safe. Existing user config is never overwritten.
# The wire block is detected by its marker comment, so old single-line
# `require("hypr.jgdock")` blocks from a prior version are migrated
# automatically.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ASSETS="$REPO_ROOT/assets"
PKG="jgdock"
CMD="${1:-install}"

BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
HYPR_DIR="$CFG_DIR/jgdock"
USER_CFG="$CFG_DIR/jgdock/dock.toml"
USER_HYPR="$CFG_DIR/hypr/hyprland.lua"
SNIPPET="$HYPR_DIR/jgdock.lua"
SNIPPET_RULES="$HYPR_DIR/windowrules.lua"
SNIPPET_BINDINGS="$HYPR_DIR/bindings.lua"

usage() {
    cat <<EOF
usage: $0 [install|update|uninstall]
  install    Build + install from local source (default).
  update     Fast-forward merge from origin, then build + install.
  uninstall  Remove binary, snippet files, and require block. Prompts
             before removing the user config; source dir is left alone.

User-only install. Refuses to run as root.
EOF
    exit 2
}

[[ "$CMD" == "-h" || "$CMD" == "--help" || "$CMD" == "help" ]] && usage

if [[ $EUID -eq 0 ]]; then
    echo "error: refusing to run as root. jgdock has no system install mode." >&2
    echo "       Run as the user who will own the binary." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Strip the marker + the wire block that follows it from hyprland.lua.
# The wire block is one or more lines, always terminated by a blank line.
# Drops the marker and everything up to and including the first blank line
# that follows.
#
# Used by both the uninstaller (remove entirely) and the installer (re-append
# with the current block shape to migrate from an older shape).
strip_wire_block() {
    local user_hypr="$1"
    local marker="$2"
    local tmp="${user_hypr}.jgdock.strip.$$"
    if ! awk -v m="$marker" '
        $0 == m { skip = 1; next }
        skip == 1 {
            if ($0 ~ /^[[:space:]]*$/) { skip = 0 }
            next
        }
        { print }
    ' "$user_hypr" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    # Trim trailing blanks the removal may have created.
    local trimmed
    trimmed=$(awk '
        { lines[NR] = $0 }
        END {
            last = NR
            while (last > 0 && lines[last] ~ /^[[:space:]]*$/) last--
            for (i = 1; i <= last; i++) print lines[i]
        }
    ' "$tmp")
    printf '%s\n' "$trimmed" > "$tmp"
    mv "$tmp" "$user_hypr"
}

# ---------------------------------------------------------------------------
# update: pull latest from the configured remote.
# Refuses if there are local uncommitted changes or a non-fast-forward state.
do_update() {
    if [[ ! -d "$REPO_ROOT/.git" ]]; then
        echo "error: $REPO_ROOT is not a git checkout; nothing to update." >&2
        exit 1
    fi

    local branch
    branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
        echo "error: not on a branch (detached HEAD?); cannot update safely." >&2
        exit 1
    fi

    if ! git -C "$REPO_ROOT" remote get-url origin >/dev/null 2>&1; then
        echo "error: no 'origin' remote configured; cannot update." >&2
        exit 1
    fi

    # Refuse to clobber local edits.
    if ! git -C "$REPO_ROOT" diff --quiet HEAD 2>/dev/null \
       || ! git -C "$REPO_ROOT" diff --cached --quiet 2>/dev/null; then
        echo "error: local uncommitted changes; commit or stash before updating." >&2
        git -C "$REPO_ROOT" status --short >&2
        exit 1
    fi

    echo "==> Fetching from origin/$branch"
    if ! git -C "$REPO_ROOT" fetch origin "$branch"; then
        echo "error: git fetch failed (offline?); aborting update." >&2
        exit 1
    fi

    local local_sha remote_sha
    local_sha=$(git -C "$REPO_ROOT" rev-parse HEAD)
    remote_sha=$(git -C "$REPO_ROOT" rev-parse "origin/$branch")

    if [[ "$local_sha" == "$remote_sha" ]]; then
        echo "==> Already up to date ($(git -C "$REPO_ROOT" rev-parse --short HEAD))"
        return 0
    fi

    # Fast-forward only — refuse to rebase/merge if local has diverged.
    if ! git -C "$REPO_ROOT" merge --ff-only "origin/$branch"; then
        echo "error: local branch has diverged from origin/$branch." >&2
        echo "       Resolve manually with git pull --rebase, then retry." >&2
        exit 1
    fi

    echo "==> Updated $(git -C "$REPO_ROOT" rev-parse --short "$local_sha") -> $(git -C "$REPO_ROOT" rev-parse --short HEAD)"
}

# ---------------------------------------------------------------------------
# uninstall: remove the binary and the require
# block from hyprland.lua. Asks before touching the user config (which may
# contain hand-edited dock specs). Leaves the source directory and cargo
# registry cache alone — those are not ours to delete.
do_uninstall() {
    local removed=0

    # 1. Strip the marker + wire block from hyprland.lua (if present).
    local marker="-- $PKG: managed by install.sh; safe to delete if you uninstall."
    if [[ -f "$USER_HYPR" ]] && grep -F -- "$marker" "$USER_HYPR" >/dev/null 2>&1; then
        if strip_wire_block "$USER_HYPR" "$marker"; then
            echo "==> Removed require block from $USER_HYPR"
            removed=1
        else
            echo "warning: failed to strip require block from $USER_HYPR" >&2
        fi
    fi

    # 2. Remove the binary and any symlink at the user bin dir.
    if [[ -e "$BIN_DIR/$PKG" && ! -L "$BIN_DIR/$PKG" ]]; then
        rm -f "$BIN_DIR/$PKG"
        echo "==> Removed $BIN_DIR/$PKG"
        removed=1
    fi
    if [[ -L "$BIN_DIR/$PKG" ]]; then
        rm -f "$BIN_DIR/$PKG"
        echo "==> Removed symlink $BIN_DIR/$PKG"
        removed=1
    fi

    # 4. Reload Hyprland if it's reachable.
    if command -v hyprctl >/dev/null 2>&1; then
        if hyprctl reload >/dev/null 2>&1; then
            echo "==> Hyprland reloaded"
            local errs
            errs=$(hyprctl configerrors 2>&1 || true)
            if [[ -n "$errs" ]]; then
                echo "==> WARNING: Hyprland reported config errors:"
                echo "$errs" | sed 's/^/    /'
            fi
        fi
    fi

    if [[ "$removed" -eq 0 ]]; then
        echo "==> Nothing to remove (already uninstalled?)"
    else
        echo
        echo "==> Done. Source directory left in place: $REPO_ROOT"
        echo "    Remove it manually if you no longer need it:"
        echo "      rm -rf '$REPO_ROOT'"
    fi
}

# ---------------------------------------------------------------------------
# install: build + drop files into the right places.
do_install() {
    local reload_needed=0

    # 1. Build ---------------------------------------------------------------
    echo "==> Building $PKG (release)"
    if ! command -v cargo >/dev/null 2>&1; then
        echo "error: cargo not found. Install Rust via:"
        echo "  mise install rust@stable"
        echo "  or https://rustup.rs/"
        exit 1
    fi
    (cd "$REPO_ROOT" && cargo build --release)

    # 2. Install binary ------------------------------------------------------
    mkdir -p "$BIN_DIR"
    echo "==> Installing binary to $BIN_DIR/$PKG"
    install -Dm0755 "$REPO_ROOT/target/release/$PKG" "$BIN_DIR/$PKG"

    # 3. Default config -----------------------------------------------------
    # Seed the user's config dir only if absent. User edits win on re-install.
    if [[ ! -e "$USER_CFG" ]]; then
        echo "==> Seeding user config at $USER_CFG"
        mkdir -p "$(dirname "$USER_CFG")"
        install -Dm0644 "$ASSETS/dock.toml" "$USER_CFG"
    else
        echo "==> User config already exists; leaving $USER_CFG alone"
    fi

    # 4. Hyprland snippet ---------------------------------------------------
    # jgdock.lua requires windowrules.lua and bindings.lua, so all
    # three must land together.
    mkdir -p "$HYPR_DIR"
    echo "==> Installing snippet to $SNIPPET"
    install -Dm0644 "$ASSETS/jgdock.lua" "$SNIPPET"
    echo "==> Installing rules to $SNIPPET_RULES"
    install -Dm0644 "$ASSETS/windowrules.lua" "$SNIPPET_RULES"
    echo "==> Installing bindings to $SNIPPET_BINDINGS"
    install -Dm0644 "$ASSETS/bindings.lua" "$SNIPPET_BINDINGS"

    # 5. Wire up Hyprland (best-effort) -------------------------------------
    # Per-user only: prepend $XDG_CONFIG_HOME/jgdock/?.lua to package.path
    # and require("jgdock"). The block is wrapped in a marker comment so
    # the uninstaller can find and remove it as a unit.
    local wire_block=$'package.path = (os.getenv("HOME") or "") .. "/.config/jgdock/?.lua;" .. package.path\nrequire("jgdock")'
    local marker="-- $PKG: managed by install.sh; safe to delete if you uninstall."
    local expected_first
    expected_first=$(printf '%s\n' "$wire_block" | head -n1)

    if [[ -f "$USER_HYPR" ]]; then
        if grep -F -- "$marker" "$USER_HYPR" >/dev/null 2>&1; then
            # Marker present. Check whether the wire block below it matches
            # what we'd write today. If yes, no-op. If no, migrate: strip
            # the old block and re-append the new one.
            local first_wire_line
            first_wire_line=$(awk -v m="$marker" '
                $0 == m { found = 1; next }
                found == 1 && $0 != "" { print; exit }
            ' "$USER_HYPR")
            if [[ "$first_wire_line" == "$expected_first" ]]; then
                echo "==> Hyprland config already wired (marker + matching block)"
                reload_needed=0
            else
                echo "==> Migrating wire block to current shape"
                if strip_wire_block "$USER_HYPR" "$marker"; then
                    reload_needed=1
                else
                    echo "warning: failed to strip old wire block" >&2
                fi
            fi
        fi
        if [[ "$reload_needed" -eq 1 ]] || ! grep -F -- "$marker" "$USER_HYPR" >/dev/null 2>&1; then
            # Append the marker + wire block. The block is N lines; printf
            # inserts a trailing newline after the last line.
            {
                printf '\n%s\n' "$marker"
                printf '%s\n' "$wire_block"
            } >> "$USER_HYPR"
            echo "==> Appended to $USER_HYPR:"
            printf '    %s\n' "$wire_block"
            reload_needed=1
        fi
    else
        echo
        echo "==> No $USER_HYPR found."
        echo "    Create one and add these lines to load the dock rules:"
        echo
        printf '    %s\n' "$wire_block"
        echo
        reload_needed=0
    fi

    # Reload only if we changed something AND Hyprland is reachable. A fresh
    # install on a machine without a running session shouldn't trigger anything.
    # Also check configerrors after reload: hyprctl reload doesn't validate Lua
    # syntax, so a bad edit can leave the session in an inconsistent state.
    if [[ "$reload_needed" -eq 1 ]] && command -v hyprctl >/dev/null 2>&1; then
        if hyprctl reload >/dev/null 2>&1; then
            echo "==> Hyprland reloaded"
            local errs
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
    echo "==> Done (user install)."
    echo "    Test: $PKG ls"
}

# Dispatch ------------------------------------------------------------------
case "$CMD" in
    install)   do_install ;;
    update)    do_update; do_install ;;
    uninstall) do_uninstall ;;
    *)         usage ;;
esac
