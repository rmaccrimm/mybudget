//! A round's progress log: one JSON object per line, appended as each step starts and
//! finishes. `scripts/events.jq` formats it, for `scripts/watch-round.sh` and
//! `scripts/round-status.sh`, so the field names, and which ones are `""` and which are
//! `null` when they don't apply, are a contract with those scripts.

use std::fmt;
use std::fs::OpenOptions;
use std::io::Write;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Event {
    /// UTC, to the second: `2026-11-20T05:40:00Z`.
    pub time: String,
    pub round: String,
    #[serde(flatten)]
    pub body: Body,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Body {
    RoundStart {
        task: String,
        start: String,
        events: String,
        max_fixes: u32,
        max_attacks: u32,
    },
    StepStart {
        step: u32,
        role: String,
        kind: String,
    },
    AgentDone {
        step: u32,
        role: String,
        kind: String,
        outcome: Outcome,
        exit_status: i32,
        /// `<lane>@<short sha>`, or `""` when the agent committed nothing.
        commit: String,
        /// `git diff --shortstat` of the commit, or `""`.
        changes: String,
        /// The tester's `spec_` test count; `null` for the implementer.
        tests_before: Option<u32>,
        tests_after: Option<u32>,
        /// `null` when the run left no JSON result (a crash, a usage limit).
        usage: Option<Usage>,
        /// The agent's `DISPUTE:` and `QUESTION:` lines, or `""`.
        ruling: String,
        message_file: String,
    },
    JudgeDone {
        step: u32,
        run: u32,
        /// `pass`, `fail`, `broken` or `exit <n>`.
        result: String,
        exit_status: i32,
        passed: Option<u32>,
        failed: Option<u32>,
        failing: Vec<String>,
        problem: String,
        seconds: u64,
        summary_file: String,
    },
    RoundEnd {
        exit_status: i32,
        reason: String,
        steps: u32,
        /// What this run's agents cost.
        run_cost_usd: f64,
        /// What every run labelled with this round has cost, from the usage ledger.
        round_cost_usd: Option<f64>,
    },
}

/// One agent run's usage, from the `claude -p --output-format json` result.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Usage {
    pub seconds: u64,
    pub cost_usd: Option<f64>,
    pub turns: Option<u64>,
    pub denials: u64,
}

/// How an agent run ended, in the order lane.sh's results are checked.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Outcome {
    /// lane.sh exited 4: the agent changed something outside its lane.
    LeftLane,
    /// lane.sh exited non-zero otherwise, usually claude itself failing.
    ClaudeFailed,
    /// The agent ended with a `QUESTION:` line.
    Question,
    /// The agent ended with a `DISPUTE:` line and no question.
    Dispute,
    NoChanges,
    Ok,
}

impl Outcome {
    pub fn classify(exit_status: i32, ruling: &str, committed: bool) -> Self {
        if exit_status == 4 {
            Outcome::LeftLane
        } else if exit_status != 0 {
            Outcome::ClaudeFailed
        } else if ruling.lines().any(|line| line.starts_with("QUESTION:")) {
            Outcome::Question
        } else if !ruling.is_empty() {
            Outcome::Dispute
        } else if !committed {
            Outcome::NoChanges
        } else {
            Outcome::Ok
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Outcome::LeftLane => "left_lane",
            Outcome::ClaudeFailed => "claude_failed",
            Outcome::Question => "question",
            Outcome::Dispute => "dispute",
            Outcome::NoChanges => "no_changes",
            Outcome::Ok => "ok",
        }
    }
}

impl fmt::Display for Outcome {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.name())
    }
}

/// Appends events for one round. Only the round runner writes here, outside the agents'
/// sandboxes.
pub struct EventLog {
    path: PathBuf,
    round: String,
}

impl EventLog {
    pub fn new(path: PathBuf, round: String) -> Self {
        EventLog { path, round }
    }

    /// Appends one event as one line. A failure to write it is reported and never stops
    /// the round.
    pub fn emit(&self, body: Body) {
        let event = Event {
            time: jiff::Timestamp::now()
                .strftime("%Y-%m-%dT%H:%M:%SZ")
                .to_string(),
            round: self.round.clone(),
            body,
        };
        if let Err(err) = self.append(&event) {
            eprintln!(
                "xtask round: couldn't write an event to {}: {err}",
                self.path.display()
            );
        }
    }

    fn append(&self, event: &Event) -> std::io::Result<()> {
        let mut line = serde_json::to_string(event)?;
        line.push('\n');
        // One write of a whole line, so a watcher reading the file never sees half of one.
        OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.path)?
            .write_all(line.as_bytes())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;
    use std::path::Path;
    use std::process::{Command, Stdio};

