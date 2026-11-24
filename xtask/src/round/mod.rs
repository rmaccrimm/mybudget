//! `cargo xtask round`: one adversarial round on a piece of the spec.
//!
//!   1. the tester writes tests for the task
//!   2. the implementer works until the judge is green (up to `--max-fixes` runs)
//!   3. the tester tries to break it; if it finds new failures, back to 2
//!
//! The round ends when an attack finds nothing new or after `--max-attacks` attacks. It
//! stops for a human when either agent ends with a `DISPUTE:` or `QUESTION:` line.
//!
//! Progress: each step appends one JSON line to an events file (see `crate::events`),
//! and each step's final message or judge summary is copied into `<events>.d/`.
//! `scripts/watch-round.sh` follows the file; `scripts/round-status.sh` summarises it.

mod driver;
mod parse;
mod steps;

use std::fs;
use std::panic::{self, AssertUnwindSafe};
use std::path::PathBuf;
use std::process::Command;
use std::sync::Arc;
use std::sync::atomic::AtomicBool;

use anyhow::Context;
use clap::ValueEnum;
use signal_hook::consts::{SIGINT, SIGTERM};

use crate::events::{Body, EventLog};
use crate::paths::Paths;
use driver::{Config, Round, Stop};
use steps::ScriptSteps;

#[derive(Debug, clap::Args)]
pub struct RoundArgs {
    /// The task, e.g. "SPEC section 3 (accounts)". The agents' prompts quote it.
    pub task: String,

    /// The first step. `implementer` is for a task that needs no new tests first, such
    /// as a refactor. `judge` resumes a round whose last agent run was cut off.
    #[arg(long, env = "START", value_enum, default_value_t = Start::Tester)]
    pub start: Start,

    /// Implementer runs allowed before each green judge run.
    #[arg(long, env = "MAX_FIXES", default_value_t = 5)]
    pub max_fixes: u32,

    /// Tester attacks after the first green judge run.
    #[arg(long, env = "MAX_ATTACKS", default_value_t = 2)]
    pub max_attacks: u32,

    /// Labels the agents' token usage, so reruns of a round add up together. Defaults
    /// to the task.
    #[arg(long, env = "MYBUDGET_ROUND")]
    pub round: Option<String>,

    /// The events file. Defaults to `<cache>/events/round-<round>-<time>.jsonl`; name it
    /// yourself to watch it before it exists.
    #[arg(long, env = "MYBUDGET_EVENTS")]
    pub events: Option<PathBuf>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum Start {
    Tester,
    Implementer,
    Judge,
}

impl Start {
    fn name(self) -> &'static str {
        match self {
            Start::Tester => "tester",
            Start::Implementer => "implementer",
            Start::Judge => "judge",
        }
    }
}

/// Runs a round and returns the process's exit status (see `driver::Stop`).
pub fn run(paths: &Paths, args: RoundArgs) -> anyhow::Result<i32> {
    let round = args.round.unwrap_or_else(|| args.task.clone());
    let events = match args.events {
        Some(events) => std::path::absolute(events)?,
        None => paths.events_dir().join(format!(
            "round-{}-{}.jsonl",
            parse::label(&round),
            jiff::ZonedDateTime::now().strftime("%Y%m%d-%H%M%S")
        )),
    };
    let steps_dir = parse::steps_dir(&events);
    fs::create_dir_all(&steps_dir)
        .with_context(|| format!("couldn't create {}", steps_dir.display()))?;
    println!("xtask round: events in {}", events.display());

    // An idle Mac sleeps mid-round and stalls whatever step is running; caffeinate holds
    // it awake until this process exits.
    if let Err(err) = Command::new("caffeinate")
        .args(["-i", "-w"])
        .arg(std::process::id().to_string())
        .spawn()
    {
        eprintln!("xtask round: couldn't start caffeinate, so the Mac may sleep: {err}");
    }

    // A Ctrl-C reaches the running agent or judge too. The round stops once that step
    // returns, so the events still end with round_end.
    let interrupted = Arc::new(AtomicBool::new(false));
    for signal in [SIGINT, SIGTERM] {
        signal_hook::flag::register(signal, Arc::clone(&interrupted))?;
    }

    let log = EventLog::new(events.clone(), round.clone());
    log.emit(Body::RoundStart {
        task: args.task.clone(),
        start: args.start.name().into(),
        events: events.to_string_lossy().into_owned(),
        max_fixes: args.max_fixes,
        max_attacks: args.max_attacks,
    });

    let cfg = Config {
        task: args.task,
        start: args.start,
        max_fixes: args.max_fixes,
        max_attacks: args.max_attacks,
        steps_dir,
        judge_results: paths.judge_results(),
    };
    let mut driver = Round::new(&cfg, ScriptSteps::new(paths, &round), &log, &interrupted);
    let stop = panic::catch_unwind(AssertUnwindSafe(|| driver.run())).unwrap_or_else(|_| Stop {
        code: 101,
        reason: "xtask round panicked (see its log)".into(),
    });
    finish(
        paths,
        &log,
        &round,
        &stop,
        driver.steps_taken(),
        driver.run_cost(),
    );
    Ok(stop.code)
}

/// Records how the round ended and prints the round's usage so far.
fn finish(paths: &Paths, log: &EventLog, round: &str, stop: &Stop, steps: u32, run_cost: f64) {
    let round_cost = fs::read_to_string(paths.usage_ledger())
        .ok()
        .and_then(|ledger| parse::round_cost(&ledger, round));
    log.emit(Body::RoundEnd {
        exit_status: stop.code,
        reason: stop.reason.clone(),
        steps,
        run_cost_usd: run_cost,
        round_cost_usd: round_cost,
    });
    if stop.code == 0 {
        println!("xtask round: {}", stop.reason);
    } else {
        eprintln!("xtask round: {}", stop.reason);
    }
    let usage = Command::new(paths.script("usage.sh"))
        .arg(round)
        .env("MYBUDGET_CACHE", &paths.cache)
        .status();
    if let Err(err) = usage {
        eprintln!("xtask round: couldn't run usage.sh: {err}");
    }
}
