//! PTY session manager using portable-pty.

use anyhow::{anyhow, Result};
use portable_pty::{native_pty_system, CommandBuilder, MasterPty, PtySize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::sync::{Arc, Mutex};
use std::thread;
use tokio::sync::mpsc;
use uuid::Uuid;

pub struct PtyHandle {
    #[allow(dead_code)]
    pub id: String,
    writer: Arc<Mutex<Box<dyn Write + Send>>>,
    master: Arc<Mutex<Box<dyn MasterPty + Send>>>,
    _reader_thread: Option<thread::JoinHandle<()>>,
}

pub struct PtyManager {
    sessions: Mutex<HashMap<String, PtyHandle>>,
}

impl PtyManager {
    pub fn new() -> Self {
        Self {
            sessions: Mutex::new(HashMap::new()),
        }
    }

    pub fn open(
        &self,
        cols: u16,
        rows: u16,
        cwd: Option<&str>,
        shell: Option<&str>,
        data_tx: mpsc::UnboundedSender<(String, Vec<u8>)>,
    ) -> Result<String> {
        let pty_system = native_pty_system();
        let pair = pty_system.openpty(PtySize {
            rows,
            cols,
            pixel_width: 0,
            pixel_height: 0,
        })?;

        let shell_path = shell
            .map(|s| s.to_string())
            .unwrap_or_else(|| {
                std::env::var("SHELL").unwrap_or_else(|_| "/bin/bash".to_string())
            });

        let mut cmd = CommandBuilder::new(&shell_path);
        if let Some(dir) = cwd {
            cmd.cwd(dir);
        }
        cmd.env("TERM", "xterm-256color");

        let _child = pair.slave.spawn_command(cmd)?;
        drop(pair.slave);

        let id = Uuid::new_v4().to_string();
        let mut reader = pair.master.try_clone_reader()?;
        let writer = pair.master.take_writer()?;
        let master = pair.master;

        let id_clone = id.clone();
        let reader_thread = thread::spawn(move || {
            let mut buf = [0u8; 4096];
            loop {
                match reader.read(&mut buf) {
                    Ok(0) => break,
                    Ok(n) => {
                        if data_tx.send((id_clone.clone(), buf[..n].to_vec())).is_err() {
                            break;
                        }
                    }
                    Err(_) => break,
                }
            }
            let _ = data_tx.send((id_clone, Vec::new()));
        });

        let handle = PtyHandle {
            id: id.clone(),
            writer: Arc::new(Mutex::new(writer)),
            master: Arc::new(Mutex::new(master)),
            _reader_thread: Some(reader_thread),
        };

        self.sessions.lock().unwrap().insert(id.clone(), handle);
        Ok(id)
    }

    pub fn write(&self, id: &str, data: &[u8]) -> Result<()> {
        let sessions = self.sessions.lock().unwrap();
        let h = sessions
            .get(id)
            .ok_or_else(|| anyhow!("pty not found: {id}"))?;
        let mut w = h.writer.lock().unwrap();
        w.write_all(data)?;
        w.flush()?;
        Ok(())
    }

    pub fn resize(&self, id: &str, cols: u16, rows: u16) -> Result<()> {
        let sessions = self.sessions.lock().unwrap();
        let h = sessions
            .get(id)
            .ok_or_else(|| anyhow!("pty not found: {id}"))?;
        let master = h.master.lock().unwrap();
        master.resize(PtySize {
            rows,
            cols,
            pixel_width: 0,
            pixel_height: 0,
        })?;
        Ok(())
    }

    pub fn close(&self, id: &str) -> Result<()> {
        let mut sessions = self.sessions.lock().unwrap();
        if sessions.remove(id).is_none() {
            return Err(anyhow!("pty not found: {id}"));
        }
        Ok(())
    }

    pub fn open_params(
        &self,
        params: &Value,
        data_tx: mpsc::UnboundedSender<(String, Vec<u8>)>,
    ) -> Result<Value> {
        let cols = params.get("cols").and_then(|v| v.as_u64()).unwrap_or(80) as u16;
        let rows = params.get("rows").and_then(|v| v.as_u64()).unwrap_or(24) as u16;
        let cwd = params.get("cwd").and_then(|v| v.as_str());
        let shell = params.get("shell").and_then(|v| v.as_str());
        let id = self.open(cols, rows, cwd, shell, data_tx)?;
        Ok(json!({ "ptyId": id, "cols": cols, "rows": rows }))
    }
}
