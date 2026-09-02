use crate::config::{Config, SlotSpec};
use crate::hypr;
use crate::state::State;
use anyhow::{anyhow, Result};
use std::path::Path;
use std::time::Duration;

/// Settle time after a single Hyprland dispatcher call. Most dispatchers
/// return `ok` before the compositor applies the state change — a
/// follow-up dispatcher targeting the same window can race the in-flight
/// update and silently fail. 500ms is empirically required on Hyprland
/// 0.56.x; shorter values (200ms, 80ms) intermittently lost the float,
/// resize, move, or pin step. Used between every dispatcher pair.
const DISPATCH_SETTLE: Duration = Duration::from_millis(500);

/// Settle time after a workspace switch (especially `special:` →
/// regular). 1500ms is empirically required to make `move_to_workspace`
/// from a special workspace settle before subsequent position
/// dispatchers fire; shorter windows let Hyprland silently lose focus
/// on the moved window and the float/resize/move/pin chain ends up
/// targeting the wrong window.
const WORKSPACE_SETTLE: Duration = Duration::from_millis(1500);

/// Bind the currently-focused window to `slot`: float + resize + move +
/// pin + focus, then record the binding in the runtime state file.
///
/// Steps:
///   1. Resolve the focused window's address.
///   2. Drop any prior binding this slot had (unpin if the previous
///      occupant is still around).
///   3. Move the window onto the active workspace and re-focus.
///   4. Make it floating (and wait for the state to settle).
///   5. Resize + move it into the slot's geometry.
///   6. Pin it.
///   7. Persist `slot -> address`.
pub fn dock(cfg: &Config, slot: &str, state_path: &Path) -> Result<()> {
    let spec = &cfg.slots[slot];
    let address = hypr::focused_address()?
        .ok_or_else(|| anyhow!("no focused window to dock"))?;

    let mut state = State::load(state_path);
    release_existing(&state, slot, &address);
    state.bind(slot, &address);

    let cur_id = hypr::active_workspace_id()?;
    // Focus first: position-mode dispatchers (`move`, `resize`) operate
    // on the active window and ignore any `window` field on Hyprland
    // 0.56.x. Re-focusing is also needed after `move_to_workspace`,
    // which drops focus on the moved window.
    hypr::focus(&address)?;
    std::thread::sleep(DISPATCH_SETTLE);
    hypr::move_to_workspace(&address, &cur_id.to_string(), false)?;
    std::thread::sleep(WORKSPACE_SETTLE);
    hypr::focus(&address)?;
    std::thread::sleep(DISPATCH_SETTLE);
    hypr::float_enable(&address)?;
    std::thread::sleep(DISPATCH_SETTLE);
    apply_geometry(&address, spec)?;
    hypr::pin(&address)?;
    state.save(state_path)?;
    Ok(())
}

/// Unpin the focused window. Keeps its current workspace and clears any
/// recorded binding for it (if it's the bound window for some slot). No-op
/// if the focused window is not pinned or there is no focused window.
pub fn undock(state_path: &Path) -> Result<()> {
    let Some(address) = hypr::focused_address()? else {
        return Ok(());
    };
    let clients = hypr::list_clients()?;
    let mut state = State::load(state_path);

    if let Some(c) = clients.iter().find(|c| c.address == address) {
        if c.pinned {
            hypr::unpin(&address)?;
        }
    }
    // Drop any slot binding that points at this address.
    let bound_to: Vec<String> = state.slots.iter()
        .filter_map(|(s, a)| (a == &address).then(|| s.clone()))
        .collect();
    for s in bound_to {
        state.clear(&s);
    }
    state.save(state_path)?;
    Ok(())
}

/// Show or hide the slot's bound window based on its current state.
///
/// State is in two places:
///   * The runtime state file maps `slot -> window_address`.
///   * Hyprland tells us whether that window still exists and whether it's
///     currently pinned.
///
/// `dock` happens when there is no bound window yet (or the bound window
/// has been closed). Otherwise we flip the bound window's visibility.
pub fn toggle(cfg: &Config, slot: &str, state_path: &Path) -> Result<()> {
    let spec = &cfg.slots[slot];
    let mut state = State::load(state_path);
    let clients = hypr::list_clients()?;

    let Some(address) = state.slots.get(slot).cloned() else {
        return dock(cfg, slot, state_path);
    };
    let Some(occ) = clients.iter().find(|c| c.address == address).cloned() else {
        // Bound window is gone — drop the stale binding and dock whatever
        // is currently focused.
        state.clear(slot);
        state.save(state_path)?;
        return dock(cfg, slot, state_path);
    };

    if occ.pinned {
        hide_address(&occ.address, &spec.stash)?;
    } else {
        hypr::focus(&occ.address)?;
        std::thread::sleep(DISPATCH_SETTLE);
        let cur_id = hypr::active_workspace_id()?;
        hypr::move_to_workspace(&occ.address, &cur_id.to_string(), false)?;
        std::thread::sleep(WORKSPACE_SETTLE);
        show_address(&occ.address, spec)?;
    }
    Ok(())
}

/// Send a window to its stash and unpin it. Idempotent. Re-focuses the
/// window between unpin and move because `hl.dsp.window.pin(..., unset)`
/// drops focus on Hyprland 0.56.x; subsequent `move_to_workspace`
/// dispatchers target the active window, not the one we asked for.
fn hide_address(address: &str, stash: &str) -> Result<()> {
    let clients = hypr::list_clients()?;
    if let Some(c) = clients.iter().find(|c| c.address == address) {
        if c.pinned {
            hypr::unpin(address)?;
            std::thread::sleep(DISPATCH_SETTLE);
            hypr::focus(address)?;
            std::thread::sleep(DISPATCH_SETTLE);
        }
        if c.workspace.name != stash {
            hypr::move_to_workspace(address, stash, false)?;
        }
    }
    Ok(())
}

/// Float + resize + move + pin. Used by `toggle` to redisplay a
/// previously-bound window that has since moved or resized. The caller is
/// expected to have already moved the window to the active workspace and
/// waited `WORKSPACE_SETTLE` so focus on the moved window has settled.
fn show_address(address: &str, spec: &SlotSpec) -> Result<()> {
    hypr::focus(address)?;
    std::thread::sleep(DISPATCH_SETTLE);
    hypr::float_enable(address)?;
    std::thread::sleep(DISPATCH_SETTLE);
    apply_geometry(address, spec)?;
    hypr::pin(address)?;
    Ok(())
}

fn apply_geometry(address: &str, spec: &SlotSpec) -> Result<()> {
    hypr::resize(address, spec.width, spec.height)?;
    std::thread::sleep(DISPATCH_SETTLE);
    hypr::move_abs(address, spec.x, spec.y)?;
    std::thread::sleep(DISPATCH_SETTLE);
    Ok(())
}

/// If `slot` already binds to a different live window, unpin that window
/// so it doesn't shadow the new occupant. Best-effort: pin state is
/// queried via Hyprland; a missing or already-hidden binding is fine.
fn release_existing(state: &State, slot: &str, new_address: &str) {
    let Some(prev) = state.slots.get(slot) else { return };
    if prev == new_address {
        return;
    }
    let Ok(clients) = hypr::list_clients() else { return };
    let Some(c) = clients.iter().find(|c| c.address == *prev) else {
        return;
    };
    if c.pinned {
        let _ = hypr::unpin(prev);
    }
}