# jgdock

Config-driven dock manager for Hyprland on Omarchy (or any Arch/Hyprland box).

Each dockable app (omp, oterm, telegram, ...) is one `[docks.<name>]` block in
`assets/dock.toml`. The Rust binary at `src/` handles spawn, show/hide, stash,
mutex between siblings. A Lua snippet at `assets/jgdock.lua` registers
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
2. Installs to `/usr/bin/jgdock` (system, root) or
   `~/.local/bin/jgdock` (user); always also creates the symlink at
   `~/.local/bin/jgdock`.
3. Installs the packaged config to `/etc/jgdock/dock.toml` (system) or
   `~/.config/jgdock/dock.toml` (user); seeds the user location only if
   absent — your edits are preserved on re-install.
4. Installs the Hyprland snippet at `/etc/hypr/jgdock.lua` (system) or
   `~/.config/hypr/jgdock.lua` (user).
5. If `~/.config/hypr/hyprland.lua` exists and isn't already wired, appends
   `require("hypr.jgdock")` (per-user) or
   `require("/etc/hypr/jgdock")` (system) with a marker comment.
6. If a Hyprland session is reachable, runs `hyprctl reload` and verifies
   `configerrors` is clean. Skipped if there's no running session (e.g.,
   fresh install before first login).

Idempotent — re-run any time. Re-running detects the marker comment and
won't duplicate the require line.

## Uninstall

```sh
./install.sh uninstall
```

This removes:

- The binary (`~/.local/bin/jgdock` and `/usr/bin/jgdock`)
- The Hyprland snippet (`~/.config/hypr/jgdock.lua` or `/etc/hypr/`)
- The `require()` line + marker comment in `hyprland.lua`
- The user config at `~/.config/jgdock/dock.toml` — **prompted** first; if
  you've hand-edited it, answer `n` to keep it

Then runs `hyprctl reload` and verifies `configerrors` is clean.

The script does **not** delete:

- The source directory (`~/Projects/omarchy-dock/`) — printed at the end
  so you can `rm -rf` it if you want
- The cargo registry cache (`~/.cargo/`) — shared with other Rust projects

## Why `require("hypr.jgdock")` works

Omarchy's bootstrap adds three roots to Lua's `package.path`:

```lua
~/.local/state/?.lua
~/.config/?.lua
$OMARCHY_PATH/?.lua
```

So `require("hypr.jgdock")` resolves to
`~/.config/hypr/jgdock.lua` — same convention Omarchy uses for its
own modules (`hypr.monitors`, `hypr.bindings`, etc.). No absolute paths, no
env vars, no symlinks.

For system installs (`/etc/hypr/`) the install prints an absolute
`require("/etc/hypr/jgdock.lua")` because `/etc/hypr` is not on the
default path.

## Usage

```sh
jgdock ls                # list configured docks
jgdock show   <name>     # show dock (spawn if absent)
jgdock hide   <name>     # hide to stash
jgdock toggle <name>     # show/hide based on state
jgdock spawn  <name>     # spawn only, don't touch state
jgdock next   <slot>     # cycle docks in slot
```

Default keybindings (defined in `assets/jgdock.lua`):

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
│   └── jgdock.lua   # window rules + bindings (require("hypr.jgdock"))
├── install.sh        # builds + installs everything
└── README.md
```

## Adding a dock

1. Add a `[docks.<name>]` block to `~/.config/jgdock/dock.toml`:

   ```toml
   [docks.btop]
   class   = "Btop"
   command = "kitty --class Btop -e btop"
   stash   = "special:btop"
   slot    = "left"
   mutex   = ["telegram"]   # auto-hide telegram when showing btop
   ```

2. Add a window rule to `assets/jgdock.lua` (geometry: size + position):

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
   o.bind("SUPER + B", "Toggle btop", "jgdock toggle btop")
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