//! Reading what the scripts and agents leave behind. Everything here is a pure function
//! of text, so it's tested without running anything.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::LazyLock;

use regex::Regex;
use serde_json::Value;

use crate::events::Usage;

/// The round's label in a file name: its first 40 characters, with anything but
/// `[A-Za-z0-9._-]` replaced by `_`.
pub fn label(round: &str) -> String {
    round
        .chars()
        .take(40)
        .map(|c| {
            if c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-') {
                c
            } else {
                '_'
            }
        })
        .collect()
}

/// Where step outputs are copied: the events file with `.jsonl` replaced by `.d`.
pub fn steps_dir(events: &Path) -> PathBuf {
    let events = events.to_string_lossy();
    PathBuf::from(format!(
        "{}.d",
        events.strip_suffix(".jsonl").unwrap_or(&events)
    ))
}

static SPEC_TEST: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[[:space:]]*(async[[:space:]]+)?fn[[:space:]]+spec_").unwrap());

/// Counts the `spec_` test functions in every file under `dir`.
pub fn count_tests(dir: &Path) -> io::Result<u32> {
    let mut count = 0;
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let kind = entry.file_type()?;
        if kind.is_dir() {
            count += count_tests(&entry.path())?;
        } else if kind.is_file() {
            let text = String::from_utf8_lossy(&fs::read(entry.path())?).into_owned();
            count += text.lines().filter(|line| SPEC_TEST.is_match(line)).count() as u32;
        }
    }
    Ok(count)
}

/// An agent's `DISPUTE:` and `QUESTION:` lines, which stop the round for a human.
pub fn ruling(message: &str) -> String {
    message
        .lines()
        .filter(|line| line.starts_with("DISPUTE:") || line.starts_with("QUESTION:"))
        .collect::<Vec<_>>()
        .join("\n")
}

/// The usage in a `claude -p --output-format json` result. `None` when there's no result,
/// as when a usage limit cut the run off.
pub fn usage(last_run_json: &str) -> Option<Usage> {
    let run: Value = serde_json::from_str(last_run_json).ok()?;
    let millis = run.get("duration_ms")?.as_f64()?;
    Some(Usage {
        seconds: (millis / 1000.0).round() as u64,
        cost_usd: run.get("total_cost_usd").and_then(Value::as_f64),
        turns: run.get("num_turns").and_then(Value::as_u64),
        denials: run
            .get("permission_denials")
            .and_then(Value::as_array)
            .map_or(0, |denials| denials.len() as u64),
    })
}

/// What judge.sh's summary.txt says.
#[derive(Debug, Default, PartialEq)]
pub struct JudgeSummary {
    pub passed: Option<u32>,
    pub failed: Option<u32>,
    /// `SPEC 3.2: 1 of 4 tests fail`, one per failing clause.
    pub failing: Vec<String>,
    /// Up to three lines that say the build, harness or migrations failed, joined by `;`.
    pub problem: String,
}

static TESTS_LINE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^tests: ([0-9]+) passed(?:, ([0-9]+) failed)?").unwrap());
static PROBLEM: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"FAILED|harness:|migrations:|naming rule").unwrap());

impl JudgeSummary {
    pub fn parse(summary: &str) -> Self {
        let mut parsed = JudgeSummary::default();
        let mut problems = Vec::new();
        for line in summary.lines() {
            if let Some(caps) = TESTS_LINE
                .captures(line)
                .filter(|_| parsed.passed.is_none())
            {
                parsed.passed = caps[1].parse().ok();
                parsed.failed = caps.get(2).and_then(|failed| failed.as_str().parse().ok());
            }
            if let Some(clause) = line
                .strip_prefix("  ")
                .filter(|rest| rest.starts_with("SPEC "))
            {
                parsed.failing.push(clause.to_string());
            }
            if problems.len() < 3 && PROBLEM.is_match(line) {
                problems.push(line);
            }
        }
        parsed.problem = problems.join(";");
        parsed
    }
}

/// judge.sh's exit status, in words.
pub fn judge_result(exit_status: i32) -> String {
    match exit_status {
        0 => "pass".into(),
        1 => "fail".into(),
        2 => "broken".into(),
        n => format!("exit {n}"),
    }
}

