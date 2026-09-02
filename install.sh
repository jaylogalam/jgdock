#!/usr/bin/env bash
# jgdock installer.
#
# Builds from source and installs:
#   * Binary at $BIN_DIR/jgdock (system /usr/bin or user ~/.local/bin)
#   * Symlink at ~/.local/bin/jgdock pointing at the binary
#   * Default config at $CFG_DIR/jgdock/dock.toml (skipped if user already has one)
#   * Hyprland snippet at $CFG_DIR/jgdock/jgdock.lua (per-user, loaded via
#     require("jgdock") after a package.path prepend written into
#     hyprland.lua) or /etc/hypr/jgdock.lua (system, absolute require)
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
# The wire block is detected by its marker comment AND its first-line content,
# so old single-line `require("hypr.jgdock")` blocks from a prior version
# are migrated automatically.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ASSETS="$REPO_ROOT/assets"
PKG="jgdock"
CMD="${1:-install}"

usage() {
    cat <<EOF
usage: $0 [install|update|uninstall]
  install    Build + install from local source (default).
  update     Fast-forward merge from origin, then build + install.
  uninstall  Remove binary, symlink, snippet, and require block. Prompts
             before removing the user config; source dir is left alone.
EOF
    exit 2
}

[[ "$CMD" == "-h" || "$CMD" == "--help" || "$CMD" == "help" ]] && usage

