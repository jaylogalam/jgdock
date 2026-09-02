# jgdock

Slot-based dock manager for Hyprland on Omarchy (or any Arch/Hyprland box).

A dock is a slot — a rectangle on the screen with a name (`left`, `right`,
`center`, `full`, ...). Any focused window can be docked into any slot.
Once docked, `toggle <slot>` shows or hides that same window. There are no
app rules in the binary, no per-app TOML blocks, and no per-app Lua
window-rules.

```
                     jgdock
                       │
              ┌────────┴────────┐
              │                 │
          SLOT CONFIG       RUNTIME STATE
       (dock.toml)        (state.toml)
              │                 │
       left/right/etc.      slot → window address
              │                 │
              └────────┬────────┘
                       │
                currently focused
                     window
```

Workflow:

```text
Open any app
     ↓
Focus it
     ↓
SUPER + SHIFT + RIGHT         (or: jgdock dock right)
     ↓
App becomes the right dock
```

After that, `SUPER + RIGHT` (or `jgdock toggle right`) shows/hides the
right dock. The slot doesn't care whether the bound window is OMP, Oterm,
Telegram, Kitty, or Firefox — it's a window address.

## Install

```sh
git clone https://github.com/jaylogalam/omarchy-custom-docks.git ~/Projects/jgdock
cd ~/Projects/jgdock
./install.sh            # or: ./install.sh install
```

## Update (other devices)

```sh
cd ~/Projects/jgdock
./install.sh update
```

Fetches from `origin`, fast-forwards, and rebuilds + reinstalls. Refuses
if local changes are uncommitted or if the branch has diverged (resolve
manually with `git pull --rebase` first).

The installer:

1. Builds the binary with `cargo build --release`.
2. Installs the binary to `~/.local/bin/jgdock`.
3. Installs the packaged config to `~/.config/jgdock/dock.toml`; seeds
   the user location only if absent. If an existing file uses the legacy
   `[docks.<name>]` shape, it's moved aside (`dock.toml.pre-slot.bak.*`)
   and the new slot-based config is seeded. Existing slot-based configs
   are left alone.
4. Installs the Hyprland snippet at `~/.config/jgdock/jgdock.lua`
   (co-located with `dock.toml`). The loader requires `bindings.lua`;
   both land together.
5. Drops any legacy `windowrules.lua` left behind by older installs.
6. If `~/.config/hypr/hyprland.lua` exists, appends a marker + wire
   block: a 2-line `package.path` prepend + `require("jgdock")`.
7. If a Hyprland session is reachable, runs `hyprctl reload` and
   verifies `configerrors` is clean. Skipped if there's no running
   session.

User-only: refuses to run as root. There's no system install mode; copy
the repo to a user-owned path and run `./install.sh` there. Idempotent.

## Uninstall

```sh
./install.sh uninstall
```

Removes:

- The binary (`~/.local/bin/jgdock`).
- The Hyprland snippet (`~/.config/jgdock/jgdock.lua`,
  `bindings.lua`).
- Any legacy `windowrules.lua` from a previous version.
- The wire block + marker comment in `hyprland.lua`.

Then runs `hyprctl reload` and verifies `configerrors` is clean.

Does **not** delete:

- The source directory (`~/Projects/jgdock/`).
- The user config (`~/.config/jgdock/dock.toml`) — left in place; user
  edits win.
- The runtime state file (`~/.local/state/jgdock/state.toml`) — slot
  bindings.

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

## Usage

```sh
jgdock ls                  # list configured slots
jgdock dock   <slot>       # pin the focused window into slot geometry
jgdock undock              # unpin the focused window (clears its binding)
jgdock toggle <slot>       # show slot's window if hidden, hide if shown
```

Default keybindings (defined in `assets/bindings.lua`):

| Key                       | Action         |
|---------------------------|----------------|
| `SUPER + RIGHT`           | Toggle right   |
| `SUPER + SHIFT + RIGHT`   | Dock to right  |
| `SUPER + LEFT`            | Toggle left    |
| `SUPER + SHIFT + LEFT`    | Dock to left   |
| `SUPER + U`               | Undock focused |

`center` and `full` slots are not bound by default — uncomment them in
`bindings.lua` if you use those slots.

## Layout

```
jgdock/
├── Cargo.toml
├── Cargo.lock
├── src/
│   ├── main.rs       # CLI dispatch (clap)
│   ├── config.rs     # dock.toml parser (serde + toml, with arithmetic
│   │                 #   expression evaluator for monitor-relative
│   │                 #   dimensions)
│   ├── hypr.rs       # hyprctl IPC wrapper
│   ├── state.rs      # slot -> window-address state file
│   └── dock.rs       # dock / undock / toggle (state-driven)
├── assets/
│   ├── dock.toml             # default config (4 slots: right/left/center/full)
│   ├── jgdock.lua            # top-level loader: requires bindings.lua
│   └── bindings.lua         # keybindings
├── install.sh        # builds + installs everything
└── README.md
```

## Configuration

`~/.config/jgdock/dock.toml` defines slots. Each slot is a generic
position; it has no notion of which app fills it.

```toml
[slots.right]
x       = "monitor_w*2/3"   # right-third start
y       = 27
width   = "monitor_w/3-1"
height  = "monitor_h-28"

[slots.left]
x       = 0
y       = 27
width   = "monitor_w/3-1"
height  = "monitor_h-28"
```

Geometry axes accept either raw pixel integers (`y = 27`) or Hyprland
monitor-arithmetic expressions as strings (`width = "monitor_w/3-1"`).
The parser supports `+ - *`, integer `/` and `%`, unary minus,
parentheses, and the identifiers `monitor_w` / `monitor_h`. Anything
Hyprland itself understands is allowed; the parser evaluates against the
focused monitor's pixel dimensions at load time.

`stash` is the special workspace used to hide the slot's window when
it's toggled off. It defaults to `special:<slot_name>`. Each slot needs
its own stash — slots that share a stash will fight over who owns the
window.

## Adding a slot

Add a `[slots.<name>]` block to `~/.config/jgdock/dock.toml`. Add a
matching pair of bindings in `assets/bindings.lua`. Then
`./install.sh install` (or `./install.sh update` to pick up changes
from another machine) — the cargo build overwrites only the binary;
config edits in your `~/.config/jgdock/dock.toml` are preserved.

There is no app entry to add. The dock takes whatever window is focused
when you press the dock shortcut.

## Why Rust

Bash + jq + python3 worked, but the boolean/string mismatch in pin
idempotency bit us during smoke testing. Rust catches that class of bug
at compile time. The binary is also ~3× faster to start (~40 ms vs
~120 ms), which matters for keybind latency if you ever chain multiple
docks.

The shell-out to `hyprctl` is preserved for protocol parity — a future
optimization could talk the Hyprland IPC socket directly.

## Upstream

Source lives only in `~/Projects/jgdock/`. The runtime files (binary,
config, snippet, state) are installed under `~/.local/` and
`~/.config/` and are excluded by this repo's gitignore.