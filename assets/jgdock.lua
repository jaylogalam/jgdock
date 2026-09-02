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
-- — copy this file (plus jgdock-rules.lua and jgdock-bindings.lua) to
-- ~/.config/jgdock/ and add the three lines above.
--
-- This loader requires the two side files, each of which can be edited
-- independently:
--   * jgdock-rules.lua    window rules (float, pin, geometry)
--   * jgdock-bindings.lua keybindings
--
-- It registers:
--   * Window rules for the configured docks
--   * Keybindings for SUPER+T (oterm), SUPER+G (omp), SUPER+ALT+E (telegram)

require("windowrules")
require("bindings")
