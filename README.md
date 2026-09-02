# jgdock

Config-driven dock manager for Hyprland on Omarchy (or any Arch/Hyprland box).

Each dockable app (omp, oterm, telegram, ...) is one `[docks.<name>]` block in
`assets/dock.toml`. The Rust binary at `src/` handles spawn, show/hide, stash,
mutex between siblings. A Lua snippet at `assets/jgdock.lua` registers
the window rules (float, pin, geometry) and keybindings; load it from your
Hyprland config with one `require()` line.

## Install

```sh
git clone https://github.com/jaylogalam/omarchy-custom-docks.git ~/Projects/jgdock
cd ~/Projects/jgdock
./install.sh            # or: ./install.sh install
```

## Update (other devices)

On a machine that already has the repo cloned:

```sh
cd ~/Projects/jgdock
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
   `~/.config/jgdock/jgdock.lua` (per-user; co-located with `dock.toml`).
5. If `~/.config/hypr/hyprland.lua` exists, appends a marker + wire block:
   per-user writes a 2-line `package.path` prepend + `require("jgdock")`,
   system writes a 1-line `require("/etc/hypr/jgdock")`. Migrates older
   `require("hypr.jgdock")` blocks from a previous install automatically.
6. If a Hyprland session is reachable, runs `hyprctl reload` and verifies
   `configerrors` is clean. Skipped if there's no running session (e.g.,
  fresh install before first login).

Idempotent — re-run any time. Re-running detects the marker + first wire
line and won't duplicate the wire block.

## Uninstall

```sh
./install.sh uninstall
```

This removes:

- The binary (`~/.local/bin/jgdock` and `/usr/bin/jgdock`)
- The Hyprland snippet (`~/.config/jgdock/jgdock.lua` or `/etc/hypr/`)
- The wire block + marker comment in `hyprland.lua` (the 2-line
  `package.path` prepend + `require("jgdock")` for per-user installs)
- The user config at `~/.config/jgdock/dock.toml` — **prompted** first; if
  you've hand-edited it, answer `n` to keep it

Then runs `hyprctl reload` and verifies `configerrors` is clean.

The script does **not** delete:

- The source directory (`~/Projects/jgdock/`) — printed at the end
  so you can `rm -rf` it if you want
- The cargo registry cache (`~/.cargo/`) — shared with other Rust projects

## How `require("jgdock")` resolves

Omarchy's bootstrap adds three roots to Lua's `package.path`:

```lua
~/.local/state/?.lua
~/.config/?.lua
$OMARCHY_PATH/?.lua
```

None of those is `~/.config/jgdock/?.lua`, so `require("jgdock")` would
fail by default. The installer fixes this by prepending a fourth root
at the top of `hyprland.lua`:

```lua
package.path = (os.getenv("HOME") or "") .. "/.config/jgdock/?.lua;" .. package.path
require("jgdock")
```

After the prepend, `require("jgdock")` resolves to
`~/.config/jgdock/jgdock.lua` (where the snippet lives, next to
`dock.toml`). The prepend is safe to repeat — each install re-detects
the existing block by its marker comment and skips the append.

For system installs (`/etc/hypr/`) the installer writes a 1-line
`require("/etc/hypr/jgdock")` instead, because `/etc/hypr` is not on
`package.path` and shouldn't be.

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
jgdock/
├── Cargo.toml
├── Cargo.lock
├── src/
│   ├── main.rs       # CLI dispatch (clap)
│   ├── config.rs     # dock.toml parser (serde + toml)
│   ├── hypr.rs       # hyprctl IPC wrapper
│   └── dock.rs       # state machine (show/hide/toggle/cycle)
├── assets/
│   ├── dock.toml             # default config (3 docks: omp, oterm, telegram)
│   └── jgdock.lua   # window rules + bindings (loaded as require("jgdock"))
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

4. Rebuild: `cd ~/Projects/jgdock && ./install.sh` (or `./install.sh update`
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

Source lives only in `~/Projects/jgdock/`. The runtime files (binary,
config, snippet) are installed under `~/.local/` and `~/.config/` and are
excluded by this repo's gitignore.