/**
 * Terminal ArkTS ↔ Web 桥接
 * - Web → ArkTS: TerminalBridge.onReady / onData / onResize
 * - ArkTS → Web: window.__hmTerm.*
 */
(function (global) {
  'use strict';

  var state = {
    ready: false,
    mode: 'local', // local interactive
    cols: 80,
    rows: 24
  };

  function postToNative(method, payload) {
    try {
      if (typeof TerminalBridge !== 'undefined' && TerminalBridge && typeof TerminalBridge[method] === 'function') {
        if (payload === undefined) {
          TerminalBridge[method]();
        } else if (typeof payload === 'string') {
          TerminalBridge[method](payload);
        } else {
          TerminalBridge[method](JSON.stringify(payload));
        }
        return;
      }
    } catch (e) { /* ignore */ }
  }

  function notifyReady() {
    state.ready = true;
    postToNative('onReady', { cols: state.cols, rows: state.rows, mode: state.mode });
  }

  function notifyData(data) {
    postToNative('onData', data);
  }

  function notifyResize(cols, rows) {
    state.cols = cols;
    state.rows = rows;
    postToNative('onResize', { cols: cols, rows: rows });
  }

  global.__hmTerm = {
    getState: function () { return state; },
    setMode: function (mode) {
      state.mode = mode === 'ssh' ? 'ssh' : 'local';
      try {
        document.body.setAttribute('data-mode', state.mode);
      } catch (e) { /* ignore */ }
      if (global.__hmTermSession && global.__hmTermSession.onMode) {
        global.__hmTermSession.onMode(state.mode);
      }
    },
    write: function (text) {
      if (global.__hmTermSession && global.__hmTermSession.write) {
        global.__hmTermSession.write(text == null ? '' : String(text));
      }
    },
    writeBase64: function (b64) {
      try {
        var bin = atob(b64);
        var arr = new Uint8Array(bin.length);
        for (var i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
        if (global.__hmTermSession && global.__hmTermSession.writeUtf8) {
          global.__hmTermSession.writeUtf8(arr);
        } else if (global.__hmTermSession && global.__hmTermSession.write) {
          global.__hmTermSession.write(bin);
        }
      } catch (e) { /* ignore */ }
    },
    clear: function () {
      if (global.__hmTermSession && global.__hmTermSession.clear) {
        global.__hmTermSession.clear();
      }
    },
    fit: function () {
      if (global.__hmTermSession && global.__hmTermSession.fit) {
        global.__hmTermSession.fit();
      }
    },
    focus: function () {
      if (global.__hmTermSession && global.__hmTermSession.focus) {
        global.__hmTermSession.focus();
      }
    },
    _notifyReady: notifyReady,
    _notifyData: notifyData,
    _notifyResize: notifyResize
  };
})(window);
