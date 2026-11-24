//! The round itself: tester → judge ⇄ implementer → tester attack, until an attack finds
//! nothing new or the attacks run out.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};

use super::Start;
use super::parse::{self, JudgeSummary};
use super::steps::Steps;
use crate::events::{Body, EventLog, Outcome};
use crate::paths::Role;

/// The exit status for a failure in the round runner itself, such as git failing.
pub const INTERNAL_ERROR: i32 = 70;

/// Added to the implementer's last fix prompt before the round stops for a human, so a
/// test it can't pass ends in a dispute rather than another guess.
pub const LAST_FIX: &str = "\n\nThis is your last run before the round stops for a human. \
    For any failing test you can't make pass, end with a DISPUTE: line for it (see your \
    rules) instead of guessing again.";

pub struct Config {
    pub task: String,
    pub start: Start,
    pub max_fixes: u32,
    pub max_attacks: u32,
    /// Where each step's final message or judge summary is copied.
    pub steps_dir: PathBuf,
    /// judge.sh's results, named when the harness is broken.
    pub judge_results: PathBuf,
}

/// How a round ended: the process's exit status and why.
///
/// 0 complete, 1 still failing after `max_fixes` implementer runs, 2 the test suite or
/// harness is broken, 3 an agent needs a ruling, 4 an agent left its lane, 130
/// interrupted, 70 the round runner failed; any other status is lane.sh's.
#[derive(Debug, Clone, PartialEq)]
pub struct Stop {
    pub code: i32,
    pub reason: String,
}

impl Stop {
    fn new(code: i32, reason: impl Into<String>) -> Self {
        Stop {
            code,
            reason: reason.into(),
        }
    }
}

pub struct Round<'a, S> {
    cfg: &'a Config,
    steps: S,
    log: &'a EventLog,
    interrupted: &'a AtomicBool,
    step: u32,
    judge_runs: u32,
    run_cost: f64,
    /// The last judge run's summary, which the next prompt quotes.
    summary: String,
}

impl<'a, S: Steps> Round<'a, S> {
    pub fn new(cfg: &'a Config, steps: S, log: &'a EventLog, interrupted: &'a AtomicBool) -> Self {
        Round {
            cfg,
            steps,
            log,
            interrupted,
            step: 0,
            judge_runs: 0,
            run_cost: 0.0,
            summary: String::new(),
        }
    }

    pub fn steps_taken(&self) -> u32 {
        self.step
    }

    /// What this run's agents cost, from their usage.
    pub fn run_cost(&self) -> f64 {
        self.run_cost
    }

    pub fn run(&mut self) -> Stop {
        self.drive().unwrap_or_else(|stop| stop)
    }

    fn drive(&mut self) -> Result<Stop, Stop> {
        let task = self.cfg.task.clone();
        match self.cfg.start {
            Start::Tester => {
                self.lane(Role::Tester, "write", &format!("Write tests for: {task}"))?
            }
            Start::Implementer => self.lane(Role::Implementer, "task", &format!("Task: {task}"))?,
            // Resuming after an interrupted run: judge the committed code, then go on.
            Start::Judge => {}
        }
        let mut attack = 0;
        loop {
            let mut fixes = 0;
            loop {
                match self.judge()? {
                    0 => break,
                    1 => {}
                    _ => {
                        let results = self.cfg.judge_results.display();
                        return Err(Stop::new(
                            2,
                            format!("the test suite or harness is broken; see {results}"),
                        ));
                    }
                }
                if fixes >= self.cfg.max_fixes {
                    let max = self.cfg.max_fixes;
                    return Err(Stop::new(
                        1,
                        format!("still failing after {max} implementer runs"),
                    ));
                }
                fixes += 1;
                // summary.txt is written to be safe for the implementer: failures by
                // clause and the failing tests' names, never their code or output.
                let mut prompt = format!(
                    "Task: {task}\n\nJudge results for the committed code:\n{}",
                    self.summary
                );
                if fixes == self.cfg.max_fixes {
                    prompt.push_str(LAST_FIX);
                }
                self.lane(Role::Implementer, &format!("fix {fixes}"), &prompt)?;
            }
            if attack > 0 && fixes == 0 {
                return Ok(Stop::new(
                    0,
                    "the tester's last attack found nothing new. Round complete.",
                ));
            }
            if attack == self.cfg.max_attacks {
                let max = self.cfg.max_attacks;
                return Ok(Stop::new(
                    0,
                    format!("green after {max} attacks. Round complete."),
                ));
            }
            attack += 1;
            let prompt = format!(
                "The implementation of \"{task}\" passes every test. Try to break it: write tests for behavior \
                 the spec requires that the server gets wrong or that no test covers yet.\n\n\
                 Judge results for the committed code:\n{}",
                self.summary
            );
            self.lane(Role::Tester, &format!("attack {attack}"), &prompt)?;
        }
    }

