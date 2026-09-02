# jsg-custom-dock

Config-driven dock manager for Hyprland on Omarchy (or any Arch/Hyprland box).

Each dockable app (omp, oterm, telegram, ...) is one `[docks.<name>]` block in
`assets/dock.toml`. The Rust binary at `src/` handles spawn, show/hide, stash,
mutex between siblings. A Lua snippet at `assets/jsg-custom-dock.lua` registers
the window rules (float, pin, geometry) and keybindings; load it from your
Hyprland config with one `require()` line.

## Install

```sh
git clone https://github.com/jaylogalam/omarchy-custom-docks.git ~/Projects/omarchy-dock
cd ~/Projects/omarchy-dock
./install.sh            # or: ./install.sh install
```

## Update (other devices)

On a machine that already has the repo cloned:

```sh
cd ~/Projects/omarchy-dock
./install.sh update
```

This fetches from `origin`, fast-forward merges, and rebuilds + reinstalls.
Refuses to run if there are local uncommitted changes or if the branch has
diverged (resolve manually with `git pull --rebase` first).

The installer:

1. Builds the binary with `cargo build --release`.
2. Installs to `/usr/bin/jsg-custom-dock` (system, root) or
   `~/.local/bin/jsg-custom-dock` (user); always also creates the symlink at
   `~/.local/bin/jsg-custom-dock`.
3. Installs the packaged config to `/etc/omarchy/dock.toml` (system) or
   `~/.config/omarchy/dock.toml` (user); seeds the user location only if
   absent — your edits are preserved on re-install.
4. Installs the Hyprland snippet at `/etc/hypr/jsg-custom-dock.lua` (system) or
   `~/.config/hypr/jsg-custom-dock.lua` (user).
5. If `~/.config/hypr/hyprland.lua` exists and isn't already wired, appends
   `require("hypr.jsg-custom-dock")` (per-user) or
   `require("/etc/hypr/jsg-custom-dock")` (system) with a marker comment.
6. If a Hyprland session is reachable, runs `hyprctl reload` and verifies
   `configerrors` is clean. Skipped if there's no running session (e.g.,
   fresh install before first login).

Idempotent — re-run any time. Re-running detects the marker comment and
won't duplicate the require line.

## Uninstall

Remove the marker comment block from `~/.config/hypr/hyprland.lua`, then
remove the package files:

```sh
rm -f ~/.local/bin/jsg-custom-dock \
      ~/.config/hypr/jsg-custom-dock.lua \
      ~/.config/omarchy/dock.toml
hyprctl reload
```

(For system installs: `/usr/bin/jsg-custom-dock`,
`/etc/hypr/jsg-custom-dock.lua`, `/etc/omarchy/dock.toml`, with `sudo`.)

## Why `require("hypr.jsg-custom-dock")` works

Omarchy's bootstrap adds three roots to Lua's `package.path`:

```lua
~/.local/state/?.lua
~/.config/?.lua
$OMARCHY_PATH/?.lua
```

So `require("hypr.jsg-custom-dock")` resolves to
`~/.config/hypr/jsg-custom-dock.lua` — same convention Omarchy uses for its
own modules (`hypr.monitors`, `hypr.bindings`, etc.). No absolute paths, no
env vars, no symlinks.

For system installs (`/etc/hypr/`) the install prints an absolute
`require("/etc/hypr/jsg-custom-dock.lua")` because `/etc/hypr` is not on the
default path.

## Usage

```sh
jsg-custom-dock ls                # list configured docks
jsg-custom-dock show   <name>     # show dock (spawn if absent)
jsg-custom-dock hide   <name>     # hide to stash
jsg-custom-dock toggle <name>     # show/hide based on state
jsg-custom-dock spawn  <name>     # spawn only, don't touch state
jsg-custom-dock next   <slot>     # cycle docks in slot
```

Default keybindings (defined in `assets/jsg-custom-dock.lua`):

| Key              | Action         |
|------------------|----------------|
| `SUPER + T`      | Toggle oterm   |
| `SUPER + G`      | Toggle omp     |
| `SUPER + ALT + E`| Toggle telegram |

## Layout

```
omarchy-dock/
├── Cargo.toml
├── Cargo.lock
├── src/
│   ├── main.rs       # CLI dispatch (clap)
│   ├── config.rs     # dock.toml parser (serde + toml)
│   ├── hypr.rs       # hyprctl IPC wrapper
│   └── dock.rs       # state machine (show/hide/toggle/cycle)
├── assets/
│   ├── dock.toml             # default config (3 docks: omp, oterm, telegram)
│   └── jsg-custom-dock.lua   # window rules + bindings (require("hypr.jsg-custom-dock"))
├── install.sh        # builds + installs everything
└── README.md
```

## Adding a dock

1. Add a `[docks.<name>]` block to `~/.config/omarchy/dock.toml`:

   ```toml
   [docks.btop]
   class   = "Btop"
   command = "kitty --class Btop -e btop"
   stash   = "special:btop"
   slot    = "left"
   mutex   = ["telegram"]   # auto-hide telegram when showing btop
   ```

2. Add a window rule to `assets/jsg-custom-dock.lua` (geometry: size + position):

   ```lua
   o.window({ class = "^Btop$" }, {
       float = true,
       pin = true,
       size = { "(monitor_w/3-1)", "(monitor_h-28)" },
       move = { "0", "27" },
   })
   ```

3. (Optional) add a keybinding in the same file:

   ```lua
   o.bind("SUPER + B", "Toggle btop", "jsg-custom-dock toggle btop")
   ```

4. Rebuild: `cd ~/Projects/omarchy-dock && ./install.sh` (or `./install.sh update`
   if you changed things on another machine and want to pull them). The cargo
   build overwrites only the binary; assets are copied fresh on every install.

## Why Rust

Bash + jq + python3 worked, but the boolean/string mismatch in pin
idempotency bit us during smoke testing. Rust catches that class of bug at
compile time. The binary is also ~3× faster to start (~40 ms vs ~120 ms),
which matters for keybind latency if you ever chain multiple docks.

The shell-out to `hyprctl` is preserved for protocol parity — a future
optimization could talk the Hyprland IPC socket directly.

## Upstream

Source lives only in `~/Projects/omarchy-dock/`. The runtime files (binary,
config, snippet) are installed under `~/.local/` and `~/.config/` and are
excluded by this repo's gitignore.