    /// Events as round.sh wrote them during round 10, one of each shape.
    const BASH_EVENTS: &[&str] = &[
        r#"{"time":"2026-11-24T15:20:40Z","round":"10","type":"round_start","task":"SPEC section 17 (importing OFX files).","start":"judge","events":"/cache/events/round-10j.jsonl","max_fixes":5,"max_attacks":2}"#,
        r#"{"time":"2026-11-24T15:20:40Z","round":"10","type":"step_start","step":1,"role":"judge","kind":"run 1"}"#,
        r#"{"time":"2026-11-24T15:22:50Z","round":"10","type":"judge_done","step":1,"run":1,"result":"pass","exit_status":0,"passed":1182,"failed":0,"failing":[],"problem":"","seconds":130,"summary_file":"/cache/events/round-10j.d/01-judge-1.txt"}"#,
        r#"{"time":"2026-11-20T05:44:00Z","round":"10","type":"judge_done","step":2,"run":1,"result":"fail","exit_status":1,"passed":1034,"failed":116,"failing":["SPEC 3.4: 1 of 42 tests fail","SPEC 15.8: 1 of 4 tests fail"],"problem":"","seconds":87,"summary_file":"/cache/events/round-10c.d/02-judge-1.txt"}"#,
        r#"{"time":"2026-11-20T05:40:00Z","round":"10","type":"agent_done","step":1,"role":"tester","kind":"write","outcome":"question","exit_status":0,"commit":"testsuite@1dc0b1e","changes":"10 files changed, 4868 insertions(+), 23 deletions(-)","tests_before":1037,"tests_after":1147,"usage":{"seconds":1709,"cost_usd":8.307533600000003,"turns":77,"denials":1},"ruling":"QUESTION: 17.3: Is it `AB` or `ABCD`?\nQUESTION: 17.5: Is `5.` a valid amount?","message_file":"/cache/events/round-10b.d/01-tester-write.md"}"#,
        r#"{"time":"2026-11-20T02:22:43Z","round":"10","type":"agent_done","step":1,"role":"tester","kind":"write","outcome":"claude_failed","exit_status":1,"commit":"","changes":"","tests_before":1037,"tests_after":1054,"usage":{"seconds":770,"cost_usd":4.5529356,"turns":62,"denials":2},"ruling":"","message_file":"/cache/events/round-10.d/01-tester-write.md"}"#,
        r#"{"time":"2026-11-20T05:55:55Z","round":"10","type":"agent_done","step":3,"role":"implementer","kind":"fix 1","outcome":"ok","exit_status":0,"commit":"server@8efd490","changes":"18 files changed, 1903 insertions(+), 48 deletions(-)","tests_before":null,"tests_after":null,"usage":null,"ruling":"","message_file":"/cache/events/round-10c.d/03-implementer-fix-1.md"}"#,
        r#"{"time":"2026-11-24T15:22:50Z","round":"10","type":"round_end","exit_status":130,"reason":"round.sh was interrupted","steps":2,"run_cost_usd":0,"round_cost_usd":37.832921}"#,
        r#"{"time":"2026-11-20T02:22:43Z","round":"10","type":"round_end","exit_status":1,"reason":"lane.sh stopped the tester with status 1 (claude_failed)","steps":1,"run_cost_usd":4.5529356,"round_cost_usd":null}"#,
    ];

    /// Every number as a float, since bash wrote `0` where serde writes `0.0`.
    fn normalize(value: Value) -> Value {
        match value {
            Value::Number(n) => serde_json::json!(n.as_f64().unwrap()),
            Value::Array(items) => Value::Array(items.into_iter().map(normalize).collect()),
            Value::Object(map) => {
                Value::Object(map.into_iter().map(|(k, v)| (k, normalize(v))).collect())
            }
            other => other,
        }
    }

    #[test]
    fn events_round_trip_with_the_same_fields_as_round_sh_wrote() {
        for line in BASH_EVENTS {
            let event: Event = serde_json::from_str(line).unwrap_or_else(|e| panic!("{e}: {line}"));
            let ours = serde_json::to_value(&event).unwrap();
            let theirs: Value = serde_json::from_str(line).unwrap();
            assert_eq!(normalize(ours), normalize(theirs), "{line}");
        }
    }

    /// The scripts that read the events format them with events.jq; it must print ours
    /// exactly as it printed round.sh's.
    #[test]
    fn events_jq_formats_our_events_as_it_formatted_round_sh_events() {
        let jq = |input: String| -> Option<String> {
            let filter = Path::new(env!("CARGO_MANIFEST_DIR")).join("../scripts/events.jq");
            let mut child = Command::new("jq")
                .args(["-r", "--argjson", "all", "false", "-f"])
                .arg(filter)
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .spawn()
                .ok()?;
            child
                .stdin
                .take()
                .unwrap()
                .write_all(input.as_bytes())
                .unwrap();
            let out = child.wait_with_output().unwrap();
            assert!(out.status.success(), "jq failed");
            Some(String::from_utf8(out.stdout).unwrap())
        };
        let theirs = BASH_EVENTS.join("\n");
        let ours = BASH_EVENTS
            .iter()
            .map(|line| {
                serde_json::to_string(&serde_json::from_str::<Event>(line).unwrap()).unwrap()
            })
            .collect::<Vec<_>>()
            .join("\n");
        let Some(expected) = jq(theirs) else {
            eprintln!("skipped: jq isn't installed");
            return;
        };
        assert_eq!(jq(ours).unwrap(), expected);
    }

    #[test]
    fn outcomes_are_checked_in_lane_sh_order() {
        assert_eq!(Outcome::classify(4, "QUESTION: x", true), Outcome::LeftLane);
        assert_eq!(
            Outcome::classify(1, "QUESTION: x", true),
            Outcome::ClaudeFailed
        );
        assert_eq!(Outcome::classify(130, "", false), Outcome::ClaudeFailed);
        assert_eq!(
            Outcome::classify(0, "DISPUTE: a\nQUESTION: b", true),
            Outcome::Question
        );
        assert_eq!(Outcome::classify(0, "DISPUTE: a", true), Outcome::Dispute);
        assert_eq!(Outcome::classify(0, "", false), Outcome::NoChanges);
        assert_eq!(Outcome::classify(0, "", true), Outcome::Ok);
    }
}
