//! Where things live: the repo checkout and the cache the scripts share
//! (`$MYBUDGET_CACHE`, by default `~/.cache/mybudget`).

use std::fmt;
use std::path::{Path, PathBuf};

use anyhow::Context;

/// The two agents. Each one works in its own submodule, its lane.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    Tester,
    Implementer,
}

impl Role {
    pub fn name(self) -> &'static str {
        match self {
            Role::Tester => "tester",
            Role::Implementer => "implementer",
        }
    }

    /// The submodule the role works in.
    pub fn lane(self) -> &'static str {
        match self {
            Role::Tester => "testsuite",
            Role::Implementer => "server",
        }
    }
}

impl fmt::Display for Role {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.name())
    }
}

#[derive(Debug, Clone)]
pub struct Paths {
    pub root: PathBuf,
    pub cache: PathBuf,
}

impl Paths {
    /// `cache` is `--cache`/`$MYBUDGET_CACHE`; without it, `~/.cache/mybudget`.
    pub fn new(cache: Option<PathBuf>) -> anyhow::Result<Self> {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .context("xtask's manifest directory has no parent")?
            .to_path_buf();
        let cache = match cache {
            Some(cache) => cache,
            None => PathBuf::from(std::env::var_os("HOME").context("HOME is not set")?)
                .join(".cache/mybudget"),
        };
        // The scripts get this path too, and they run in other directories.
        let cache = std::path::absolute(&cache)
            .with_context(|| format!("can't make {} absolute", cache.display()))?;
        Ok(Paths { root, cache })
    }

    pub fn script(&self, name: &str) -> PathBuf {
        self.root.join("scripts").join(name)
    }

    pub fn lane_dir(&self, role: Role) -> PathBuf {
        self.root.join(role.lane())
    }

    pub fn tests_dir(&self) -> PathBuf {
        self.root.join("testsuite/tests")
    }

    /// Where lane.sh leaves a role's `last-output.md` and `last-run.json`.
    pub fn role_state(&self, role: Role) -> PathBuf {
        self.cache.join(role.name())
    }

    /// Where judge.sh leaves `summary.txt` and its logs.
    pub fn judge_results(&self) -> PathBuf {
        self.cache.join("judge/results")
    }

    /// One line per agent run, appended by lane.sh.
    pub fn usage_ledger(&self) -> PathBuf {
        self.cache.join("usage.jsonl")
    }

    pub fn events_dir(&self) -> PathBuf {
        self.cache.join("events")
    }
}
