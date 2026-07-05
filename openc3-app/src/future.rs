//! Placeholders for planned functionality. These are intentionally NOT wired
//! into the CLI or GUI yet — they document the intended extension points from
//! the requirements (items 7 and 8) so the architecture leaves room for them.

#![allow(dead_code)]

use crate::context::Context;
use anyhow::{bail, Result};

/// Future: launch and keep alive host-side Python microservices (requirement
/// #7). These will run outside Docker, supervised by this application, using
/// the isolated Python runtime installed under `<root>/python`.
pub fn launch_host_microservices(_ctx: &Context) -> Result<()> {
    bail!("host Python microservice supervision is not implemented yet")
}

/// Future: act as an Iroh client/server to communicate with the host Python
/// microservices (requirement #8).
pub fn start_iroh_endpoint(_ctx: &Context) -> Result<()> {
    bail!("Iroh client/server transport is not implemented yet")
}
