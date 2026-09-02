-- jgdock keybindings.
--
-- Each slot defined in dock.toml gets two bindings:
--
--   SUPER + <direction>          toggle   — show if hidden, hide if shown
--   SUPER + SHIFT + <direction>  dock     — pin the focused window into the slot
--
-- The right/left bindings cover the two most common slots; center/full are
-- included for completeness but uncomment if you use them. Drop or rename
-- freely — the binary doesn't care about specific names, only that the
-- slot is defined in dock.toml.
--
-- `jgdock undock` removes a binding from any slot (whichever one owns the
-- focused window). It's exposed under SUPER + U as an escape hatch when a
-- dock gets stuck.

o.bind("SUPER + RIGHT",          "Toggle right dock",  "jgdock toggle right")
o.bind("SUPER + SHIFT + RIGHT",  "Dock to right",      "jgdock dock right")

o.bind("SUPER + LEFT",           "Toggle left dock",   "jgdock toggle left")
o.bind("SUPER + SHIFT + LEFT",   "Dock to left",       "jgdock dock left")

o.bind("SUPER + U",              "Undock focused",     "jgdock undock")

-- Optional: center and full slots. Uncomment if you've defined them in
-- dock.toml; the bindings do nothing without a matching slot entry.
-- o.bind("SUPER + C",              "Toggle center",      "jgdock toggle center")
-- o.bind("SUPER + SHIFT + C",      "Dock to center",     "jgdock dock center")
-- o.bind("SUPER + F",              "Toggle full",        "jgdock toggle full")
-- o.bind("SUPER + SHIFT + F",      "Dock to full",       "jgdock dock full")