/// What every run labelled with `round` has cost, from the usage ledger lane.sh appends
/// to. `None` if any line can't be read, rather than a total that's quietly short.
pub fn round_cost(ledger: &str, round: &str) -> Option<f64> {
    let mut total = 0.0;
    for line in ledger.lines().filter(|line| !line.trim().is_empty()) {
        let run: Value = serde_json::from_str(line).ok()?;
        let run = run.as_object()?;
        if run.get("round").and_then(Value::as_str) == Some(round) {
            total += run.get("cost_usd").and_then(Value::as_f64).unwrap_or(0.0);
        }
    }
    Some(total)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn labels_keep_forty_safe_characters() {
        assert_eq!(label("10"), "10");
        assert_eq!(
            label("SPEC section 3 (accounts)"),
            "SPEC_section_3__accounts_"
        );
        assert_eq!(label("refactor-1.b_x"), "refactor-1.b_x");
        assert_eq!(label(&"é".repeat(50)), "_".repeat(40));
    }

    #[test]
    fn steps_dir_replaces_the_jsonl_extension() {
        assert_eq!(
            steps_dir(Path::new("/c/events/round-10j.jsonl")),
            Path::new("/c/events/round-10j.d")
        );
        assert_eq!(
            steps_dir(Path::new("/c/events/round-10j.log")),
            Path::new("/c/events/round-10j.log.d")
        );
    }

    #[test]
    fn counts_spec_tests_in_every_file_below() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir(dir.path().join("sub")).unwrap();
        fs::write(
            dir.path().join("a.rs"),
            "#[test]\nfn spec_1_1_x() {}\n  async fn spec_1_2_y() {}\nfn helper() {}\n// fn spec_in_a_comment\nfn spec_\n",
        )
        .unwrap();
        fs::write(
            dir.path().join("sub/b.rs"),
            "\tfn  spec_2_1() {}\npub fn spec_2_2() {}\n",
        )
        .unwrap();
        // `pub fn` doesn't count, as round.sh's grep didn't count it.
        assert_eq!(count_tests(dir.path()).unwrap(), 4);
    }

    #[test]
    fn ruling_keeps_only_dispute_and_question_lines() {
        let message =
            "Done.\nQUESTION: 17.3: which?\n  QUESTION: indented\nDISPUTE: 3.11 is wrong\n";
        assert_eq!(
            ruling(message),
            "QUESTION: 17.3: which?\nDISPUTE: 3.11 is wrong"
        );
        assert_eq!(ruling("All green."), "");
    }

    #[test]
    fn usage_comes_from_the_claude_result() {
        let run = r#"{"duration_ms":1709499,"total_cost_usd":8.3,"num_turns":77,"permission_denials":[{"tool_name":"Bash"}],"result":"x"}"#;
        assert_eq!(
            usage(run),
            Some(Usage {
                seconds: 1709,
                cost_usd: Some(8.3),
                turns: Some(77),
                denials: 1
            })
        );
        let sparse = r#"{"duration_ms":1500}"#;
        assert_eq!(
            usage(sparse),
            Some(Usage {
                seconds: 2,
                cost_usd: None,
                turns: None,
                denials: 0
            })
        );
        assert_eq!(usage(""), None);
        assert_eq!(usage(r#"{"result":"no duration"}"#), None);
    }

    #[test]
    fn judge_summary_of_a_pass() {
        let summary = "server build: ok\nstartup: ok\ntests: 1182 passed, 0 failed\n";
        assert_eq!(
            JudgeSummary::parse(summary),
            JudgeSummary {
                passed: Some(1182),
                failed: Some(0),
                failing: vec![],
                problem: "".into()
            }
        );
    }

    #[test]
    fn judge_summary_of_failing_clauses() {
        let summary = "server build: ok\nstartup: ok\ntests: 1034 passed, 116 failed\nfailing clauses:\n  SPEC 3.4: 1 of 42 tests fail\n  SPEC 17.1: 6 of 6 tests fail\n";
        let parsed = JudgeSummary::parse(summary);
        assert_eq!((parsed.passed, parsed.failed), (Some(1034), Some(116)));
        assert_eq!(
            parsed.failing,
            [
                "SPEC 3.4: 1 of 42 tests fail",
                "SPEC 17.1: 6 of 6 tests fail"
            ]
        );
        assert_eq!(parsed.problem, "");
    }

    #[test]
    fn judge_summary_of_a_broken_build() {
        let summary = "server build: FAILED\n\nerror[E0425]: cannot find value\nharness: x\nmigrations: y\nnaming rule z\n";
        let parsed = JudgeSummary::parse(summary);
        assert_eq!((parsed.passed, parsed.failed), (None, None));
        assert_eq!(
            parsed.problem,
            "server build: FAILED;harness: x;migrations: y"
        );
        assert_eq!(JudgeSummary::parse(""), JudgeSummary::default());
    }

    #[test]
    fn judge_results_in_words() {
        assert_eq!(judge_result(0), "pass");
        assert_eq!(judge_result(1), "fail");
        assert_eq!(judge_result(2), "broken");
        assert_eq!(judge_result(130), "exit 130");
    }

    #[test]
    fn round_cost_sums_the_round_s_runs() {
        let ledger = r#"{"round":"10","role":"tester","cost_usd":1.5}
{"round":"9","role":"tester","cost_usd":100}
{"round":"10","role":"implementer","cost_usd":null}

{"round":"10","role":"implementer","cost_usd":2.25}
"#;
        assert_eq!(round_cost(ledger, "10"), Some(3.75));
        assert_eq!(round_cost(ledger, "11"), Some(0.0));
        assert_eq!(round_cost("not json\n", "10"), None);
    }
}
