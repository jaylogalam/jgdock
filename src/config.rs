use anyhow::{anyhow, bail, Context, Result};
use serde::Deserialize;
use std::collections::BTreeMap;
use std::path::Path;

/// Hyprland-monitor arithmetic expression, evaluated at load time against
/// the active monitor's dimensions into a concrete pixel integer. Examples:
///
///   * `0`, `27`                       → raw pixels
///   * `"monitor_w/3-1"`               → current monitor width / 3 - 1
///   * `"monitor_h-28"`                → current monitor height - 28
///   * `"monitor_w*2/3"`               → start of right third on a 3-column layout
///
/// We support integers, the identifiers `monitor_w` / `monitor_h`, the
/// operators `+ - *`, integer `/` and `%` (floor division), unary minus, and
/// parentheses. That's enough for every example used in the default slots
/// without pulling in a full expression-evaluator crate.
#[derive(Debug, Deserialize, Clone)]
#[serde(untagged)]
pub enum Dim {
    Px(i64),
    Expr(String),
}

/// Resolved slot spec with pixel-integer geometry. `Dim::Expr` is evaluated
/// once at config load against the active monitor and converted to
/// `Dim::Px`. The runtime only ever sees integers.
#[derive(Debug, Clone)]
pub struct SlotSpec {
    pub x     : i64,
    pub y     : i64,
    pub width : i64,
    pub height: i64,
    pub stash : String,
}

#[derive(Debug)]
pub struct Config {
    pub slots: BTreeMap<String, SlotSpec>,
    /// Monitor dimensions used to resolve expressions. Kept around so we can
    /// recompute when the user changes monitors between calls. For now we
    /// capture once at load.
    pub monitor_w: i64,
    pub monitor_h: i64,
}

/// Active monitor size from `hyprctl monitors -j`. Returns the first focused
/// monitor's logical width/height.
pub fn active_monitor_size() -> Result<(i64, i64)> {
    let out = std::process::Command::new("hyprctl")
        .args(["monitors", "-j"])
        .output()
        .context("spawning hyprctl monitors -j")?;
    if !out.status.success() {
        return Err(anyhow!(
            "hyprctl monitors -j failed: {}",
            String::from_utf8_lossy(&out.stderr)
        ));
    }
    let v: serde_json::Value = serde_json::from_slice(&out.stdout)
        .or_else(|_| serde_json::from_slice(&out.stderr))
        .context("parsing hyprctl monitors -j output")?;
    let monitors = v.as_array()
        .ok_or_else(|| anyhow!("hyprctl monitors -j: expected JSON array"))?;
    let focused = monitors.iter()
        .find(|m| m.get("focused").and_then(|f| f.as_bool()).unwrap_or(false))
        .or_else(|| monitors.first())
        .ok_or_else(|| anyhow!("no monitors reported by Hyprland"))?;
    let w = focused.get("width").and_then(|w| w.as_i64())
        .ok_or_else(|| anyhow!("monitor width missing or non-integer"))?;
    let h = focused.get("height").and_then(|h| h.as_i64())
        .ok_or_else(|| anyhow!("monitor height missing or non-integer"))?;
    Ok((w, h))
}

impl Config {
    pub fn load(path: &Path) -> Result<Self> {
        let text = std::fs::read_to_string(path)
            .with_context(|| format!("reading {}", path.display()))?;
        let raw: RawConfig = toml::from_str(&text)
            .with_context(|| format!("parsing {}", path.display()))?;
        if raw.slots.is_empty() {
            return Err(anyhow!("no [slots.*] blocks defined"));
        }
        let (monitor_w, monitor_h) = active_monitor_size()?;

        let mut slots: BTreeMap<String, SlotSpec> = BTreeMap::new();
        for (name, raw_spec) in raw.slots {
            let stash = if raw_spec.stash.is_empty() {
                format!("special:{}", name)
            } else if !raw_spec.stash.starts_with("special:") {
                return Err(anyhow!(
                    "slots.{}: stash must be a special workspace (start with `special:`, got `{}`)",
                    name, raw_spec.stash
                ));
            } else {
                raw_spec.stash.clone()
            };
            let x      = resolve_dim("x",      &name, &raw_spec.x,      monitor_w, monitor_h)?;
            let y      = resolve_dim("y",      &name, &raw_spec.y,      monitor_w, monitor_h)?;
            let width  = resolve_dim("width",  &name, &raw_spec.width,  monitor_w, monitor_h)?;
            let height = resolve_dim("height", &name, &raw_spec.height, monitor_w, monitor_h)?;
            slots.insert(name, SlotSpec { x, y, width, height, stash });
        }
        Ok(Config { slots, monitor_w, monitor_h })
    }
}

#[derive(Debug, Deserialize)]
struct RawConfig {
    slots: BTreeMap<String, RawSlot>,
}

