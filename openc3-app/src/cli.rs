//! Command line interface definition.
//!
//! The subcommands here mirror the functionality of the legacy `openc3.sh`
//! shell script plus the new installer functions described in the
//! requirements.

use clap::{Args, Parser, Subcommand};
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(
    name = "openc3",
    version,
    about = "OpenC3 COSMOS native launcher and manager",
    long_about = "Installs and manages a complete OpenC3 COSMOS environment: a Docker \
                  engine, an isolated Python runtime, and the COSMOS containers themselves. \
                  Runs as a GUI by default or fully headless from the command line."
)]
pub struct Cli {
    /// Application root directory. Installed components (python/, cosmos/, bin/)
    /// live in subfolders here. Defaults to the directory containing the
    /// executable, overridable with OPENC3_APP_HOME.
    #[arg(long, global = true, value_name = "DIR")]
    pub root: Option<PathBuf>,

    /// Run without launching the GUI. The GUI is on by default when no
    /// subcommand is given; any subcommand implies headless operation.
    #[arg(long, global = true)]
    pub headless: bool,

    /// Treat the installation as COSMOS Enterprise.
    #[arg(long, global = true)]
    pub enterprise: bool,

    #[command(subcommand)]
    pub command: Option<Command>,
}

#[derive(Subcommand, Debug)]
pub enum Command {
    /// Install components: a Docker engine, an isolated Python runtime, and/or
    /// the COSMOS environment.
    Install(InstallArgs),

    /// Build all COSMOS containers from source (development installs only).
    Build {
        /// Extra flags passed through to `docker compose build`.
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        flags: Vec<String>,
    },

    /// Start the COSMOS containers (detached). Access at http://localhost:2900.
    Run,

    /// Build (if a dev install) and run COSMOS.
    Start {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        flags: Vec<String>,
    },

    /// Gracefully stop all COSMOS containers.
    Stop,

    /// Restart all COSMOS containers (stop + run).
    Restart,

    /// Show the status of the COSMOS containers.
    Status,

    /// Show container logs.
    Logs {
        /// Optional service name (e.g. openc3-operator). Omit for all services.
        service: Option<String>,
        /// Follow log output.
        #[arg(short, long)]
        follow: bool,
    },

    /// Continuously monitor container health (headless monitor loop).
    Monitor,

    /// Remove COSMOS docker volumes and data. WARNING: destructive.
    Cleanup {
        /// Also remove local plugin files in plugins/DEFAULT/.
        #[arg(long)]
        local: bool,
        /// Skip the confirmation prompt.
        #[arg(long)]
        force: bool,
    },

    /// Run a COSMOS CLI command inside a container as the default user.
    Cli {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
    },

    /// Run a COSMOS CLI command inside a container as root.
    Cliroot {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
    },

    /// Run COSMOS test suites (rspec, playwright, hash).
    Test {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
    },

    /// Upgrade the COSMOS environment to a given git tag.
    Upgrade {
        /// Git tag to upgrade to (e.g. v6.4.1).
        tag: String,
        /// Show the diff without applying changes.
        #[arg(long)]
        preview: bool,
    },

    /// Utility commands (encode, hash, save, load, tag, push, pull, clean, ...).
    Util(UtilArgs),

    /// Run the host microservice operator (process spawner/monitor).
    Microservices,

    /// Pair with a remote COSMOS bridge using an enrollment token (from the
    /// COSMOS Admin → Bridges page). Not needed for a co-located COSMOS, which
    /// enrolls automatically.
    BridgeEnroll {
        /// The enrollment token generated in COSMOS.
        token: String,
    },

    /// Launch the graphical control panel explicitly.
    Gui,
}

#[derive(Args, Debug)]
pub struct InstallArgs {
    #[command(subcommand)]
    pub target: InstallTarget,
}

#[derive(Subcommand, Debug)]
pub enum InstallTarget {
    /// Install everything: prerequisites, Docker, Python, and the COSMOS environment.
    All,
    /// Install OS-level prerequisites (a downloader, and Homebrew on macOS).
    Prerequisites,
    /// Install a working Docker / docker compose engine for this platform.
    Docker,
    /// Install an isolated Python runtime into the python/ subfolder.
    Python,
    /// Install the OpenC3 COSMOS environment into the cosmos/ subfolder.
    Cosmos {
        /// Version tag to install (defaults to "latest").
        #[arg(long, default_value = "latest")]
        tag: String,
    },
}

#[derive(Args, Debug)]
pub struct UtilArgs {
    #[command(subcommand)]
    pub command: UtilCommand,
}

#[derive(Subcommand, Debug)]
pub enum UtilCommand {
    /// Encode a string to base64.
    Encode { string: String },
    /// Hash a string using SHA-256.
    Hash { string: String },
    /// Pull all OpenC3 images from a registry.
    Pull {
        tag: String,
        repo: Option<String>,
        namespace: Option<String>,
        suffix: Option<String>,
    },
    /// Pull and save all OpenC3 images to tar files in tmp/.
    Save {
        repo: String,
        namespace: String,
        tag: String,
        suffix: Option<String>,
    },
    /// Load OpenC3 images from tar files in tmp/.
    Load {
        tag: Option<String>,
        suffix: Option<String>,
    },
    /// Tag OpenC3 images from one repo to another.
    Tag {
        repo1: String,
        repo2: String,
        namespace1: String,
        tag1: String,
        namespace2: Option<String>,
        tag2: Option<String>,
        suffix: Option<String>,
    },
    /// Push OpenC3 images to a repository.
    Push {
        repo: String,
        namespace: String,
        tag: String,
        suffix: Option<String>,
    },
    /// Remove node_modules, coverage, and lock files from the source tree.
    Clean,
}
