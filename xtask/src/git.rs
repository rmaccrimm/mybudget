//! The few git queries the tooling needs, run through the git CLI with hooks and
//! fsmonitor off, as lane.sh runs it.

use std::path::Path;
use std::process::Command;

use anyhow::{Context, bail};

fn git(dir: &Path, args: &[&str]) -> anyhow::Result<String> {
    let out = Command::new("git")
        .args([
            "-c",
            "core.hooksPath=/dev/null",
            "-c",
            "core.fsmonitor=false",
            "-C",
        ])
        .arg(dir)
        .args(args)
        .output()
        .context("couldn't run git")?;
    if !out.status.success() {
        bail!(
            "git {} in {} failed: {}",
            args.join(" "),
            dir.display(),
            String::from_utf8_lossy(&out.stderr).trim()
        );
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

pub fn head(dir: &Path) -> anyhow::Result<String> {
    git(dir, &["rev-parse", "HEAD"])
}

pub fn short_head(dir: &Path) -> anyhow::Result<String> {
    git(dir, &["rev-parse", "--short", "HEAD"])
}

/// `git diff --shortstat`, e.g. "2 files changed, 201 insertions(+), 1 deletion(-)".
pub fn shortstat(dir: &Path, from: &str, to: &str) -> anyhow::Result<String> {
    git(dir, &["diff", "--shortstat", from, to])
}
