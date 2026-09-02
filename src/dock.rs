use crate::config::{Config, DockSpec};
use crate::hypr;
use anyhow::{Context, Result};
use std::process::Command;

extern "C" {
    fn setsid() -> i32;
}

fn libc_setsid() {
    unsafe { setsid(); }
}

#[derive(Debug)]
pub enum Op {
    Show,
    Hide,
    Toggle,
    Spawn,
}

/// Execute a dock operation. The caller has already resolved `name` against
/// the config.
pub fn execute(cfg: &Config, name: &str, op: Op) -> Result<()> {
    let spec = &cfg.docks[name];
    match op {
        Op::Spawn  => spawn_if_missing(spec),
        Op::Show   => show(cfg, name),
        Op::Hide   => hide(spec),
        Op::Toggle => toggle(cfg, name),
    }
}

pub fn show(cfg: &Config, name: &str) -> Result<()> {
    let spec = &cfg.docks[name];
    spawn_if_missing(spec)?;
    hide_mutex(cfg, name)?;

    let clients = hypr::list_clients()?;
    let cur_id  = hypr::active_workspace_id()?;

    if let Some(client) = hypr::first_match(&clients, &spec.class) {
        let on_stash = client.workspace.name == spec.stash;
        if !on_stash && client.pinned {
            // Already shown: just refocus.
            hypr::dispatch_focus(&client.address)?;
            return Ok(());
        }
        hypr::dispatch_move(&client.address, &cur_id.to_string(), false)?;
        hypr::dispatch_pin(&client.address)?;
        hypr::dispatch_focus(&client.address)?;
    }
    Ok(())
}

pub fn hide(spec: &DockSpec) -> Result<()> {
    let clients = hypr::list_clients()?;
    if let Some(client) = hypr::first_match(&clients, &spec.class) {
        // Idempotent: only dispatch if state actually changes.
        if client.pinned {
            hypr::dispatch_pin(&client.address)?;
        }
        if client.workspace.name != spec.stash {
            hypr::dispatch_move(&client.address, &spec.stash, false)?;
        }
    }
    Ok(())
}

pub fn toggle(cfg: &Config, name: &str) -> Result<()> {
    let spec = &cfg.docks[name];
    let clients = hypr::list_clients()?;
    let cur_id  = hypr::active_workspace_id()?;

    let Some(client) = hypr::first_match(&clients, &spec.class) else {
        // No window yet: spawn + show.
        return show(cfg, name);
    };

    let on_stash = client.workspace.name == spec.stash;
    let on_current_special = client.workspace.name == format!("special:{}", cur_id);

    if !on_stash && client.pinned && !on_current_special {
        // Shown on a real workspace -> hide.
        hide(spec)
    } else {
        // Stashed, on another workspace, or on a "special:N" workspace
        // whose name happens to mirror the active id.
        show(cfg, name)
    }
}

/// Cycle: hide whatever dock is currently pinned in `slot`, then show the
/// next one in config order. Wraps.
pub fn cycle(cfg: &Config, slot: &str) -> Result<()> {
    let order: Vec<&str> = cfg.docks
        .iter()
        .filter(|(_, s)| s.slot == slot)
        .map(|(n, _)| n.as_str())
        .collect();
    if order.is_empty() {
        anyhow::bail!("no docks in slot: {}", slot);
    }

    let clients = hypr::list_clients()?;
    let current_idx = order.iter().position(|n| {
        let class = &cfg.docks[*n].class;
        hypr::first_match(&clients, class).is_some_and(|c| c.pinned)
    });

    if let Some(i) = current_idx {
        let cur_name = order[i];
        hide(&cfg.docks[cur_name])?;
    }
    let next_name = order[current_idx.map_or(0, |i| (i + 1) % order.len())];
    show(cfg, next_name)
}

fn hide_mutex(cfg: &Config, name: &str) -> Result<()> {
    let partners: Vec<String> = cfg.docks[name].mutex.clone();
    if partners.is_empty() {
        return Ok(());
    }
    let clients = hypr::list_clients()?;
    for other in &partners {
        let Some(other_spec) = cfg.docks.get(other) else { continue };
        if let Some(client) = hypr::first_match(&clients, &other_spec.class) {
            if !client.pinned {
                continue;
            }
            hypr::dispatch_pin(&client.address)?;
            if client.workspace.name != other_spec.stash {
                hypr::dispatch_move(&client.address, &other_spec.stash, false)?;
            }
        }
    }
    Ok(())
}

fn spawn_if_missing(spec: &DockSpec) -> Result<()> {
    let clients = hypr::list_clients()?;
    if hypr::first_match(&clients, &spec.class).is_some() {
        return Ok(());
    }
    // Shell-split the command. This handles `setsid env -C "$HOME/Work" ...`
    // and similar without invoking a shell. Quoted paths aren't supported
    // (config commands must avoid whitespace in tokens).
    let parts: Vec<&str> = spec.command.split_whitespace().collect();
    if parts.is_empty() {
        return Ok(());
    }
    let mut cmd = Command::new(parts[0]);
    for arg in &parts[1..] {
        cmd.arg(arg);
    }
    // Detach from controlling terminal so the dock survives script exit.
    unsafe {
        use std::os::unix::process::CommandExt;
        cmd.pre_exec(|| {
            libc_setsid();
            Ok(())
        });
    }
    cmd.stdin(std::process::Stdio::null());
    cmd.stdout(std::process::Stdio::null());
    cmd.stderr(std::process::Stdio::null());
    let _child = cmd.spawn().context("spawning dock command")?;
    // Give Hyprland a beat to register the new window before callers query.
    std::thread::sleep(std::time::Duration::from_millis(150));
    Ok(())
}