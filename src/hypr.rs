use anyhow::{anyhow, Context, Result};
use serde::Deserialize;

/// A single Hyprland client window.
#[derive(Debug, Deserialize, Clone)]
pub struct Client {
    pub address  : String,
    pub pinned   : bool,
    pub floating: bool,
    pub workspace: Workspace,
}

#[derive(Debug, Deserialize, Clone)]
pub struct Workspace {
    pub id  : i64,
    pub name: String,
}

pub fn list_clients() -> Result<Vec<Client>> {
    let out = std::process::Command::new("hyprctl")
        .args(["clients", "-j"])
        .output()
        .context("spawning hyprctl clients -j")?;
    if !out.status.success() {
        return Err(anyhow!(
            "hyprctl clients -j failed: {}",
            String::from_utf8_lossy(&out.stderr)
        ));
    }
    let clients: Vec<Client> = serde_json::from_slice(&out.stderr)
        .or_else(|_| serde_json::from_slice(&out.stdout))
        .context("parsing hyprctl clients -j output")?;
    Ok(clients)
}

pub fn active_workspace_id() -> Result<i64> {
    let out = std::process::Command::new("hyprctl")
        .args(["activeworkspace", "-j"])
        .output()
        .context("spawning hyprctl activeworkspace -j")?;
    if !out.status.success() {
        return Err(anyhow!(
            "hyprctl activeworkspace -j failed: {}",
            String::from_utf8_lossy(&out.stderr)
        ));
    }
    let ws: Workspace = serde_json::from_slice(&out.stdout)
        .or_else(|_| serde_json::from_slice(&out.stderr))
        .context("parsing hyprctl activeworkspace -j output")?;
    Ok(ws.id)
}

/// Return the focused window's address, or `None` if no window is focused.
pub fn focused_address() -> Result<Option<String>> {
    let out = std::process::Command::new("hyprctl")
        .args(["activewindow", "-j"])
        .output()
        .context("spawning hyprctl activewindow -j")?;
    if !out.status.success() {
        return Err(anyhow!(
            "hyprctl activewindow -j failed: {}",
            String::from_utf8_lossy(&out.stderr)
        ));
    }
    // activewindow prints `{}` (empty object) when no window is focused; treat
    // that as None instead of a parse error.
    let v: serde_json::Value = serde_json::from_slice(&out.stdout)
        .or_else(|_| serde_json::from_slice(&out.stderr))
        .context("parsing hyprctl activewindow -j output")?;
    Ok(v.get("address").and_then(|a| a.as_str()).map(|s| s.to_string()))
}

/// All low-level dispatchers go through `hl.dispatch(...)`. Hyprland's Lua
/// parser expects table literals, so the helpers below format them inline.
///
/// Window-targeting dispatchers all take `{ window = "address:<hex>" }`.

pub fn pin(address: &str) -> Result<()> {
    dispatch(&format!(
        "hl.dsp.window.pin({{ window = \"address:{}\" }})",
        address
    ))
}

pub fn unpin(address: &str) -> Result<()> {
    dispatch(&format!(
        "hl.dsp.window.pin({{ window = \"address:{}\", action = \"unset\" }})",
        address
    ))
}

/// Ensure the window is floating.
///
/// `hl.dsp.window.float` `action` values 0–3 all toggle the float state
/// on Hyprland 0.56.x — there is no "force set" value. Calling it on an
/// already-floating window would tile it, which breaks the `toggle` show
/// path (the stashed window was already floating, so re-issuing the
/// dispatcher tiled it, and the subsequent `pin` was rejected with
/// "Window does not qualify to be pinned"). Skip the call when the
/// window is already floating.
pub fn float_enable(address: &str) -> Result<()> {
    let already = list_clients()?
        .iter()
        .find(|c| c.address == address)
        .map(|c| c.floating)
        .unwrap_or(false);
    if !already {
        dispatch(&format!(
            "hl.dsp.window.float({{ window = \"address:{}\", action = 0 }})",
            address
        ))?;
    }
    Ok(())
}

/// Move a window to a named workspace. `follow` switches focus to the new ws.
pub fn move_to_workspace(address: &str, workspace: &str, follow: bool) -> Result<()> {
    dispatch(&format!(
        "hl.dsp.window.move({{ window = \"address:{}\", workspace = \"{}\", follow = {} }})",
        address, workspace, follow,
    ))
}

/// Position a window at (x, y). Coordinates are forwarded verbatim to
/// Position a window at (x, y). Coordinates are pre-resolved pixel integers
/// (the config layer evaluates `monitor_w/3-1` etc. before we get here).
pub fn move_abs(address: &str, x: i64, y: i64) -> Result<()> {
    dispatch(&format!(
        "hl.dsp.window.move({{ window = \"address:{}\", x = {}, y = {} }})",
        address, x, y,
    ))
}

/// Resize a window to (w, h). Same pixel-integer contract as `move_abs`.
pub fn resize(address: &str, w: i64, h: i64) -> Result<()> {
    dispatch(&format!(
        "hl.dsp.window.resize({{ window = \"address:{}\", x = {}, y = {} }})",
        address, w, h,
    ))
}

pub fn focus(address: &str) -> Result<()> {
    dispatch(&format!(
        "hl.dsp.focus({{ window = \"address:{}\" }})",
        address
    ))
}

fn dispatch(spec: &str) -> Result<()> {
    let status = std::process::Command::new("hyprctl")
        .args(["dispatch", spec])
        .status()
        .with_context(|| format!("spawning hyprctl dispatch {}", spec))?;
    if !status.success() {
        return Err(anyhow!("hyprctl dispatch `{}` failed", spec));
    }
    Ok(())
}