    fn check_interrupted(&self) -> Result<(), Stop> {
        if self.interrupted.load(Ordering::SeqCst) {
            Err(Stop::new(130, "the round was interrupted"))
        } else {
            Ok(())
        }
    }

    fn copy_path(&self, name: &str) -> PathBuf {
        self.cfg.steps_dir.join(format!("{:02}-{name}", self.step))
    }

    /// Runs one agent and stops the round if it failed or needs a ruling.
    fn lane(&mut self, role: Role, kind: &str, prompt: &str) -> Result<(), Stop> {
        self.check_interrupted()?;
        self.step += 1;
        let copy = self.copy_path(&format!("{role}-{}.md", kind.replace(' ', "-")));
        self.log.emit(Body::StepStart {
            step: self.step,
            role: role.to_string(),
            kind: kind.to_string(),
        });

        let report = self.steps.lane(role, prompt, &copy).map_err(internal)?;
        // A Ctrl-C reaches the agent too; what it left behind isn't a result.
        self.check_interrupted()?;

        let ruling = parse::ruling(&report.message);
        let outcome = Outcome::classify(report.exit_status, &ruling, !report.commit.is_empty());
        self.run_cost += report
            .usage
            .as_ref()
            .and_then(|usage| usage.cost_usd)
            .unwrap_or(0.0);
        self.log.emit(Body::AgentDone {
            step: self.step,
            role: role.to_string(),
            kind: kind.to_string(),
            outcome,
            exit_status: report.exit_status,
            commit: report.commit,
            changes: report.changes,
            tests_before: report.tests_before,
            tests_after: report.tests_after,
            usage: report.usage,
            ruling: ruling.clone(),
            message_file: path_string(&copy),
        });

        if report.exit_status != 0 {
            let status = report.exit_status;
            return Err(Stop::new(
                status,
                format!("lane.sh stopped the {role} with status {status} ({outcome})"),
            ));
        }
        if !ruling.is_empty() {
            eprintln!("{ruling}");
            eprintln!(
                "xtask round: the {role} needs a human ruling (above). Resolve it, then rerun."
            );
            return Err(Stop::new(
                3,
                format!("the {role} ended with a {outcome}; it needs a ruling"),
            ));
        }
        Ok(())
    }

    /// Runs the judge and returns its exit status.
    fn judge(&mut self) -> Result<i32, Stop> {
        self.check_interrupted()?;
        self.step += 1;
        self.judge_runs += 1;
        let run = self.judge_runs;
        let copy = self.copy_path(&format!("judge-{run}.txt"));
        self.log.emit(Body::StepStart {
            step: self.step,
            role: "judge".into(),
            kind: format!("run {run}"),
        });
        println!("== judge");

        let report = self.steps.judge(&copy).map_err(internal)?;
        self.check_interrupted()?;

        let summary = JudgeSummary::parse(&report.summary);
        self.log.emit(Body::JudgeDone {
            step: self.step,
            run,
            result: parse::judge_result(report.exit_status),
            exit_status: report.exit_status,
            passed: summary.passed,
            failed: summary.failed,
            failing: summary.failing,
            problem: summary.problem,
            seconds: report.seconds,
            summary_file: path_string(&copy),
        });
        // As the shell substitution `$(cat summary.txt)` quoted it, without trailing newlines.
        self.summary = report.summary.trim_end_matches('\n').to_string();
        Ok(report.exit_status)
    }
}

