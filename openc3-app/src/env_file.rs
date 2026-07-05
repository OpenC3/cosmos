//! Minimal `.env` file parsing. COSMOS ships a `.env` next to its
//! `compose.yaml`; `docker compose` reads it automatically, but a few
//! commands (cli/cliroot/util) need individual values to forward to the
//! container, so we parse it ourselves.

use anyhow::{Context, Result};
use std::collections::BTreeMap;
use std::path::Path;

/// Parse a `.env` file into an ordered key/value map. Lines that are blank or
/// start with `#` are ignored. Surrounding quotes on values are stripped.
pub fn parse(path: &Path) -> Result<BTreeMap<String, String>> {
    let contents = std::fs::read_to_string(path)
        .with_context(|| format!("reading env file {}", path.display()))?;
    Ok(parse_str(&contents))
}

pub fn parse_str(contents: &str) -> BTreeMap<String, String> {
    let mut map = BTreeMap::new();
    for line in contents.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let key = key.trim().to_string();
        let mut value = value.trim().to_string();
        if (value.starts_with('"') && value.ends_with('"') && value.len() >= 2)
            || (value.starts_with('\'') && value.ends_with('\'') && value.len() >= 2)
        {
            value = value[1..value.len() - 1].to_string();
        }
        map.insert(key, value);
    }
    map
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_basic() {
        let m = parse_str("# comment\nFOO=bar\n\nBAZ=\"qux\"\nNUM=42\n");
        assert_eq!(m.get("FOO").unwrap(), "bar");
        assert_eq!(m.get("BAZ").unwrap(), "qux");
        assert_eq!(m.get("NUM").unwrap(), "42");
        assert!(!m.contains_key("# comment"));
    }
}
