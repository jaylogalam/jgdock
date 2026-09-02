-- jgdock window rules.
--
-- Geometry (float, pin, size, move) for each dock declared in dock.toml.
-- Runtime behaviour (spawn, show/hide, mutex) lives in the `jgdock` binary;
-- this file is layout only. Kept separate from `bindings.lua` so each
-- can be edited without touching the other; both are loaded by jgdock.lua.
--
-- Right-third geometry matches the waybar (26 px) on the top edge.

o.window({ class = "^Omp$" }, {
    float = true,
    pin = true,
    size = { "(monitor_w/3-1)", "(monitor_h-28)" },
    move = { "(monitor_w-monitor_w/3)", "27" },
})

o.window({ class = "^Oterm$" }, {
    float = true,
    pin = true,
    size = { "(monitor_w/3-1)", "(monitor_h-28)" },
    move = { "(monitor_w-monitor_w/3)", "27" },
})

o.window({ class = "^org\\.telegram\\.desktop$" }, {
    float = true,
    pin = true,
    size = { "(monitor_w/3-1)", "(monitor_h-28)" },
    move = { "0", "27" },
    focus_on_activate = false,
})
