//! Efficient filesystem search (ripgrep-like walk with ignore).

use anyhow::{anyhow, Result};
use ignore::WalkBuilder;
use regex::RegexBuilder;
use serde_json::{json, Value};
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::Path;

const SKIP_DIRS: &[&str] = &[
    "node_modules",
    "target",
    ".git",
    "oh_modules",
    "build",
    ".hvigor",
    "dist",
    "__pycache__",
    ".cache",
];

pub fn search(params: &Value) -> Result<Value> {
    let root = params
        .get("path")
        .or_else(|| params.get("root"))
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow!("missing path"))?;
    let query = params
        .get("query")
        .or_else(|| params.get("pattern"))
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow!("missing query"))?;
    if query.is_empty() {
        return Ok(json!({ "hits": [], "truncated": false }));
    }
    let case_insensitive = params
        .get("caseInsensitive")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);
    let max_hits = params
        .get("maxHits")
        .and_then(|v| v.as_u64())
        .unwrap_or(200) as usize;
    let max_file_bytes = params
        .get("maxFileBytes")
        .and_then(|v| v.as_u64())
        .unwrap_or(2 * 1024 * 1024) as u64;
    let use_regex = params
        .get("regex")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    let re = if use_regex {
        RegexBuilder::new(query)
            .case_insensitive(case_insensitive)
            .build()
            .map_err(|e| anyhow!("invalid regex: {e}"))?
    } else {
        let escaped = regex::escape(query);
        RegexBuilder::new(&escaped)
            .case_insensitive(case_insensitive)
            .build()
            .map_err(|e| anyhow!("regex build: {e}"))?
    };

    let root_path = Path::new(root);
    if !root_path.is_dir() {
        return Err(anyhow!("not a directory: {root}"));
    }

    let mut builder = WalkBuilder::new(root_path);
    builder.hidden(false);
    builder.git_ignore(true);
    builder.git_global(true);
    builder.git_exclude(true);
    builder.filter_entry(|entry| {
        if entry.file_type().map(|t| t.is_dir()).unwrap_or(false) {
            let name = entry.file_name().to_string_lossy();
            if SKIP_DIRS.iter().any(|s| *s == name) {
                return false;
            }
        }
        true
    });

    let mut hits = Vec::new();
    let mut truncated = false;

    for result in builder.build() {
        if hits.len() >= max_hits {
            truncated = true;
            break;
        }
        let entry = match result {
            Ok(e) => e,
            Err(_) => continue,
        };
        if !entry.file_type().map(|t| t.is_file()).unwrap_or(false) {
            continue;
        }
        let path = entry.path();
        if let Ok(meta) = entry.metadata() {
            if meta.len() > max_file_bytes {
                continue;
            }
        }
        // Skip likely-binary by extension
        if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
            let el = ext.to_lowercase();
            if matches!(
                el.as_str(),
                "png" | "jpg" | "jpeg" | "gif" | "webp" | "ico" | "so" | "a" | "o" | "bin"
                    | "exe" | "dll" | "zip" | "jar" | "wasm" | "pdf" | "mp4" | "mp3"
            ) {
                continue;
            }
        }

        let file = match File::open(path) {
            Ok(f) => f,
            Err(_) => continue,
        };
        let reader = BufReader::new(file);
        for (idx, line_res) in reader.lines().enumerate() {
            if hits.len() >= max_hits {
                truncated = true;
                break;
            }
            let line = match line_res {
                Ok(l) => l,
                Err(_) => break, // binary-ish
            };
            if re.is_match(&line) {
                let preview: String = line.chars().take(240).collect();
                let abs = path.to_string_lossy().to_string();
                let rel = path
                    .strip_prefix(root_path)
                    .map(|p| p.to_string_lossy().to_string())
                    .unwrap_or_else(|_| abs.clone());
                hits.push(json!({
                    "path": abs,
                    "relPath": rel,
                    "line": idx + 1,
                    "preview": preview,
                }));
            }
        }
    }

    Ok(json!({ "hits": hits, "truncated": truncated, "count": hits.len() }))
}
