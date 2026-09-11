//! Filesystem watch manager using notify crate. Pushes fs.changed events.

use anyhow::{anyhow, Result};
use notify::{Config, Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use tokio::sync::mpsc;
use uuid::Uuid;

pub type FsChangedTx = mpsc::UnboundedSender<(String, Value)>;

struct WatchEntry {
    path: PathBuf,
    _watcher: RecommendedWatcher,
}

pub struct WatchManager {
    watches: Mutex<HashMap<String, WatchEntry>>,
}

impl WatchManager {
    pub fn new() -> Self {
        Self {
            watches: Mutex::new(HashMap::new()),
        }
    }

    pub fn watch(&self, params: &Value, changed_tx: FsChangedTx) -> Result<Value> {
        let path = params
            .get("path")
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow!("missing path"))?;
        let recursive = params
            .get("recursive")
            .and_then(|v| v.as_bool())
            .unwrap_or(true);
        let p = PathBuf::from(path);
        if !p.exists() {
            return Err(anyhow!("path not found: {path}"));
        }

        let watch_id = Uuid::new_v4().to_string();
        let wid = watch_id.clone();
        let root = p.clone();

        let mut watcher = RecommendedWatcher::new(
            move |res: Result<Event, notify::Error>| {
                if let Ok(event) = res {
                    let kind = match event.kind {
                        EventKind::Create(_) => "create",
                        EventKind::Modify(_) => "modify",
                        EventKind::Remove(_) => "remove",
                        EventKind::Any => "any",
                        _ => "other",
                    };
                    let paths: Vec<String> = event
                        .paths
                        .iter()
                        .map(|x| x.to_string_lossy().to_string())
                        .collect();
                    if paths.is_empty() {
                        return;
                    }
                    let params = json!({
                        "watchId": wid,
                        "kind": kind,
                        "paths": paths,
                        "root": root.to_string_lossy(),
                    });
                    let _ = changed_tx.send((wid.clone(), params));
                }
            },
            Config::default(),
        )?;

        let mode = if recursive {
            RecursiveMode::Recursive
        } else {
            RecursiveMode::NonRecursive
        };
        watcher.watch(&p, mode)?;

        self.watches.lock().unwrap().insert(
            watch_id.clone(),
            WatchEntry {
                path: p,
                _watcher: watcher,
            },
        );

        Ok(json!({ "watchId": watch_id, "path": path, "recursive": recursive }))
    }

    pub fn unwatch(&self, params: &Value) -> Result<Value> {
        let watch_id = params
            .get("watchId")
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow!("missing watchId"))?;
        let mut map = self.watches.lock().unwrap();
        if map.remove(watch_id).is_none() {
            return Err(anyhow!("watch not found: {watch_id}"));
        }
        Ok(json!({ "ok": true, "watchId": watch_id }))
    }

    pub fn clear_all(&self) {
        self.watches.lock().unwrap().clear();
    }
}

/// Shared across sockets so watch events can be multiplexed.
pub type SharedWatchManager = Arc<WatchManager>;
