//! Git status / diff summary via git2 (libgit2).

use anyhow::{anyhow, Result};
use git2::{Delta, Repository, StatusOptions, StatusShow};
use serde_json::{json, Value};
use std::path::Path;

pub fn status(params: &Value) -> Result<Value> {
    let path = params
        .get("path")
        .or_else(|| params.get("cwd"))
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow!("missing path"))?;
    let repo = Repository::discover(path)
        .map_err(|e| anyhow!("not a git repo under {path}: {e}"))?;

    let mut opts = StatusOptions::new();
    opts.include_untracked(true)
        .recurse_untracked_dirs(true)
        .include_ignored(false)
        .show(StatusShow::IndexAndWorkdir);

    let statuses = repo.statuses(Some(&mut opts))?;
    let mut items = Vec::new();
    for entry in statuses.iter() {
        let path_str = entry.path().unwrap_or("").to_string();
        let st = entry.status();
        let mut kinds = Vec::new();
        if st.is_index_new() || st.is_wt_new() {
            kinds.push(if st.is_wt_new() && !st.is_index_new() {
                "untracked"
            } else {
                "added"
            });
        }
        if st.is_index_modified() || st.is_wt_modified() {
            kinds.push("modified");
        }
        if st.is_index_deleted() || st.is_wt_deleted() {
            kinds.push("deleted");
        }
        if st.is_index_renamed() || st.is_wt_renamed() {
            kinds.push("renamed");
        }
        if st.is_conflicted() {
            kinds.push("conflicted");
        }
        if kinds.is_empty() {
            kinds.push("unknown");
        }
        items.push(json!({
            "path": path_str,
            "status": kinds[0],
            "statuses": kinds,
            "inIndex": st.is_index_new() || st.is_index_modified() || st.is_index_deleted() || st.is_index_renamed(),
            "inWorkdir": st.is_wt_new() || st.is_wt_modified() || st.is_wt_deleted() || st.is_wt_renamed(),
        }));
    }

    let head = repo.head().ok();
    let branch = head
        .as_ref()
        .and_then(|h| h.shorthand().map(|s| s.to_string()))
        .unwrap_or_else(|| "DETACHED".into());
    let commit = head
        .as_ref()
        .and_then(|h| h.target().map(|oid| oid.to_string()))
        .unwrap_or_default();

    let workdir = repo
        .workdir()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_default();

    Ok(json!({
        "branch": branch,
        "commit": commit,
        "workdir": workdir,
        "items": items,
        "clean": items.is_empty(),
    }))
}

pub fn diff_summary(params: &Value) -> Result<Value> {
    let path = params
        .get("path")
        .or_else(|| params.get("cwd"))
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow!("missing path"))?;
    let repo = Repository::discover(path)
        .map_err(|e| anyhow!("not a git repo under {path}: {e}"))?;

    let mut opts = git2::DiffOptions::new();
    opts.include_untracked(true);

    // Workdir vs HEAD (or empty tree if no commits)
    let diff = match repo.head().ok().and_then(|h| h.peel_to_tree().ok()) {
        Some(tree) => repo.diff_tree_to_workdir_with_index(Some(&tree), Some(&mut opts))?,
        None => repo.diff_tree_to_workdir_with_index(None, Some(&mut opts))?,
    };

    let stats = diff.stats()?;
    let mut files = Vec::new();
    for delta in diff.deltas() {
        let status = match delta.status() {
            Delta::Added => "added",
            Delta::Deleted => "deleted",
            Delta::Modified => "modified",
            Delta::Renamed => "renamed",
            Delta::Copied => "copied",
            Delta::Ignored => "ignored",
            Delta::Untracked => "untracked",
            Delta::Typechange => "typechange",
            Delta::Unreadable => "unreadable",
            Delta::Conflicted => "conflicted",
            Delta::Unmodified => "unmodified",
        };
        let new_path = delta
            .new_file()
            .path()
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_default();
        let old_path = delta
            .old_file()
            .path()
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_default();
        files.push(json!({
            "status": status,
            "path": if new_path.is_empty() { old_path.clone() } else { new_path },
            "oldPath": old_path,
        }));
    }

    Ok(json!({
        "filesChanged": stats.files_changed(),
        "insertions": stats.insertions(),
        "deletions": stats.deletions(),
        "files": files,
    }))
}

#[allow(dead_code)]
pub fn is_repo(path: &Path) -> bool {
    Repository::discover(path).is_ok()
}
