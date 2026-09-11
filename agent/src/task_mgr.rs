//! Task runner: spawn command in workspace cwd, push task.output / task.exit.

use anyhow::{anyhow, Result};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::process::Stdio;
use std::sync::{Arc, Mutex};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::{Child, Command};
use tokio::sync::mpsc;
use uuid::Uuid;

pub type TaskEventTx = mpsc::UnboundedSender<(String, Value)>;

pub struct SharedTaskManager {
    inner: Arc<Mutex<HashMap<String, Child>>>,
}

impl SharedTaskManager {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub async fn run(&self, params: &Value, event_tx: TaskEventTx) -> Result<Value> {
        let cmd = params
            .get("command")
            .or_else(|| params.get("cmd"))
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow!("missing command"))?;
        let cwd = params
            .get("cwd")
            .and_then(|v| v.as_str())
            .unwrap_or(".");
        let shell = params
            .get("shell")
            .and_then(|v| v.as_bool())
            .unwrap_or(true);

        let task_id = Uuid::new_v4().to_string();
        let mut command = if shell {
            let mut c = Command::new("bash");
            c.arg("-lc").arg(cmd);
            c
        } else {
            let mut parts: Vec<String> = cmd.split_whitespace().map(|x| x.to_string()).collect();
            if parts.is_empty() {
                return Err(anyhow!("empty command"));
            }
            let prog = parts.remove(0);
            let mut c = Command::new(prog);
            c.args(parts);
            c
        };
        command
            .current_dir(cwd)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true);

        let mut child = command.spawn().map_err(|e| anyhow!("spawn failed: {e}"))?;
        let stdout = child.stdout.take();
        let stderr = child.stderr.take();

        let tid_out = task_id.clone();
        let tx_out = event_tx.clone();
        if let Some(out) = stdout {
            tokio::spawn(async move {
                let mut lines = BufReader::new(out).lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    let _ = tx_out.send((
                        tid_out.clone(),
                        json!({
                            "taskId": tid_out,
                            "stream": "stdout",
                            "data": format!("{line}\n"),
                        }),
                    ));
                }
            });
        }
        let tid_err = task_id.clone();
        let tx_err = event_tx.clone();
        if let Some(err) = stderr {
            tokio::spawn(async move {
                let mut lines = BufReader::new(err).lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    let _ = tx_err.send((
                        tid_err.clone(),
                        json!({
                            "taskId": tid_err,
                            "stream": "stderr",
                            "data": format!("{line}\n"),
                        }),
                    ));
                }
            });
        }

        self.inner.lock().unwrap().insert(task_id.clone(), child);

        let inner = self.inner.clone();
        let tid_wait = task_id.clone();
        let tx_wait = event_tx.clone();
        tokio::spawn(async move {
            let code = loop {
                let status = {
                    let mut map = inner.lock().unwrap();
                    match map.get_mut(&tid_wait) {
                        Some(child) => match child.try_wait() {
                            Ok(Some(st)) => Some(st.code().unwrap_or(-1)),
                            Ok(None) => None,
                            Err(_) => Some(-1),
                        },
                        None => Some(-1),
                    }
                };
                if let Some(c) = status {
                    break c;
                }
                tokio::time::sleep(std::time::Duration::from_millis(50)).await;
            };
            inner.lock().unwrap().remove(&tid_wait);
            let _ = tx_wait.send((
                tid_wait.clone(),
                json!({
                    "taskId": tid_wait,
                    "code": code,
                    "_event": "exit",
                }),
            ));
        });

        Ok(json!({ "taskId": task_id, "command": cmd, "cwd": cwd }))
    }

    pub fn kill(&self, params: &Value) -> Result<Value> {
        let task_id = params
            .get("taskId")
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow!("missing taskId"))?;
        let mut map = self.inner.lock().unwrap();
        if let Some(mut child) = map.remove(task_id) {
            let _ = child.start_kill();
            Ok(json!({ "ok": true, "taskId": task_id }))
        } else {
            Err(anyhow!("task not found: {task_id}"))
        }
    }
}
