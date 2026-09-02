//! Runtime slot state — which window is bound to which slot.
//!
//! Distinct from `Config`, which only knows geometry + stash names. State is
//! written under `$XDG_STATE_HOME/jgdock/state.toml` (default
//! `~/.local/state/jgdock/state.toml`) and survives across calls so that
//! `toggle <slot>` can find a previously docked window after it's been
//! re-hidden or the user has changed focus.
//!
//! A missing or unreadable state file is treated as empty — the runtime
//! tolerates first-run, permission issues, and corruption by starting from
//! a clean slate and overwriting on the next mutation. That keeps `jgdock`
//! runnable in degraded environments (no write access to $HOME, etc.)
//! without blocking the user.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

/// slot name → Hyprland window address (`0x...`).
#[derive(Debug, Default, Serialize, Deserialize)]
pub struct State {
    #[serde(default)]
    pub slots: BTreeMap<String, String>,
}

impl State {
    /// Read the state file, or return an empty `State` if absent/unreadable.
    /// Corruption logs to stderr via `eprintln!` and degrades to empty —
    /// losing the binding is less harmful than refusing to launch.
    pub fn load(path: &Path) -> Self {
        let Ok(text) = std::fs::read_to_string(path) else {
            return Self::default();
        };
        match toml::from_str::<Self>(&text) {
            Ok(s)  => s,
            Err(e) => {
                eprintln!(
                    "jgdock: state file at {} failed to parse ({}); starting empty",
                    path.display(), e,
                );
                Self::default()
            }
        }
    }

    /// Persist atomically: write to a sibling `.tmp` and `rename` over the
    /// target so a crash mid-write doesn't leave a half-written TOML that
    /// would force the next call to clear the bindings.
    pub fn save(&self, path: &Path) -> Result<()> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .with_context(|| format!("creating state dir {}", parent.display()))?;
        }
        let body = toml::to_string(self).context("serialising jgdock state")?;
        let tmp = path.with_extension("toml.tmp");
        std::fs::write(&tmp, body)
            .with_context(|| format!("writing {}", tmp.display()))?;
        std::fs::rename(&tmp, path)
            .with_context(|| format!("renaming {} -> {}", tmp.display(), path.display()))?;
        Ok(())
    }

    pub fn bind(&mut self, slot: &str, address: &str) {
        self.slots.insert(slot.to_string(), address.to_string());
    }

    pub fn clear(&mut self, slot: &str) {
        self.slots.remove(slot);
    }
}

/// Default location: `$XDG_STATE_HOME/jgdock/state.toml`, falling back to
/// `$HOME/.local/state/jgdock/state.toml`.
pub fn default_path() -> PathBuf {
    let base = std::env::var("XDG_STATE_HOME")
        .ok()
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var("HOME").ok().map(|h| PathBuf::from(h).join(".local/state"))
        })
        .unwrap_or_else(|| PathBuf::from(".local/state"));
    base.join("jgdock").join("state.toml")
}