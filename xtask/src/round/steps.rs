//! The two kinds of step a round runs: an agent in its lane, and the judge. The round's
//! logic only sees the `Steps` trait, so its tests use a scripted fake instead of agents.

use std::fs;
use std::os::unix::process::ExitStatusExt;
use std::path::Path;
use std::process::{Command, ExitStatus};
use std::time::{Instant, SystemTime};

use anyhow::Context;

use super::parse;
use crate::events::Usage;
use crate::git;
use crate::paths::{Paths, Role};

/// What one agent run did.
#[derive(Debug, Clone, PartialEq)]
pub struct LaneReport {
    /// lane.sh's exit status: 0, 4 when the agent left its lane, else claude's failure.
    pub exit_status: i32,
    /// `<lane>@<short sha>` if lane.sh committed the agent's work, else `""`.
    pub commit: String,
    pub changes: String,
    /// The tester's `spec_` test count before and after; `None` for the implementer.
    pub tests_before: Option<u32>,
    pub tests_after: Option<u32>,
    /// The agent's final message.
    pub message: String,
    pub usage: Option<Usage>,
}

/// What one judge run found.
#[derive(Debug, Clone, PartialEq)]
pub struct JudgeReport {
    /// judge.sh's exit status: 0 pass, 1 the server fails, 2 the tests or harness are broken.
    pub exit_status: i32,
    /// This run's summary.txt, or `""` if the run didn't write one.
    pub summary: String,
    pub seconds: u64,
}

pub trait Steps {
    /// Runs one agent in its lane, and copies its final message to `message_copy`.
    fn lane(&mut self, role: Role, prompt: &str, message_copy: &Path)
    -> anyhow::Result<LaneReport>;

    /// Runs the judge on the committed code, and copies its summary to `summary_copy`.
    fn judge(&mut self, summary_copy: &Path) -> anyhow::Result<JudgeReport>;
}

/// The real steps: `scripts/lane.sh` and `scripts/judge.sh`, with their output going
/// straight to the terminal or log.
pub struct ScriptSteps<'a> {
    paths: &'a Paths,
    round: &'a str,
}

impl<'a> ScriptSteps<'a> {
    pub fn new(paths: &'a Paths, round: &'a str) -> Self {
        ScriptSteps { paths, round }
    }

    fn script(&self, name: &str) -> Command {
        let mut command = Command::new(self.paths.script(name));
        // lane.sh labels each run's usage with the round, so reruns add up together.
        command
            .env("MYBUDGET_ROUND", self.round)
            .env("MYBUDGET_CACHE", &self.paths.cache);
        command
    }

    fn count_tests(&self) -> Option<u32> {
        let dir = self.paths.tests_dir();
        parse::count_tests(&dir)
            .inspect_err(|err| {
                eprintln!(
                    "xtask round: couldn't count the tests in {}: {err}",
                    dir.display()
                )
            })
            .ok()
    }
}

impl Steps for ScriptSteps<'_> {
    fn lane(
        &mut self,
        role: Role,
        prompt: &str,
        message_copy: &Path,
    ) -> anyhow::Result<LaneReport> {
        let dir = self.paths.lane_dir(role);
        let before = git::head(&dir)?;
        let tests_before = if role == Role::Tester {
            self.count_tests()
        } else {
            None
        };

        let status = self
            .script("lane.sh")
            .arg(role.name())
            .arg(prompt)
            .status()
            .context("couldn't run lane.sh")?;

        let after = git::head(&dir)?;
        let tests_after = if role == Role::Tester {
            self.count_tests()
        } else {
            None
        };
        let (commit, changes) = if after != before {
            (
                format!("{}@{}", role.lane(), git::short_head(&dir)?),
                git::shortstat(&dir, &before, &after)?,
            )
        } else {
            (String::new(), String::new())
        };

        let state = self.paths.role_state(role);
        // An empty copy when there's no message, so every step has its file.
        let message = fs::read(state.join("last-output.md")).unwrap_or_default();
        fs::write(message_copy, &message)
            .with_context(|| format!("couldn't write {}", message_copy.display()))?;
        let usage = fs::read_to_string(state.join("last-run.json"))
            .ok()
            .and_then(|run| parse::usage(&run));

        Ok(LaneReport {
            exit_status: exit_code(status),
            commit,
            changes,
            tests_before,
            tests_after,
            message: String::from_utf8_lossy(&message).into_owned(),
            usage,
        })
    }

    fn judge(&mut self, summary_copy: &Path) -> anyhow::Result<JudgeReport> {
        let started_at = SystemTime::now();
        let started = Instant::now();
        let status = self
            .script("judge.sh")
            .status()
            .context("couldn't run judge.sh")?;
        let seconds = started.elapsed().as_secs();

        // judge.sh writes summary.txt on every exit; one from before this run started
        // belongs to an earlier run.
        let summary_path = self.paths.judge_results().join("summary.txt");
        let fresh = fs::metadata(&summary_path)
            .and_then(|meta| meta.modified())
            .is_ok_and(|modified| modified >= started_at);
        let summary = if fresh {
            fs::read(&summary_path).unwrap_or_default()
        } else {
            Vec::new()
        };
        fs::write(summary_copy, &summary)
            .with_context(|| format!("couldn't write {}", summary_copy.display()))?;

        Ok(JudgeReport {
            exit_status: exit_code(status),
            summary: String::from_utf8_lossy(&summary).into_owned(),
            seconds,
        })
    }
}

/// An exit status as a shell reports it: 128 + the signal for a process killed by one.
fn exit_code(status: ExitStatus) -> i32 {
    status
        .code()
        .unwrap_or_else(|| 128 + status.signal().unwrap_or(0))
}
