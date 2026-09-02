use anyhow::{anyhow, Context, Result};
use serde::Deserialize;

/// A single Hyprland client window.
#[derive(Debug, Deserialize, Clone)]
pub struct Client {
    pub address  : String,
    pub class    : String,
    pub pinned   : bool,
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

/// Hyprland 0.56.2's `hl.dsp.window.pin({ state = true|false })` ignores the
/// `state` argument and always toggles. We dispatch unconditionally; the
/// idempotency check above ensures we only call this on transitions.
pub fn dispatch_pin(address: &str) -> Result<()> {
    dispatch(&format!(
        "hl.dsp.window.pin({{ window = \"address:{}\" }})",
        address
    ))
}

pub fn dispatch_move(address: &str, workspace: &str, follow: bool) -> Result<()> {
    // Always quote the workspace: identifiers like `special:foo` confuse
    // Hyprland's Lua parser without quotes.
    dispatch(&format!(
        "hl.dsp.window.move({{ window = \"address:{}\", workspace = \"{}\", follow = {} }})",
        address, workspace, follow,
    ))
}

pub fn dispatch_focus(address: &str) -> Result<()> {
    dispatch(&format!(
        "hl.dsp.focus({{ window = \"address:{}\" }})",
        address
    ))
}

fn dispatch(spec: &str) -> Result<()> {
    let out = std::process::Command::new("hyprctl")
        .args(["dispatch", spec])
        .output()
        .with_context(|| format!("spawning hyprctl dispatch {}", spec))?;
    if !out.status.success() {
        return Err(anyhow!(
            "hyprctl dispatch `{}` failed: {}",
            spec,
            String::from_utf8_lossy(&out.stderr)
        ));
    }
    Ok(())
}

/// Find the first client matching `class`. Returns `None` if absent.
pub fn first_match<'a>(clients: &'a [Client], class: &str) -> Option<&'a Client> {
    clients.iter().find(|c| c.class == class)
}