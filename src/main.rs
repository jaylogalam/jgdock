mod config;
mod dock;
mod hypr;
mod state;

use anyhow::{bail, Result};
use clap::{Parser as ClapParser, Subcommand};

const DEFAULT_CONFIG_ENV: &str = "JGDOCK_CONFIG";

#[derive(ClapParser, Debug)]
#[command(version, about = "Slot-based dock manager for Hyprland")]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand, Debug)]
enum Cmd {
    /// List configured slots.
    Ls,
    /// Bind the focused window to a slot: float + size + position + pin + focus.
    Dock   { slot: String },
    /// Unpin the focused window. Keeps its current workspace.
    Undock,
    /// Show the slot's window if hidden, hide if shown.
    Toggle { slot: String },
}

fn config_path() -> std::path::PathBuf {
    if let Ok(p) = std::env::var(DEFAULT_CONFIG_ENV) {
        return std::path::PathBuf::from(p);
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
    std::path::PathBuf::from(home).join(".config/jgdock/dock.toml")
}

fn run() -> Result<()> {
    let cli = Cli::parse();
    let cfg_path = config_path();
    let cfg = config::Config::load(&cfg_path)?;
    let state_path = state::default_path();

    match cli.cmd {
        Cmd::Ls => {
            println!("{:<10} {:<14} {}", "SLOT", "STASH", "GEOMETRY (x,y,w,h)");
            for (name, spec) in &cfg.slots {
                println!(
                    "{:<10} {:<14} {},{},{},{}",
                    name, spec.stash,
                    spec.x, spec.y, spec.width, spec.height,
                );
            }
            eprintln!("(monitor: {}x{})", cfg.monitor_w, cfg.monitor_h);
        }
        Cmd::Dock   { slot } => require(&cfg, &slot, || {
            dock::dock(&cfg, &slot, &state_path)
        })?,
        Cmd::Undock          => dock::undock(&state_path)?,
        Cmd::Toggle { slot } => require(&cfg, &slot, || {
            dock::toggle(&cfg, &slot, &state_path)
        })?,
    }
    Ok(())
}

fn require<F>(cfg: &config::Config, slot: &str, f: F) -> Result<()>
where F: FnOnce() -> Result<()> {
    if !cfg.slots.contains_key(slot) {
        bail!("unknown slot: {}", slot);
    }
    f()
}

fn main() {
    if let Err(e) = run() {
        let msg = e.chain().map(|c| c.to_string()).collect::<Vec<_>>().join(": ");
        eprintln!("jgdock: {}", msg);
        std::process::exit(1);
    }
}