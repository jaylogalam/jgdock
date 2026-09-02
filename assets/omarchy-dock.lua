-- omarchy-dock: Hyprland integration snippet.
--
-- Drop this into your Hyprland config by adding ONE line to
-- ~/.config/hypr/hyprland.lua (after the Omarchy requires):
--
--   require("hypr.omarchy-dock")
--
-- It registers:
--   * Window rules for the configured docks (float, pin, geometry)
--   * Keybindings for SUPER+T (oterm), SUPER+G (omp), SUPER+ALT+E (telegram)
--
-- This file is installed by omarchy-dock's installer at:
--   * ~/.config/hypr/omarchy-dock.lua  (per-user)
--   * /etc/hypr/omarchy-dock.lua       (system, requires() requires absolute path)
--
-- To customize, edit this file after install, or copy it to your own path.

-- Window rules ------------------------------------------------------------
-- Runtime behaviour (spawn, show/hide, mutex) lives in `omarchy-dock`,
-- configured in ~/.config/omarchy/dock.toml. This block is geometry only.

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

o.bind("SUPER + T",       "Toggle oterm",   "omarchy-dock toggle oterm")
o.bind("SUPER + G",       "Toggle omp",     "omarchy-dock toggle omp")
o.bind("SUPER + ALT + E", "Toggle telegram", "omarchy-dock toggle telegram")