#[derive(Debug, Deserialize)]
struct RawSlot {
    x: Dim,
    y: Dim,
    width: Dim,
    height: Dim,
    #[serde(default)]
    stash: String,
}

fn resolve_dim(axis: &str, slot: &str, dim: &Dim, mw: i64, mh: i64) -> Result<i64> {
    let v = match dim {
        Dim::Px(n) => *n,
        Dim::Expr(s) => ExprParser::new(s, mw, mh)
            .eval()
            .with_context(|| format!("slots.{}.{}: invalid expression `{}`", slot, axis, s))?,
    };
    if v < 0 {
        bail!("slots.{}.{}: expression resolved to negative value ({})", slot, axis, v);
    }
    Ok(v)
}

// ---------------------------------------------------------------------------
// Tiny Hyprland-style expression evaluator.
//
// Grammar:
//   expr     = term (('+' | '-') term)*
//   term     = factor (('*' | '/' | '%') factor)*
//   factor   = '-' factor | atom
//   atom     = number | ident | '(' expr ')'
//   number   = digit+
//   ident    = 'monitor_w' | 'monitor_h'
//
// All arithmetic is i64. `/` is integer division toward zero (Rust default).
// `%` follows the same rule.
// ---------------------------------------------------------------------------

struct ExprParser<'a> {
    src: &'a [u8],
    pos: usize,
    mw : i64,
    mh : i64,
}

impl<'a> ExprParser<'a> {
    fn new(src: &'a str, mw: i64, mh: i64) -> Self {
        Self { src: src.as_bytes(), pos: 0, mw, mh }
    }

    fn eval(&mut self) -> Result<i64> {
        self.skip_ws();
        let v = self.parse_expr()?;
        self.skip_ws();
        if self.pos < self.src.len() {
            bail!("unexpected character `{}`", self.src[self.pos] as char);
        }
        Ok(v)
    }

    fn parse_expr(&mut self) -> Result<i64> {
        let mut v = self.parse_term()?;
        loop {
            self.skip_ws();
                match self.peek() {
                    Some(b'+') => { self.pos += 1; v += self.parse_term()?; }
                    Some(b'-') => { self.pos += 1; v -= self.parse_term()?; }
                    _ => return Ok(v),
                }
        }
    }

    fn parse_term(&mut self) -> Result<i64> {
        let mut v = self.parse_factor()?;
        loop {
            self.skip_ws();
            match self.peek() {
                Some(b'*') => { self.pos += 1; v *= self.parse_factor()?; }
                Some(b'/') => {
                    self.pos += 1;
                    let rhs = self.parse_factor()?;
                    if rhs == 0 { bail!("division by zero"); }
                    v /= rhs;
                }
                Some(b'%') => {
                    self.pos += 1;
                    let rhs = self.parse_factor()?;
                    if rhs == 0 { bail!("modulo by zero"); }
                    v %= rhs;
                }
                _ => return Ok(v),
            }
        }
    }

    fn parse_factor(&mut self) -> Result<i64> {
        self.skip_ws();
        if self.peek() == Some(b'-') {
            self.pos += 1;
            return Ok(-self.parse_factor()?);
        }
        if self.peek() == Some(b'+') {
            self.pos += 1;
            return self.parse_factor();
        }
        self.parse_atom()
    }

    fn parse_atom(&mut self) -> Result<i64> {
        self.skip_ws();
        match self.peek() {
            Some(b'(') => {
                self.pos += 1;
                let v = self.parse_expr()?;
                self.skip_ws();
                match self.peek() {
                    Some(b')') => { self.pos += 1; Ok(v) }
                    _ => bail!("missing `)`"),
                }
            }
            Some(b'0'..=b'9') => {
                let start = self.pos;
                while let Some(b'0'..=b'9') = self.peek() {
                    self.pos += 1;
                }
                let s = std::str::from_utf8(&self.src[start..self.pos])
                    .expect("digits are ASCII");
                s.parse::<i64>().map_err(|e| anyhow!("bad number `{}`: {}", s, e))
            }
            Some(b'a'..=b'z' | b'A'..=b'Z' | b'_') => {
                let start = self.pos;
                while let Some(b'a'..=b'z' | b'A'..=b'Z' | b'_' | b'0'..=b'9') = self.peek() {
                    self.pos += 1;
                }
                let s = std::str::from_utf8(&self.src[start..self.pos])
                    .expect("ident is ASCII");
                match s {
                    "monitor_w" => Ok(self.mw),
                    "monitor_h" => Ok(self.mh),
                    other       => bail!("unknown identifier `{}`", other),
                }
            }
            Some(c) => bail!("unexpected character `{}`", c as char),
            None    => bail!("unexpected end of expression"),
        }
    }

    fn peek(&self) -> Option<u8> {
        self.src.get(self.pos).copied()
    }

    fn skip_ws(&mut self) {
        while let Some(b' ' | b'\t' | b'\n' | b'\r') = self.peek() {
            self.pos += 1;
        }
    }
}