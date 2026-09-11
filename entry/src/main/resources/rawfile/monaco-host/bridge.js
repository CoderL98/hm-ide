/**
 * ArkTS ↔ Web 桥接层
 * - ArkTS 通过 Web.runJavaScript 调用 window.__hmIde.*
 * - Web 通过 IdeBridge（JavaScriptProxy）或 console 回调通知原生
 */
(function (global) {
  'use strict';

  var state = {
    ready: false,
    language: 'typescript',
    theme: 'vs-dark',
    fontSize: 13,
    tabSize: 2,
    value: '',
    engine: 'pending' // monaco | fallback
  };

  function postToNative(method, payload) {
    try {
      if (typeof IdeBridge !== 'undefined' && IdeBridge && typeof IdeBridge[method] === 'function') {
        if (payload === undefined) {
          IdeBridge[method]();
        } else if (typeof payload === 'string') {
          IdeBridge[method](payload);
        } else {
          IdeBridge[method](JSON.stringify(payload));
        }
        return;
      }
    } catch (e) { /* ignore */ }
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.IdeBridge) {
        window.webkit.messageHandlers.IdeBridge.postMessage({ method: method, payload: payload });
      }
    } catch (e2) { /* ignore */ }
  }

  function notifyReady() {
    state.ready = true;
    postToNative('onReady', { engine: state.engine });
  }

  function notifyChange(value) {
    state.value = value;
    postToNative('onChange', value);
  }

  function notifySave() {
    postToNative('onSaveRequest', state.value);
  }

  global.__hmIde = {
    getState: function () { return state; },
    setValue: function (text) {
      state.value = text == null ? '' : String(text);
      if (global.__hmIdeEditor && global.__hmIdeEditor.setValue) {
        global.__hmIdeEditor.setValue(state.value);
      }
    },
    getValue: function () {
      if (global.__hmIdeEditor && global.__hmIdeEditor.getValue) {
        state.value = global.__hmIdeEditor.getValue();
      }
      return state.value;
    },
    setLanguage: function (lang) {
      state.language = lang || 'plaintext';
      if (global.__hmIdeEditor && global.__hmIdeEditor.setLanguage) {
        global.__hmIdeEditor.setLanguage(state.language);
      }
    },
    setTheme: function (theme) {
      var t = theme || 'dark';
      if (t === 'dark' || t === 'system') t = 'vs-dark';
      if (t === 'light') t = 'vs';
      state.theme = t;
      document.body.setAttribute('data-theme', t === 'vs' ? 'light' : 'dark');
      if (global.__hmIdeEditor && global.__hmIdeEditor.setTheme) {
        global.__hmIdeEditor.setTheme(state.theme);
      }
    },
    setFontSize: function (n) {
      state.fontSize = Number(n) || 13;
      if (global.__hmIdeEditor && global.__hmIdeEditor.setFontSize) {
        global.__hmIdeEditor.setFontSize(state.fontSize);
      }
    },
    setTabSize: function (n) {
      state.tabSize = Number(n) || 2;
      if (global.__hmIdeEditor && global.__hmIdeEditor.setTabSize) {
        global.__hmIdeEditor.setTabSize(state.tabSize);
      }
    },
    focus: function () {
      if (global.__hmIdeEditor && global.__hmIdeEditor.focus) {
        global.__hmIdeEditor.focus();
      }
    },
    triggerFind: function () {
      if (global.__hmIdeEditor && global.__hmIdeEditor.triggerFind) {
        global.__hmIdeEditor.triggerFind();
      }
    },
    triggerReplace: function () {
      if (global.__hmIdeEditor && global.__hmIdeEditor.triggerReplace) {
        global.__hmIdeEditor.triggerReplace();
      }
    },
    revealLine: function (line, column) {
      if (global.__hmIdeEditor && global.__hmIdeEditor.revealLine) {
        global.__hmIdeEditor.revealLine(Number(line) || 1, Number(column) || 1);
      }
    },
    dump: function () {
      return JSON.stringify({
        value: global.__hmIde.getValue(),
        language: state.language,
        theme: state.theme,
        engine: state.engine,
        ready: state.ready
      });
    },
    _notifyReady: notifyReady,
    _notifyChange: notifyChange,
    _notifySave: notifySave,
    _setEngine: function (e) {
      state.engine = e;
      var pill = document.getElementById('modePill');
      if (pill) pill.textContent = e;
    }
  };
})(window);
