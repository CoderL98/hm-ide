/**
 * xterm.js：本地行缓冲交互壳的前端仿真器（非 OS PTY 驱动）。
 */
(function () {
  'use strict';

  function boot() {
    var Terminal = window.Terminal;
    var FitAddonNS = window.FitAddon;
    if (!Terminal) {
      document.getElementById('term').textContent = 'xterm 未能加载';
      return;
    }

    var fitAddon = FitAddonNS && FitAddonNS.FitAddon
      ? new FitAddonNS.FitAddon()
      : (FitAddonNS ? new FitAddonNS() : null);

    var term = new Terminal({
      cursorBlink: true,
      fontSize: 13,
      fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
      theme: {
        background: '#09090b',
        foreground: '#e4e4e7',
        cursor: '#e4e4e7',
        selectionBackground: '#3f3f46'
      },
      convertEol: false,
      scrollback: 4000
    });

    if (fitAddon) {
      term.loadAddon(fitAddon);
    }
    term.open(document.getElementById('term'));

    function doFit() {
      try {
        if (fitAddon) fitAddon.fit();
        window.__hmTerm._notifyResize(term.cols, term.rows);
      } catch (e) { /* ignore */ }
    }

    window.__hmTermSession = {
      write: function (t) { term.write(t); },
      writeUtf8: function (u8) {
        try { term.write(u8); } catch (e) {
          var s = '';
          for (var i = 0; i < u8.length; i++) s += String.fromCharCode(u8[i]);
          term.write(s);
        }
      },
      clear: function () { term.clear(); },
      fit: doFit,
      focus: function () { term.focus(); },
      onMode: function (_mode) { term.focus(); }
    };

    term.onData(function (data) {
      window.__hmTerm._notifyData(data);
    });

    term.onResize(function (size) {
      window.__hmTerm._notifyResize(size.cols, size.rows);
    });

    window.addEventListener('resize', function () { doFit(); });

    setTimeout(function () {
      doFit();
      window.__hmTerm.setMode('local');
      window.__hmTerm._notifyReady();
      term.focus();
    }, 40);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
