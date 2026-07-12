//! OpenC3 COSMOS native launcher and manager.
//!
//! A single cross-platform binary that installs and manages a complete COSMOS
//! environment (Docker engine, isolated Python runtime, COSMOS containers).
//! It launches a graphical control panel by default and exposes the full
//! `openc3.sh` command set on the command line for headless use.

mod bridge;
mod cli;
mod commands;
mod context;
mod docker;
mod download;
mod enroll;
mod env_file;
mod hostfiles;
mod future;
mod install;
mod monitor;
mod operator;
mod process;
mod util;

#[cfg(feature = "gui")]
mod gui;

#[cfg(feature = "gui")]
mod tray;

use anyhow::Result;
use clap::Parser;
use cli::{Cli, Command, InstallTarget};
use context::Context;

fn main() {
    let cli = Cli::parse();
    if let Err(e) = run(cli) {
        eprintln!("error: {e:#}");
        std::process::exit(1);
    }
}

fn run(cli: Cli) -> Result<()> {
    // No subcommand: launch the GUI by default unless asked to be headless.
    let Some(command) = cli.command else {
        return default_action(cli.root, cli.headless, cli.enterprise);
    };

    let ctx = Context::new(cli.root.clone(), cli.enterprise)?;

    match command {
        Command::Install(args) => match args.target {
            InstallTarget::All => install::all(&ctx),
            InstallTarget::Prerequisites => install::prerequisites(&ctx),
            InstallTarget::Docker => install::docker(&ctx),
            InstallTarget::Python => install::python(&ctx),
            InstallTarget::Cosmos { tag } => install::cosmos(&ctx, &tag),
        },
        Command::Build { flags } => commands::build(&ctx, &flags),
        Command::Run => commands::run(&ctx),
        Command::Start { flags } => commands::start(&ctx, &flags),
        Command::Stop => commands::stop(&ctx),
        Command::Restart => commands::restart(&ctx),
        Command::Status => commands::status(&ctx),
        Command::Logs { service, follow } => commands::logs(&ctx, service.as_deref(), follow),
        Command::Monitor => commands::monitor_loop(&ctx),
        Command::Cleanup { local, force } => commands::cleanup(&ctx, local, force),
        Command::Cli { args } => commands::cli(&ctx, &args, false),
        Command::Cliroot { args } => commands::cli(&ctx, &args, true),
        Command::Test { args } => commands::test(&ctx, &args),
        Command::Upgrade { tag, preview } => commands::upgrade(&ctx, &tag, preview),
        Command::Util(args) => util::run(&ctx, &args.command),
        Command::Microservices => {
            let mut op = operator::MicroserviceOperator::new(
                ctx.paths.python.clone(),
                ctx.paths.microservices.clone(),
            );
            // openc3-app is a client of the COSMOS bridge_microservice hub. It
            // uses its own persistent identity and enrolls (auto over local
            // Docker, or via a configured ticket) to obtain the hub ticket.
            // Auto-enroll happens in the operator loop once COSMOS has been up a
            // while (bounded retries, re-armed on restart).
            let connect_ctx = ctx.clone();
            let ready_ctx = ctx.clone();
            op.set_bridge_connector(
                Box::new(move || enroll::connect_bridge(&connect_ctx)),
                Box::new(move || {
                    monitor::snapshot(&ready_ctx)
                        .ok()
                        .and_then(|s| s.iter().filter_map(|c| c.uptime()).min())
                }),
            );
            op.run();
            Ok(())
        }
        Command::BridgeEnroll { token } => {
            let bridge = enroll::enroll_with_token(&ctx, &token)?;
            println!("Enrolled with bridge '{bridge}'.");
            Ok(())
        }
        Command::Gui => launch_gui(cli.root, cli.enterprise),
    }
}

#[cfg(feature = "gui")]
fn default_action(root: Option<std::path::PathBuf>, headless: bool, enterprise: bool) -> Result<()> {
    if headless {
        headless_summary(root, enterprise)
    } else {
        launch_gui(root, enterprise)
    }
}

#[cfg(not(feature = "gui"))]
fn default_action(root: Option<std::path::PathBuf>, _headless: bool, enterprise: bool) -> Result<()> {
    // No GUI compiled in: behave as the headless summary.
    headless_summary(root, enterprise)
}

#[cfg(feature = "gui")]
fn launch_gui(root: Option<std::path::PathBuf>, enterprise: bool) -> Result<()> {
    gui::launch(root, enterprise)
}

#[cfg(not(feature = "gui"))]
fn launch_gui(_root: Option<std::path::PathBuf>, _enterprise: bool) -> Result<()> {
    anyhow::bail!("This build was compiled without GUI support. Use a subcommand (see --help).")
}

/// Headless default: print a short status summary and a usage hint.
fn headless_summary(root: Option<std::path::PathBuf>, enterprise: bool) -> Result<()> {
    let ctx = Context::new(root, enterprise)?;
    println!("OpenC3 COSMOS");
    println!("  root:    {}", ctx.paths.root.display());
    let runtime_line = match ctx.runtime.as_ref() {
        Some(r) if context::container_engine_running() => format!("{} (running)", r.engine),
        Some(r) => format!("{} (installed, not running)", r.engine),
        None => "none (run `openc3 install docker`)".to_string(),
    };
    println!("  runtime: {runtime_line}");
    println!(
        "  python:  {}",
        if ctx.paths.python_installed() {
            "installed"
        } else {
            "not installed (run `openc3 install python`)"
        }
    );
    println!(
        "  cosmos:  {}",
        if ctx.paths.cosmos_installed() {
            "installed"
        } else {
            "not installed (run `openc3 install cosmos`)"
        }
    );
    if ctx.paths.cosmos_installed() && ctx.runtime.is_some() {
        if let Ok(statuses) = monitor::snapshot(&ctx) {
            println!("  status:  {}", monitor::summarize(&statuses));
        }
    }
    println!("\nRun `openc3 --help` for all commands.");
    Ok(())
}
