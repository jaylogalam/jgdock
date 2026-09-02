# omarchy-dock

Config-driven dock manager for Hyprland on Omarchy (or any Arch/Hyprland box).

Each dockable app (omp, oterm, telegram, ...) is one `[docks.<name>]` block in
`assets/dock.toml`. The Rust binary at `src/` handles spawn, show/hide, stash,
mutex between siblings. A Lua snippet at `assets/hyprland.lua` registers the
window rules (float, pin, geometry) and keybindings; load it from your Hyprland
config with one `require()` line.

## Install (current machine)

```sh
cd ~/Projects/omarchy-dock
./install.sh
```

Then add to `~/.config/hypr/hyprland.lua` (after the Omarchy requires):

```lua
require((os.getenv("HOME") or "") .. "/.local/share/omarchy-dock/hyprland")
```

…and run `hyprctl reload`.

## Install (fresh machine)

```sh
git clone <this repo> ~/Projects/omarchy-dock
cd ~/Projects/omarchy-dock
./install.sh
```

The script:

1. Builds the binary with `cargo build --release`.
2. Installs to `/usr/bin/omarchy-dock` (system) or `~/.local/bin/omarchy-dock`
   (user); always also creates the symlink at `~/.local/bin/omarchy-dock`.
3. Installs the packaged config to `/etc/omarchy/dock.toml` (system) or
   `~/.config/omarchy/dock.toml` (user); seeds the user location only if
   absent — your edits are preserved on re-install.
4. Installs the Hyprland snippet at `/usr/share/omarchy-dock/hyprland.lua`
   (system) or `~/.local/share/omarchy-dock/hyprland.lua` (user).
5. Prints the `require()` line you need to add.

Idempotent — re-run any time.

## Usage

```sh
omarchy-dock ls                # list configured docks
omarchy-dock show   <name>     # show dock (spawn if absent)
omarchy-dock hide   <name>     # hide to stash
omarchy-dock toggle <name>     # show/hide based on state
omarchy-dock spawn  <name>     # spawn only, don't touch state
omarchy-dock next   <slot>     # cycle docks in slot
```

Default keybindings (defined in `assets/hyprland.lua`):

| Key           | Action              |
|---------------|---------------------|
| `SUPER + T`   | Toggle oterm        |
| `SUPER + G`   | Toggle omp          |
| `SUPER + ALT + E` | Toggle telegram |

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
│   ├── dock.toml     # default config (3 docks: omp, oterm, telegram)
│   └── hyprland.lua  # window rules + bindings (require() this)
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

2. Add a window rule to `assets/hyprland.lua` (geometry: size + position):

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
   o.bind("SUPER + B", "Toggle btop", "omarchy-dock toggle btop")
   ```

4. Rebuild: `cd ~/Projects/omarchy-dock && ./install.sh`. Re-run, no
   reinstall of the snippet needed (the cargo build overwrites only the
   binary; assets are copied fresh).

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
ignored by this repo's gitignore.