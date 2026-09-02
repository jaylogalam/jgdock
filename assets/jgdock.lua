-- jgdock: Hyprland integration snippet.
--
-- Drop this into your Hyprland config by adding two lines to
-- ~/.config/hypr/hyprland.lua (after the Omarchy requires):
--
--   local home = os.getenv("HOME")
--   package.path = home .. "/.config/jgdock/?.lua;" .. package.path
--   require("jgdock")
--
-- The installer wires this up automatically with a marker comment so it
-- can be undone by ./install.sh uninstall. Manual installation works too
-- — copy this file to ~/.config/jgdock/jgdock.lua and add the three lines
-- above.
--
-- It registers:
--   * Window rules for the configured docks (float, pin, geometry)
--   * Keybindings for SUPER+T (oterm), SUPER+G (omp), SUPER+ALT+E (telegram)
--
-- This file is installed by jgdock's installer at:
--   * ~/.config/jgdock/jgdock.lua  (per-user; the only install location now)
--   * /etc/hypr/jgdock.lua         (system, requires absolute-path require)
--
-- To customize, edit this file after install, or copy it to your own path.

-- Window rules ------------------------------------------------------------
-- Runtime behaviour (spawn, show/hide, mutex) lives in `jgdock`,
-- configured in ~/.config/jgdock/dock.toml. This block is geometry only.

o.window({ class = "^Omp$" }, {
    float = true,
    pin = true,
    -- Right third of monitor, below the 26px waybar.
    size = { "(monitor_w/3-1)", "(monitor_h-28)" },
    move = { "(monitor_w-monitor_w/3)", "27" },
})

o.window({ class = "^Oterm$" }, {
    float = true,
    pin = true,
    -- Right third of monitor, below the 26px waybar.
    size = { "(monitor_w/3-1)", "(monitor_h-28)" },
    move = { "(monitor_w-monitor_w/3)", "27" },
})

o.window({ class = "^org\\.telegram\\.desktop$" }, {
    float = true,
    pin = true,
    -- Left third of monitor, below the 26px waybar.
    size = { "(monitor_w/3-1)", "(monitor_h-28)" },
    move = { "0", "27" },
    focus_on_activate = false,
})

-- Keybindings -------------------------------------------------------------

o.bind("SUPER + T",       "Toggle oterm",   "jgdock toggle oterm")
o.bind("SUPER + G",       "Toggle omp",     "jgdock toggle omp")
o.bind("SUPER + ALT + E", "Toggle telegram", "jgdock toggle telegram")