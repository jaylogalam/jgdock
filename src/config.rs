use anyhow::{anyhow, Context, Result};
use serde::Deserialize;
use std::collections::BTreeMap;
use std::path::Path;

#[derive(Debug, Deserialize, Clone)]
pub struct DockSpec {
    pub class  : String,
    pub command: String,
    pub stash  : String,
    #[serde(default)]
    pub slot   : String,
    #[serde(default)]
    pub mutex  : Vec<String>,
}

#[derive(Debug, Deserialize)]
pub struct Config {
    pub docks: BTreeMap<String, DockSpec>,
}

impl Config {
    pub fn load(path: &Path) -> Result<Self> {
        let text = std::fs::read_to_string(path)
            .with_context(|| format!("reading {}", path.display()))?;
        let cfg: Config = toml::from_str(&text)
            .with_context(|| format!("parsing {}", path.display()))?;
        for (name, spec) in &cfg.docks {
            if spec.class.is_empty() || spec.command.is_empty() {
                return Err(anyhow!("docks.{}: `class` and `command` are required", name));
            }
            if spec.stash.is_empty() {
                return Err(anyhow!("docks.{}: `stash` is required", name));
            }
            // Validate that every mutex partner exists.
            for m in &spec.mutex {
                if !cfg.docks.contains_key(m) {
                    return Err(anyhow!(
                        "docks.{}.mutex references unknown dock `{}`",
                        name, m
                    ));
                }
            }
        }
        Ok(cfg)
    }
}