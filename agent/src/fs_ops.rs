//! Filesystem operations for the remote agent.

use crate::protocol::{FsEntry, FsStat};
use anyhow::{anyhow, Context, Result};
use serde_json::{json, Value};
use std::fs;
use std::path::PathBuf;
use std::time::SystemTime;

fn mtime_ms(meta: &fs::Metadata) -> u64 {
    meta.modified()
        .ok()
        .and_then(|t| t.duration_since(SystemTime::UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

fn resolve(path: &str) -> Result<PathBuf> {
    if path.is_empty() {
        return Err(anyhow!("empty path"));
    }
    Ok(PathBuf::from(path))
}

pub fn list(params: &Value) -> Result<Value> {
    let path = params
        .get("path")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow!("missing path"))?;
    let p = resolve(path)?;
    let rd = fs::read_dir(&p).with_context(|| format!("read_dir {}", p.display()))?;
    let mut entries: Vec<FsEntry> = Vec::new();
    for ent in rd {
        let ent = ent?;
        let meta = ent.metadata()?;
        let name = ent.file_name().to_string_lossy().to_string();
        let full = ent.path().to_string_lossy().to_string();
        entries.push(FsEntry {
            name,
            path: full,
            is_dir: meta.is_dir(),
            size: if meta.is_file() { meta.len() } else { 0 },
            mtime_ms: mtime_ms(&meta),
        });
    }
    entries.sort_by(|a, b| match (a.is_dir, b.is_dir) {
        (true, false) => std::cmp::Ordering::Less,
        (false, true) => std::cmp::Ordering::Greater,
        _ => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
    });
    Ok(json!({ "entries": entries }))
}

pub fn read(params: &Value) -> Result<Value> {
    let path = params
        .get("path")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow!("missing path"))?;
    let encoding = params
        .get("encoding")
        .and_then(|v| v.as_str())
        .unwrap_or("utf8");
    let p = resolve(path)?;
    let bytes = fs::read(&p).with_context(|| format!("read {}", p.display()))?;
    if encoding == "base64" {
        use base64::{engine::general_purpose::STANDARD, Engine};
        Ok(json!({
            "path": path,
            "encoding": "base64",
            "data": STANDARD.encode(&bytes),
            "size": bytes.len()
        }))
    } else {
        let text = String::from_utf8_lossy(&bytes).to_string();
        Ok(json!({
            "path": path,
            "encoding": "utf8",
            "data": text,
            "size": bytes.len()
        }))
    }
}

pub fn write(params: &Value) -> Result<Value> {
    let path = params
        .get("path")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow!("missing path"))?;
    let encoding = params
        .get("encoding")
        .and_then(|v| v.as_str())
        .unwrap_or("utf8");
    let data = params
        .get("data")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow!("missing data"))?;
    let p = resolve(path)?;
    if let Some(parent) = p.parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent)?;
        }
    }
    let bytes: Vec<u8> = if encoding == "base64" {
        use base64::{engine::general_purpose::STANDARD, Engine};
        STANDARD
            .decode(data)
            .map_err(|e| anyhow!("base64 decode: {e}"))?
    } else {
        data.as_bytes().to_vec()
    };
    fs::write(&p, &bytes).with_context(|| format!("write {}", p.display()))?;
    Ok(json!({ "path": path, "size": bytes.len() }))
}

pub fn mkdir(params: &Value) -> Result<Value> {
    let path = params
        .get("path")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow!("missing path"))?;
    let p = resolve(path)?;
    fs::create_dir_all(&p).with_context(|| format!("mkdir {}", p.display()))?;
    Ok(json!({ "path": path }))
}

pub fn remove(params: &Value) -> Result<Value> {
    let path = params
        .get("path")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow!("missing path"))?;
    let recursive = params
        .get("recursive")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);
    let p = resolve(path)?;
    if !p.exists() {
        return Err(anyhow!("not found: {}", p.display()));
    }
    if p.is_dir() {
        if recursive {
            fs::remove_dir_all(&p)?;
        } else {
            fs::remove_dir(&p)?;
        }
    } else {
        fs::remove_file(&p)?;
    }
    Ok(json!({ "path": path, "ok": true }))
}

pub fn rename(params: &Value) -> Result<Value> {
    let from = params
        .get("from")
        .or_else(|| params.get("path"))
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow!("missing from"))?;
    let to = params
        .get("to")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow!("missing to"))?;
    let src = resolve(from)?;
    let dst = resolve(to)?;
    if let Some(parent) = dst.parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent)?;
        }
    }
    fs::rename(&src, &dst).with_context(|| format!("rename {} -> {}", src.display(), dst.display()))?;
    Ok(json!({ "from": from, "to": to }))
}

pub fn stat(params: &Value) -> Result<Value> {
    let path = params
        .get("path")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow!("missing path"))?;
    let p = resolve(path)?;
    let meta = fs::metadata(&p).with_context(|| format!("stat {}", p.display()))?;
    #[cfg(unix)]
    let mode = {
        use std::os::unix::fs::PermissionsExt;
        meta.permissions().mode()
    };
    #[cfg(not(unix))]
    let mode = 0u32;
    let s = FsStat {
        path: path.to_string(),
        is_dir: meta.is_dir(),
        is_file: meta.is_file(),
        size: meta.len(),
        mtime_ms: mtime_ms(&meta),
        mode,
    };
    Ok(serde_json::to_value(s)?)
}

