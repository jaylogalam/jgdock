-- jgdock keybindings.
--
-- Default toggle bindings for the docks declared in dock.toml. Kept separate
-- from `windowrules.lua` so window geometry and input mappings can be edited
-- independently; both are loaded by jgdock.lua.

o.bind("SUPER + T",       "Toggle oterm",   "jgdock toggle oterm")
o.bind("SUPER + G",       "Toggle omp",     "jgdock toggle omp")
o.bind("SUPER + ALT + E", "Toggle telegram", "jgdock toggle telegram")