fn internal(err: anyhow::Error) -> Stop {
    Stop::new(INTERNAL_ERROR, format!("xtask round failed: {err:#}"))
}

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::events::{Event, Usage};
    use crate::round::steps::{JudgeReport, LaneReport};
    use std::collections::VecDeque;

    /// Steps that replay scripted results and record what they were asked to do.
    #[derive(Default)]
    struct Fake<'f> {
        lanes: VecDeque<LaneReport>,
        judges: VecDeque<JudgeReport>,
        calls: Vec<(String, String)>,
        /// Set this flag during the call with this index, as a Ctrl-C would.
        interrupt_at: Option<(usize, &'f AtomicBool)>,
    }

    impl Fake<'_> {
        fn record(&mut self, who: String, prompt: &str) {
            if let Some((at, flag)) = self.interrupt_at
                && at == self.calls.len()
            {
                flag.store(true, Ordering::SeqCst);
            }
            self.calls.push((who, prompt.to_string()));
        }
    }

    impl Steps for &mut Fake<'_> {
        fn lane(&mut self, role: Role, prompt: &str, _: &Path) -> anyhow::Result<LaneReport> {
            self.record(role.to_string(), prompt);
            self.lanes
                .pop_front()
                .ok_or_else(|| anyhow::anyhow!("no lane result scripted"))
        }

        fn judge(&mut self, _: &Path) -> anyhow::Result<JudgeReport> {
            self.record("judge".into(), "");
            Ok(self.judges.pop_front().expect("no judge result scripted"))
        }
    }

    fn agent(cost: f64) -> LaneReport {
        LaneReport {
            exit_status: 0,
            commit: "server@abc1234".into(),
            changes: "1 file changed, 2 insertions(+)".into(),
            tests_before: None,
            tests_after: None,
            message: "Done.".into(),
            usage: Some(Usage {
                seconds: 60,
                cost_usd: Some(cost),
                turns: Some(5),
                denials: 0,
            }),
        }
    }

    fn asking(question: &str) -> LaneReport {
        LaneReport {
            message: format!("Mostly done.\n{question}\n"),
            ..agent(1.0)
        }
    }

    fn exiting(status: i32) -> LaneReport {
        LaneReport {
            exit_status: status,
            commit: String::new(),
            changes: String::new(),
            usage: None,
            ..agent(0.0)
        }
    }

    fn pass() -> JudgeReport {
        JudgeReport {
            exit_status: 0,
            summary: "tests: 3 passed, 0 failed\n".into(),
            seconds: 10,
        }
    }

    fn fail() -> JudgeReport {
        JudgeReport {
            exit_status: 1,
            summary: "tests: 2 passed, 1 failed\nfailing clauses:\n  SPEC 3.2: 1 of 2 tests fail\n"
                .into(),
            seconds: 10,
        }
    }

    fn broken() -> JudgeReport {
        JudgeReport {
            exit_status: 2,
            summary: "harness: cargo vendor failed\n".into(),
            seconds: 1,
        }
    }

    struct Ran {
        stop: Stop,
        calls: Vec<(String, String)>,
        events: Vec<Body>,
        run_cost: f64,
        steps: u32,
    }

    fn run_with(start: Start, max_fixes: u32, mut fake: Fake<'_>, flag: &AtomicBool) -> Ran {
        let dir = tempfile::tempdir().unwrap();
        let events = dir.path().join("round.jsonl");
        let cfg = Config {
            task: "SPEC section 3".into(),
            start,
            max_fixes,
            max_attacks: 2,
            steps_dir: dir.path().join("round.d"),
            judge_results: PathBuf::from("/cache/judge/results"),
        };
        let log = EventLog::new(events.clone(), "3".into());
        let mut round = Round::new(&cfg, &mut fake, &log, flag);
        let stop = round.run();
        let (run_cost, steps) = (round.run_cost(), round.steps_taken());
        let events = std::fs::read_to_string(&events)
            .unwrap_or_default()
            .lines()
            .map(|line| serde_json::from_str::<Event>(line).unwrap().body)
            .collect();
        assert!(
            fake.lanes.is_empty() && fake.judges.is_empty(),
            "scripted results left over"
        );
        Ran {
            stop,
            calls: fake.calls,
            events,
            run_cost,
            steps,
        }
    }

    fn run(start: Start, lanes: Vec<LaneReport>, judges: Vec<JudgeReport>) -> Ran {
        let fake = Fake {
            lanes: lanes.into(),
            judges: judges.into(),
            ..Fake::default()
        };
        run_with(start, 5, fake, &AtomicBool::new(false))
    }

    fn who(outcome: &Ran) -> Vec<&str> {
        outcome.calls.iter().map(|(who, _)| who.as_str()).collect()
    }

    #[test]
    fn a_clean_attack_completes_the_round() {
        let out = run(
            Start::Tester,
            vec![agent(1.0), agent(2.0), agent(4.0)],
            vec![fail(), pass(), pass()],
        );
        assert_eq!(
            out.stop,
            Stop::new(
                0,
                "the tester's last attack found nothing new. Round complete."
            )
        );
        assert_eq!(
            who(&out),
            ["tester", "judge", "implementer", "judge", "tester", "judge"]
        );
        assert_eq!(out.calls[0].1, "Write tests for: SPEC section 3");
        assert_eq!(
            out.calls[2].1,
            "Task: SPEC section 3\n\nJudge results for the committed code:\n\
             tests: 2 passed, 1 failed\nfailing clauses:\n  SPEC 3.2: 1 of 2 tests fail"
        );
        assert_eq!(
            out.calls[4].1,
            "The implementation of \"SPEC section 3\" passes every test. Try to break it: write tests for \
             behavior the spec requires that the server gets wrong or that no test covers yet.\n\n\
             Judge results for the committed code:\ntests: 3 passed, 0 failed"
        );
        assert_eq!(out.run_cost, 7.0);
        assert_eq!(out.steps, 6);
    }

    #[test]
    fn the_round_ends_green_when_the_attacks_run_out() {
        let out = run(
            Start::Tester,
            vec![agent(1.0), agent(1.0), agent(1.0), agent(1.0), agent(1.0)],
            vec![pass(), fail(), pass(), fail(), pass()],
        );
        assert_eq!(
            out.stop,
            Stop::new(0, "green after 2 attacks. Round complete.")
        );
        assert_eq!(
            who(&out),
            [
                "tester",
                "judge",
                "tester",
                "judge",
                "implementer",
                "judge",
                "tester",
                "judge",
                "implementer",
                "judge"
            ]
        );
        let kinds: Vec<_> = out
            .events
            .iter()
            .filter_map(|event| match event {
                Body::StepStart { kind, .. } => Some(kind.as_str()),
                _ => None,
            })
            .collect();
        assert_eq!(
            kinds,
            [
                "write", "run 1", "attack 1", "run 2", "fix 1", "run 3", "attack 2", "run 4",
                "fix 1", "run 5"
            ]
        );
    }

    #[test]
    fn the_round_stops_when_the_fixes_run_out() {
        let fake = Fake {
            lanes: vec![agent(1.0), agent(1.0)].into(),
            judges: vec![fail(), fail(), fail()].into(),
            ..Fake::default()
        };
        let out = run_with(Start::Judge, 2, fake, &AtomicBool::new(false));
        assert_eq!(
            out.stop,
            Stop::new(1, "still failing after 2 implementer runs")
        );
        assert_eq!(
            who(&out),
            ["judge", "implementer", "judge", "implementer", "judge"]
        );
        // Only the last fix run is told to dispute what it can't pass.
        assert!(!out.calls[1].1.contains(LAST_FIX), "{}", out.calls[1].1);
        assert!(out.calls[3].1.ends_with(LAST_FIX), "{}", out.calls[3].1);
    }

    #[test]
    fn a_broken_judge_stops_the_round() {
        let out = run(Start::Judge, vec![], vec![broken()]);
        assert_eq!(
            out.stop,
            Stop::new(
                2,
                "the test suite or harness is broken; see /cache/judge/results"
            )
        );
        let Body::JudgeDone {
            result,
            problem,
            passed,
            ..
        } = &out.events[1]
        else {
            panic!()
        };
        assert_eq!(
            (result.as_str(), problem.as_str(), *passed),
            ("broken", "harness: cargo vendor failed", None)
        );
    }

    #[test]
    fn a_question_stops_the_round_for_a_ruling() {
        let out = run(Start::Tester, vec![asking("QUESTION: 3.2: which?")], vec![]);
        assert_eq!(
            out.stop,
            Stop::new(3, "the tester ended with a question; it needs a ruling")
        );
        let Body::AgentDone {
            outcome, ruling, ..
        } = &out.events[1]
        else {
            panic!()
        };
        assert_eq!(
            (*outcome, ruling.as_str()),
            (crate::events::Outcome::Question, "QUESTION: 3.2: which?")
        );
    }

    #[test]
    fn a_dispute_from_the_implementer_stops_the_round() {
        let out = run(
            Start::Implementer,
            vec![asking("DISPUTE: 3.2 contradicts 3.1")],
            vec![],
        );
        assert_eq!(
            out.stop,
            Stop::new(3, "the implementer ended with a dispute; it needs a ruling")
        );
        assert_eq!(
            out.calls[0],
            ("implementer".into(), "Task: SPEC section 3".into())
        );
    }

    #[test]
    fn a_failed_lane_stops_the_round_with_its_status() {
        let out = run(Start::Tester, vec![exiting(4)], vec![]);
        assert_eq!(
            out.stop,
            Stop::new(4, "lane.sh stopped the tester with status 4 (left_lane)")
        );
        let out = run(Start::Judge, vec![exiting(1)], vec![fail()]);
        assert_eq!(
            out.stop,
            Stop::new(
                1,
                "lane.sh stopped the implementer with status 1 (claude_failed)"
            )
        );
        let Body::AgentDone { commit, usage, .. } = &out.events[3] else {
            panic!()
        };
        assert_eq!((commit.as_str(), usage), ("", &None));
    }

    #[test]
    fn an_interrupt_stops_the_round_after_the_running_step() {
        let flag = AtomicBool::new(false);
        let fake = Fake {
            lanes: vec![agent(1.0)].into(),
            judges: vec![pass()].into(),
            interrupt_at: Some((1, &flag)),
            ..Fake::default()
        };
        let out = run_with(Start::Tester, 5, fake, &flag);
        assert_eq!(out.stop, Stop::new(130, "the round was interrupted"));
        assert_eq!(who(&out), ["tester", "judge"]);
        // The interrupted judge run started but has no result.
        assert!(matches!(
            out.events.last(),
            Some(Body::StepStart { step: 2, .. })
        ));
    }

    #[test]
    fn a_runner_failure_stops_the_round() {
        let out = run(Start::Tester, vec![], vec![]);
        assert_eq!(out.stop.code, INTERNAL_ERROR);
        assert!(
            out.stop.reason.contains("no lane result scripted"),
            "{}",
            out.stop.reason
        );
    }

    #[test]
    fn events_record_each_step() {
        let out = run(Start::Judge, vec![agent(1.5)], vec![fail(), pass()]);
        let Body::JudgeDone {
            step,
            run,
            result,
            passed,
            failed,
            failing,
            summary_file,
            ..
        } = &out.events[1]
        else {
            panic!()
        };
        assert_eq!(
            (*step, *run, result.as_str(), *passed, *failed),
            (1, 1, "fail", Some(2), Some(1))
        );
        assert_eq!(failing, &["SPEC 3.2: 1 of 2 tests fail"]);
        assert!(
            summary_file.ends_with("round.d/01-judge-1.txt"),
            "{summary_file}"
        );
        let Body::AgentDone {
            step,
            role,
            kind,
            outcome,
            commit,
            message_file,
            ..
        } = &out.events[3]
        else {
            panic!()
        };
        assert_eq!(
            (*step, role.as_str(), kind.as_str()),
            (2, "implementer", "fix 1")
        );
        assert_eq!(
            (*outcome, commit.as_str()),
            (crate::events::Outcome::Ok, "server@abc1234")
        );
        assert!(
            message_file.ends_with("round.d/02-implementer-fix-1.md"),
            "{message_file}"
        );
    }
}
