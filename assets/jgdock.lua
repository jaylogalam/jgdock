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
-- — copy this file (plus bindings.lua) to ~/.config/jgdock/ and add the
-- three lines above.
--
-- jgdock is window-based: there are no per-app window rules. The runtime
-- owns geometry (it queries dock.toml for slot positions and applies them
-- at dock-time). This loader only registers keybindings; edit bindings.lua
-- to add or change them.

require("bindings")