//! `openc3 util ...` — equivalents of the legacy `openc3_util.sh` helpers.

use crate::cli::UtilCommand;
use crate::context::Context;
use crate::docker::{self, IMAGES};
use anyhow::{Context as _, Result};
use base64::Engine;
use sha2::{Digest, Sha256};
use std::path::Path;
use std::process::Command;

pub fn run(ctx: &Context, cmd: &UtilCommand) -> Result<()> {
    match cmd {
        UtilCommand::Encode { string } => {
            println!("{}", base64::engine::general_purpose::STANDARD.encode(string.as_bytes()));
            Ok(())
        }
        UtilCommand::Hash { string } => {
            let mut hasher = Sha256::new();
            hasher.update(string.as_bytes());
            println!("{:x}", hasher.finalize());
            Ok(())
        }
        UtilCommand::Pull {
            tag,
            repo,
            namespace,
            suffix,
        } => pull(
            ctx,
            tag,
            repo.as_deref().unwrap_or("docker.io"),
            namespace.as_deref().unwrap_or("openc3inc"),
            suffix.as_deref().unwrap_or(""),
        ),
        UtilCommand::Save {
            repo,
            namespace,
            tag,
            suffix,
        } => save(ctx, repo, namespace, tag, suffix.as_deref().unwrap_or("")),
        UtilCommand::Load { tag, suffix } => load(
            ctx,
            tag.as_deref().unwrap_or("latest"),
            suffix.as_deref().unwrap_or(""),
        ),
        UtilCommand::Tag {
            repo1,
            repo2,
            namespace1,
            tag1,
            namespace2,
            tag2,
            suffix,
        } => tag_images(
            ctx,
            repo1,
            repo2,
            namespace1,
            tag1,
            namespace2.as_deref().unwrap_or(namespace1),
            tag2.as_deref().unwrap_or(tag1),
            suffix.as_deref().unwrap_or(""),
        ),
        UtilCommand::Push {
            repo,
            namespace,
            tag,
            suffix,
        } => push(ctx, repo, namespace, tag, suffix.as_deref().unwrap_or("")),
        UtilCommand::Clean => clean(&ctx.paths.root),
    }
}

fn engine(ctx: &Context) -> Result<Command> {
    Ok(docker::engine_cmd(ctx.runtime()?))
}

fn pull(ctx: &Context, tag: &str, repo: &str, ns: &str, suffix: &str) -> Result<()> {
    for image in IMAGES {
        let mut cmd = engine(ctx)?;
        cmd.arg("pull").arg(format!("{repo}/{ns}/{image}{suffix}:{tag}"));
        docker::run(cmd)?;
    }
    Ok(())
}

fn save(ctx: &Context, repo: &str, ns: &str, tag: &str, suffix: &str) -> Result<()> {
    let tmp = ctx.paths.root.join("tmp");
    std::fs::create_dir_all(&tmp).ok();
    for image in IMAGES {
        let reference = format!("{repo}/{ns}/{image}{suffix}:{tag}");
        let mut pull = engine(ctx)?;
        pull.arg("pull").arg(&reference);
        docker::run(pull)?;

        let out = tmp.join(format!("{image}{suffix}-{tag}.tar"));
        let mut save = engine(ctx)?;
        save.arg("save").arg(&reference).arg("-o").arg(&out);
        docker::run(save)?;
    }
    Ok(())
}

fn load(ctx: &Context, tag: &str, suffix: &str) -> Result<()> {
    let tmp = ctx.paths.root.join("tmp");
    for image in IMAGES {
        let path = tmp.join(format!("{image}{suffix}-{tag}.tar"));
        let mut cmd = engine(ctx)?;
        cmd.arg("load").arg("-i").arg(&path);
        docker::run(cmd)?;
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn tag_images(
    ctx: &Context,
    repo1: &str,
    repo2: &str,
    ns1: &str,
    tag1: &str,
    ns2: &str,
    tag2: &str,
    suffix: &str,
) -> Result<()> {
    for image in IMAGES {
        let src = format!("{repo1}/{ns1}/{image}{suffix}:{tag1}");
        let dst = format!("{repo2}/{ns2}/{image}{suffix}:{tag2}");
        let mut cmd = engine(ctx)?;
        cmd.arg("tag").arg(&src).arg(&dst);
        docker::run(cmd)?;
    }
    Ok(())
}

fn push(ctx: &Context, repo: &str, ns: &str, tag: &str, suffix: &str) -> Result<()> {
    for image in IMAGES {
        let mut cmd = engine(ctx)?;
        cmd.arg("push").arg(format!("{repo}/{ns}/{image}{suffix}:{tag}"));
        docker::run(cmd)?;
    }
    Ok(())
}

/// Remove node_modules and coverage directories from the source tree.
fn clean(root: &Path) -> Result<()> {
    fn walk(dir: &Path) -> Result<()> {
        for entry in std::fs::read_dir(dir)? {
            let entry = entry?;
            let path = entry.path();
            if path.is_dir() {
                let name = entry.file_name();
                if name == "node_modules" || name == "coverage" {
                    println!("Removing {}", path.display());
                    std::fs::remove_dir_all(&path)
                        .with_context(|| format!("removing {}", path.display()))?;
                } else {
                    walk(&path)?;
                }
            }
        }
        Ok(())
    }
    walk(root)
}
