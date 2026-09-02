mod config;
mod dock;
mod hypr;

use anyhow::{bail, Result};
use clap::{Parser as ClapParser, Subcommand};

const DEFAULT_CONFIG_ENV: &str = "OMARCHY_DOCK_CONFIG";

#[derive(ClapParser, Debug)]
#[command(version, about = "Config-driven dock manager for Hyprland")]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand, Debug)]
enum Cmd {
    /// List configured docks.
    Ls,
    /// Show dock (spawn if absent).
    Show   { name: String },
    /// Hide dock to its stash.
    Hide   { name: String },
    /// Show or hide based on current state.
    Toggle { name: String },
    /// Spawn only; do not show/hide existing.
    Spawn  { name: String },
    /// Cycle docks in slot, show next.
    Next   { slot: String },
}

fn config_path() -> std::path::PathBuf {
    if let Ok(p) = std::env::var(DEFAULT_CONFIG_ENV) {
        return std::path::PathBuf::from(p);
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
    std::path::PathBuf::from(home).join(".config/omarchy/dock.toml")
}

fn run() -> Result<()> {
    let cli = Cli::parse();
    let cfg_path = config_path();
    let cfg = config::Config::load(&cfg_path)?;

    match cli.cmd {
        Cmd::Ls => {
            println!("{:<12} {:<10} {:<22} {}", "NAME", "SLOT", "CLASS", "STASH");
            for (name, spec) in &cfg.docks {
                println!(
                    "{:<12} {:<10} {:<22} {}",
                    name, spec.slot, spec.class, spec.stash
                );
            }
        }
        Cmd::Show   { name } => require(&cfg, &name, || dock::show(&cfg, &name))?,
        Cmd::Hide   { name } => require(&cfg, &name, || dock::hide(&cfg.docks[&name]))?,
        Cmd::Toggle { name } => require(&cfg, &name, || dock::toggle(&cfg, &name))?,
        Cmd::Spawn  { name } => require(&cfg, &name, || dock::execute(&cfg, &name, dock::Op::Spawn))?,
        Cmd::Next   { slot } => dock::cycle(&cfg, &slot)?,
    }
    Ok(())
}

fn require<F>(cfg: &config::Config, name: &str, f: F) -> Result<()>
where F: FnOnce() -> Result<()> {
    if !cfg.docks.contains_key(name) {
        // bash version: exit 3 ("unknown dock").
        bail!("unknown dock: {}", name);
    }
    f()
}

fn main() {
    // Match the bash contract: clap's own parse errors print usage and exit 2
    // before run() is ever called, so anything reaching this branch is a
    // runtime error (config not found, hyprctl failed, unknown dock, etc.).
    if let Err(e) = run() {
        let msg = e.chain().map(|c| c.to_string()).collect::<Vec<_>>().join(": ");
        eprintln!("omarchy-dock: {}", msg);
        std::process::exit(1);
    }
}