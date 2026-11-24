//! MyBudget's workflow tooling, run as `cargo xtask <command>`.

mod events;
mod git;
mod paths;
mod round;

use std::path::PathBuf;
use std::process::ExitCode;

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "cargo xtask", about = "MyBudget's workflow tooling")]
struct Cli {
    /// The cache the scripts share: agent state, judge results, usage and events.
    /// Defaults to ~/.cache/mybudget.
    #[arg(long, env = "MYBUDGET_CACHE", global = true)]
    cache: Option<PathBuf>,

    #[command(subcommand)]
    command: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// One adversarial round: tester → implementer until green → tester attacks.
    Round(round::RoundArgs),
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    let result = paths::Paths::new(cli.cache).and_then(|paths| match cli.command {
        Cmd::Round(args) => round::run(&paths, args),
    });
    match result {
        Ok(code) => ExitCode::from(u8::try_from(code).unwrap_or(1)),
        Err(err) => {
            eprintln!("xtask: {err:#}");
            ExitCode::from(70)
        }
    }
}