# ---------------------------------------------------------------------------
# Strip the marker + the wire block that follows it from hyprland.lua.
# The wire block is 1 line (system) or 2 lines (per-user), always followed
# by a blank separator. Drops the marker and everything up to and including
# the first blank line that follows.
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
    if ! command -v git >/dev/null 2>&1; then
        echo "error: git not found; cannot update." >&2
        exit 1
    fi
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
# uninstall: remove the binary, symlink, Hyprland snippet, and the require
# block from hyprland.lua. Asks before touching the user config (which may
# contain hand-edited dock specs). Leaves the source directory and cargo
# registry cache alone — those are not ours to delete.
do_uninstall() {
    if [[ $EUID -eq 0 ]]; then
        BIN_DIR="/usr/bin"
        CFG_DIR="/etc"
        HYPR_DIR="/etc/hypr"
    else
        BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
        CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
        # Mirror do_install: per-user snippet lives at
        # ~/.config/jgdock/jgdock.lua, not ~/.config/hypr/jgdock.lua.
        HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/jgdock"
    fi
    local user_bin="${XDG_BIN_HOME:-$HOME/.local/bin}"
    local user_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/jgdock/dock.toml"
    local user_hypr="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua"

    local removed=0

    # 1. Strip the marker + wire block from hyprland.lua (if present).
    local marker="-- $PKG: managed by install.sh; safe to delete if you uninstall."
    if [[ -f "$user_hypr" ]] && grep -F -- "$marker" "$user_hypr" >/dev/null 2>&1; then
        if strip_wire_block "$user_hypr" "$marker"; then
            echo "==> Removed require block from $user_hypr"
            removed=1
        else
            echo "warning: failed to strip require block from $user_hypr" >&2
        fi
    fi

    # 2. Remove the binary (system path).
    if [[ -e "$BIN_DIR/$PKG" ]]; then
        rm -f "$BIN_DIR/$PKG"
        echo "==> Removed $BIN_DIR/$PKG"
        removed=1
    fi

    # 3. Remove the symlink (user path), if it's a symlink.
    if [[ -L "$user_bin/$PKG" ]]; then
        rm -f "$user_bin/$PKG"
        echo "==> Removed symlink $user_bin/$PKG"
        removed=1
    fi

    # 4. Remove the Hyprland snippet.
    # if [[ -f "$HYPR_DIR/jgdock.lua" ]]; then
    #     rm -f "$HYPR_DIR/jgdock.lua"
    #     echo "==> Removed $HYPR_DIR/jgdock.lua"
    #     removed=1
    # fi

    # 5. Optionally remove the user config. Default config (installed but
    # never edited) is safe to remove without prompting; for safety we
    # always prompt — the user may have hand-edited it.
    # if [[ -f "$user_cfg" ]]; then
    #     echo
    #     printf "Remove user config at %s? [y/N] " "$user_cfg"
    #     local ans
    #     read -r ans
    #     if [[ "$ans" =~ ^[Yy]$ ]]; then
    #         rm -f "$user_cfg"
    #         echo "==> Removed $user_cfg"
    #         removed=1
    #     else
    #         echo "==> Keeping $user_cfg"
    #     fi
    # fi

    # 6. Reload Hyprland if it's reachable.
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
    # Resolve install paths: system-wide if root, per-user otherwise.
    if [[ $EUID -eq 0 ]]; then
        BIN_DIR="/usr/bin"
        CFG_DIR="/etc"
        HYPR_DIR="/etc/hypr"
        INSTALL_KIND="system"
    else
        BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
        CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
        # Snippet lives at $CFG_DIR/jgdock/jgdock.lua (co-located with
        # dock.toml). It's not under hypr/ because Omarchy's Lua loader
        # only adds $XDG_CONFIG_HOME/?.lua, not arbitrary subdirs. The
        # installer instead prepends $XDG_CONFIG_HOME/jgdock/?.lua to
        # package.path at the top of hyprland.lua so `require("jgdock")`
        # resolves here.
        HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/jgdock"
        INSTALL_KIND="user"
    fi

    local user_bin="${XDG_BIN_HOME:-$HOME/.local/bin}"
    local user_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/jgdock/dock.toml"
    local user_hypr="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua"
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
    local bin_target="$BIN_DIR/$PKG"
    echo "==> Installing binary to $bin_target"
    install -Dm0755 "$REPO_ROOT/target/release/$PKG" "$bin_target"

    # Symlink for ~/.local/bin so both paths work.
    mkdir -p "$user_bin"
    if [[ ! -e "$user_bin/$PKG" ]]; then
        echo "==> Symlinking $user_bin/$PKG -> $bin_target"
        ln -s "$bin_target" "$user_bin/$PKG"
    fi

    # 3. Default config -----------------------------------------------------
    # Install a default at the system location (or per-user), and seed the
    # user's config dir only if absent. User edits win on re-install.
    local system_cfg="$CFG_DIR/jgdock/dock.toml"
    echo "==> Installing default config to $system_cfg"
    install -Dm0644 "$ASSETS/dock.toml" "$system_cfg"

    if [[ ! -e "$user_cfg" ]]; then
        echo "==> Seeding user config at $user_cfg"
        mkdir -p "$(dirname "$user_cfg")"
        install -Dm0644 "$ASSETS/dock.toml" "$user_cfg"
    else
        echo "==> User config already exists; leaving $user_cfg alone"
    fi

    # 4. Hyprland snippet ---------------------------------------------------
    local snippet="$HYPR_DIR/jgdock.lua"
    echo "==> Installing Hyprland snippet to $snippet"
    install -Dm0644 "$ASSETS/jgdock.lua" "$snippet"

    # 5. Wire up Hyprland (best-effort) -------------------------------------
    # Per-user writes a 2-line block: package.path prepend + require.
    # System installs use a 1-line absolute require since /etc/hypr isn't
    # on package.path. The block is wrapped in a marker comment so the
    # uninstaller can find and remove it as a unit.
    local wire_block
    if [[ "$INSTALL_KIND" == "system" ]]; then
        wire_block='require("/etc/hypr/jgdock")'
    else
        wire_block=$'package.path = (os.getenv("HOME") or "") .. "/.config/jgdock/?.lua;" .. package.path\nrequire("jgdock")'
    fi

    local marker="-- $PKG: managed by install.sh; safe to delete if you uninstall."
    local expected_first
    expected_first=$(printf '%s\n' "$wire_block" | head -n1)

    if [[ -f "$user_hypr" ]]; then
        if grep -F -- "$marker" "$user_hypr" >/dev/null 2>&1; then
            # Marker present. Check whether the wire block below it matches
            # what we'd write today. If yes, no-op. If no, migrate: strip
            # the old block and re-append the new one.
            local first_wire_line
            first_wire_line=$(awk -v m="$marker" '
                $0 == m { found = 1; next }
                found == 1 && $0 != "" { print; exit }
            ' "$user_hypr")
            if [[ "$first_wire_line" == "$expected_first" ]]; then
                echo "==> Hyprland config already wired (marker + matching block)"
                reload_needed=0
            else
                echo "==> Migrating wire block to current shape"
                if strip_wire_block "$user_hypr" "$marker"; then
                    reload_needed=1
                else
                    echo "warning: failed to strip old wire block" >&2
                fi
            fi
        fi
        if [[ "$reload_needed" -eq 1 ]] || ! grep -F -- "$marker" "$user_hypr" >/dev/null 2>&1; then
            # Append the marker + wire block. The block is N lines; printf
            # inserts a trailing newline after the last line.
            {
                printf '\n%s\n' "$marker"
                printf '%s\n' "$wire_block"
            } >> "$user_hypr"
            echo "==> Appended to $user_hypr:"
            printf '    %s\n' "$wire_block"
            reload_needed=1
        fi
    else
        echo
        echo "==> No $user_hypr found."
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
    echo "==> Done ($INSTALL_KIND install)."
    echo "    Test: $PKG ls"
}

# Dispatch ------------------------------------------------------------------
case "$CMD" in
    install)   do_install ;;
    update)    do_update; do_install ;;
    uninstall) do_uninstall ;;
    *)         usage ;;
esac
