/**
 * 优先加载本地 Monaco AMD；失败则启用高保真 fallback（原型视觉）。
 * 注册 arkts 语言（基于 typescript + Harmony 装饰器）。
 */
(function () {
  'use strict';

  var FALLBACK_TIMEOUT_MS = 4000;
  var booted = false;

  function markBooted() {
    if (booted) return;
    booted = true;
  }

  function mapLanguage(lang) {
    if (!lang) return 'typescript';
    var l = String(lang).toLowerCase();
    if (l === 'ets' || l === 'arkts') return 'arkts';
    if (l === 'ts') return 'typescript';
    if (l === 'json5') return 'json';
    if (l === 'js') return 'javascript';
    return l;
  }

  function registerArkTS(monaco) {
    try {
      if (monaco.languages.getLanguages().some(function (x) { return x.id === 'arkts'; })) {
        return;
      }
    } catch (e) { /* continue */ }

    monaco.languages.register({
      id: 'arkts',
      extensions: ['.ets'],
      aliases: ['ArkTS', 'arkts', 'ETS']
    });

    // Monarch：以 TypeScript 为基，强调 Harmony 装饰器
    var arktsKeywords = [
      'abstract', 'any', 'as', 'asserts', 'async', 'await', 'boolean', 'break', 'case', 'catch',
      'class', 'const', 'constructor', 'continue', 'debugger', 'declare', 'default', 'delete',
      'do', 'else', 'enum', 'export', 'extends', 'false', 'finally', 'for', 'from', 'function',
      'get', 'if', 'implements', 'import', 'in', 'infer', 'instanceof', 'interface', 'is', 'keyof',
      'let', 'module', 'namespace', 'never', 'new', 'null', 'number', 'object', 'of', 'package',
      'private', 'protected', 'public', 'readonly', 'require', 'return', 'set', 'static', 'string',
      'struct', 'super', 'switch', 'symbol', 'this', 'throw', 'true', 'try', 'type', 'typeof',
      'undefined', 'unique', 'unknown', 'var', 'void', 'while', 'with', 'yield'
    ];

    monaco.languages.setMonarchTokensProvider('arkts', {
      defaultToken: '',
      tokenPostfix: '.arkts',
      keywords: arktsKeywords,
      // Harmony / ArkUI 装饰器
      decorators: [
        'Entry', 'Component', 'ComponentV2', 'Builder', 'BuilderParam', 'State', 'Prop', 'Link',
        'Provide', 'Consume', 'ObjectLink', 'Observed', 'ObservedV2', 'Trace', 'Watch', 'Require',
        'Reusable', 'CustomDialog', 'Styles', 'Extend', 'AnimatableExtend', 'Preview', 'Concurrent',
        'Sendable', 'LocalStorageLink', 'LocalStorageProp', 'StorageLink', 'StorageProp',
        'Local', 'Param', 'Event', 'Once', 'Monitor', 'Computed'
      ],
      operators: [
        '<=', '>=', '==', '!=', '===', '!==', '=>', '+', '-', '**', '*', '/', '%', '++', '--',
        '<<', '</', '>>', '>>>', '&', '|', '^', '!', '~', '&&', '||', '??', '?', ':', '=', '+=',
        '-=', '*=', '**=', '/=', '%=', '<<=', '>>=', '>>>=', '&=', '|=', '^=', '@'
      ],
      symbols: /[=><!~?:&|+\-*\/\^%]+/,
      escapes: /\\(?:[abfnrtv\\"']|x[0-9A-Fa-f]{1,4}|u[0-9A-Fa-f]{4}|U[0-9A-Fa-f]{8})/,
      tokenizer: {
        root: [
          [/@[a-zA-Z_]\w*/, {
            cases: {
              '@decorators': 'annotation',
              '@default': 'annotation'
            }
          }],
          [/[a-zA-Z_$][\w$]*/, {
            cases: {
              '@keywords': 'keyword',
              '@default': 'identifier'
            }
          }],
          { include: '@whitespace' },
          [/[{}()\[\]]/, '@brackets'],
          [/[<>](?!@symbols)/, '@brackets'],
          [/@symbols/, {
            cases: {
              '@operators': 'operator',
              '@default': ''
            }
          }],
          [/\d*\.\d+([eE][\-+]?\d+)?/, 'number.float'],
          [/0[xX][0-9a-fA-F]+/, 'number.hex'],
          [/\d+/, 'number'],
          [/[;,.]/, 'delimiter'],
          [/"([^"\\]|\\.)*$/, 'string.invalid'],
          [/'([^'\\]|\\.)*$/, 'string.invalid'],
          [/"/, 'string', '@string_double'],
          [/'/, 'string', '@string_single'],
          [/`/, 'string', '@string_backtick']
        ],
        whitespace: [
          [/[ \t\r\n]+/, ''],
          [/\/\*\*(?!\/)/, 'comment.doc', '@jsdoc'],
          [/\/\*/, 'comment', '@comment'],
          [/\/\/.*$/, 'comment']
        ],
        comment: [
          [/[^\/*]+/, 'comment'],
          [/\*\//, 'comment', '@pop'],
          [/[\/*]/, 'comment']
        ],
        jsdoc: [
          [/[^\/*]+/, 'comment.doc'],
          [/\*\//, 'comment.doc', '@pop'],
          [/[\/*]/, 'comment.doc']
        ],
        string_double: [
          [/[^\\"]+/, 'string'],
          [/@escapes/, 'string.escape'],
          [/\\./, 'string.escape.invalid'],
          [/"/, 'string', '@pop']
        ],
        string_single: [
          [/[^\\']+/, 'string'],
          [/@escapes/, 'string.escape'],
          [/\\./, 'string.escape.invalid'],
          [/'/, 'string', '@pop']
        ],
        string_backtick: [
          [/\$\{/, { token: 'delimiter.bracket', next: '@bracketCounting' }],
          [/[^\\`$]+/, 'string'],
          [/@escapes/, 'string.escape'],
          [/\\./, 'string.escape.invalid'],
          [/`/, 'string', '@pop']
        ],
        bracketCounting: [
          [/\{/, 'delimiter.bracket', '@bracketCounting'],
          [/\}/, 'delimiter.bracket', '@pop'],
          { include: 'root' }
        ]
      }
    });

    monaco.languages.setLanguageConfiguration('arkts', {
      comments: { lineComment: '//', blockComment: ['/*', '*/'] },
      brackets: [['{', '}'], ['[', ']'], ['(', ')']],
      autoClosingPairs: [
        { open: '{', close: '}' },
        { open: '[', close: ']' },
        { open: '(', close: ')' },
        { open: '"', close: '"', notIn: ['string'] },
        { open: "'", close: "'", notIn: ['string'] },
        { open: '`', close: '`', notIn: ['string'] }
      ],
      surroundingPairs: [
        { open: '{', close: '}' },
        { open: '[', close: ']' },
        { open: '(', close: ')' },
        { open: '"', close: '"' },
        { open: "'", close: "'" },
        { open: '`', close: '`' }
      ]
    });
  }

  function bootMonaco() {
    if (typeof require === 'undefined') {
      bootFallback('no-amd-loader');
      return;
    }
    try {
      require.config({
        paths: { vs: './vs' },
        'vs/nls': { availableLanguages: { '*': 'zh-cn' } }
      });
    } catch (e) {
      bootFallback('require-config-failed');
      return;
    }

    var timer = setTimeout(function () {
      if (!booted) bootFallback('monaco-timeout');
    }, FALLBACK_TIMEOUT_MS);

    require(['vs/editor/editor.main'], function () {
      clearTimeout(timer);
      if (booted && window.__hmIde.getState().engine === 'fallback') {
        return;
      }
      markBooted();
      var root = document.getElementById('root');
      document.getElementById('fallback').classList.remove('shown');
      root.style.display = 'block';

      registerArkTS(monaco);

      var editor = monaco.editor.create(root, {
        value: window.__hmIde.getState().value || '',
        language: mapLanguage(window.__hmIde.getState().language),
        theme: window.__hmIde.getState().theme || 'vs-dark',
        fontSize: window.__hmIde.getState().fontSize || 13,
        tabSize: window.__hmIde.getState().tabSize || 2,
        automaticLayout: true,
        minimap: { enabled: false },
        scrollBeyondLastLine: false,
        renderLineHighlight: 'line',
        lineNumbers: 'on',
        folding: true,
        wordWrap: 'off',
        padding: { top: 8, bottom: 8 },
        fontFamily: '"JetBrains Mono","SF Mono",ui-monospace,Menlo,Consolas,monospace',
        scrollbar: { verticalScrollbarSize: 8, horizontalScrollbarSize: 8 },
        find: { addExtraSpaceOnTop: false, autoFindInSelection: 'never' }
      });

      monaco.editor.defineTheme('hm-dark', {
        base: 'vs-dark',
        inherit: true,
        rules: [
          { token: 'comment', foreground: '71717a', fontStyle: 'italic' },
          { token: 'keyword', foreground: 'c4b5fd' },
          { token: 'string', foreground: '86efac' },
          { token: 'number', foreground: 'fdba74' },
          { token: 'type', foreground: '67e8f9' },
          { token: 'function', foreground: '93c5fd' },
          { token: 'annotation', foreground: 'f0abfc' },
          { token: 'annotation.arkts', foreground: 'f0abfc' }
        ],
        colors: {
          'editor.background': '#0c0c0e',
          'editor.foreground': '#fafafa',
          'editorLineNumber.foreground': '#52525b',
          'editor.lineHighlightBackground': '#27272a8c',
          'editor.selectionBackground': '#3f3f4680',
          'editorCursor.foreground': '#fafafa',
          'editorWidget.background': '#18181b',
          'editorGutter.background': '#0c0c0e'
        }
      });
      monaco.editor.defineTheme('hm-light', {
        base: 'vs',
        inherit: true,
        rules: [
          { token: 'comment', foreground: 'a1a1aa', fontStyle: 'italic' },
          { token: 'keyword', foreground: '7c3aed' },
          { token: 'string', foreground: '15803d' },
          { token: 'number', foreground: 'c2410c' },
          { token: 'type', foreground: '0891b2' },
          { token: 'function', foreground: '2563eb' },
          { token: 'annotation', foreground: 'a21caf' },
          { token: 'annotation.arkts', foreground: 'a21caf' }
        ],
        colors: {
          'editor.background': '#ffffff',
          'editor.foreground': '#09090b',
          'editorLineNumber.foreground': '#a1a1aa',
          'editor.lineHighlightBackground': '#f4f4f5e6',
          'editorGutter.background': '#ffffff'
        }
      });

      var theme = window.__hmIde.getState().theme;
      monaco.editor.setTheme(theme === 'vs' ? 'hm-light' : 'hm-dark');

      editor.onDidChangeModelContent(function () {
        window.__hmIde._notifyChange(editor.getValue());
      });

      editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, function () {
        window.__hmIde._notifySave();
      });

      window.__hmIdeEditor = {
        setValue: function (v) {
          var pos = editor.getPosition();
          editor.setValue(v == null ? '' : v);
          if (pos) editor.setPosition(pos);
        },
        getValue: function () { return editor.getValue(); },
        setLanguage: function (lang) {
          var model = editor.getModel();
          if (model) monaco.editor.setModelLanguage(model, mapLanguage(lang));
        },
        setTheme: function (t) {
          monaco.editor.setTheme(t === 'vs' ? 'hm-light' : 'hm-dark');
        },
        setFontSize: function (n) { editor.updateOptions({ fontSize: n }); },
        setTabSize: function (n) {
          var model = editor.getModel();
          if (model) model.updateOptions({ tabSize: n });
        },
        focus: function () { editor.focus(); },
        triggerFind: function () {
          editor.focus();
          editor.trigger('hm-ide', 'actions.find', null);
        },
        triggerReplace: function () {
          editor.focus();
          try {
            editor.trigger('hm-ide', 'editor.action.startFindReplaceAction', null);
          } catch (e) {
            editor.trigger('hm-ide', 'actions.find', null);
          }
        },
        revealLine: function (line, column) {
          var ln = Math.max(1, Number(line) || 1);
          var col = Math.max(1, Number(column) || 1);
          editor.revealLineInCenter(ln);
          editor.setPosition({ lineNumber: ln, column: col });
          editor.focus();
        }
      };

      window.__hmIde._setEngine('monaco');
      window.__hmIde._notifyReady();
    }, function (err) {
      clearTimeout(timer);
      bootFallback('monaco-load-error:' + (err && err.message ? err.message : 'unknown'));
    });
  }

  function bootFallback(reason) {
    if (booted && window.__hmIde.getState().engine === 'monaco') return;
    markBooted();
    document.getElementById('root').style.display = 'none';
    var fb = document.getElementById('fallback');
    fb.classList.add('shown');
    var area = document.getElementById('codeArea');
    var gutter = document.getElementById('gutter');

    function refreshGutter() {
      var lines = (area.value || '').split('\n').length;
      var html = '';
      for (var i = 1; i <= Math.max(lines, 1); i++) {
        html += '<div>' + i + '</div>';
      }
      gutter.innerHTML = html;
    }

    area.value = window.__hmIde.getState().value || '';
    area.style.fontSize = (window.__hmIde.getState().fontSize || 13) + 'px';
    area.style.tabSize = String(window.__hmIde.getState().tabSize || 2);
    refreshGutter();

    area.addEventListener('input', function () {
      refreshGutter();
      window.__hmIde._notifyChange(area.value);
    });
    area.addEventListener('scroll', function () {
      gutter.scrollTop = area.scrollTop;
    });
    area.addEventListener('keydown', function (e) {
      if ((e.ctrlKey || e.metaKey) && (e.key === 's' || e.key === 'S')) {
        e.preventDefault();
        window.__hmIde._notifySave();
      }
      if ((e.ctrlKey || e.metaKey) && (e.key === 'f' || e.key === 'F')) {
        e.preventDefault();
        var q = window.prompt('查找', '');
        if (q) {
          var idx = area.value.indexOf(q);
          if (idx >= 0) {
            area.focus();
            area.setSelectionRange(idx, idx + q.length);
          }
        }
      }
      if (e.key === 'Tab') {
        e.preventDefault();
        var start = area.selectionStart;
        var end = area.selectionEnd;
        var tab = new Array((window.__hmIde.getState().tabSize || 2) + 1).join(' ');
        area.value = area.value.substring(0, start) + tab + area.value.substring(end);
        area.selectionStart = area.selectionEnd = start + tab.length;
        window.__hmIde._notifyChange(area.value);
        refreshGutter();
      }
    });

    window.__hmIdeEditor = {
      setValue: function (v) { area.value = v == null ? '' : v; refreshGutter(); },
      getValue: function () { return area.value; },
      setLanguage: function () {},
      setTheme: function (t) {
        document.body.setAttribute('data-theme', t === 'vs' ? 'light' : 'dark');
      },
      setFontSize: function (n) { area.style.fontSize = n + 'px'; },
      setTabSize: function (n) { area.style.tabSize = String(n); },
      focus: function () { area.focus(); },
      triggerFind: function () {
        var q = window.prompt('查找', '');
        if (q) {
          var idx = area.value.indexOf(q);
          if (idx >= 0) {
            area.focus();
            area.setSelectionRange(idx, idx + q.length);
          }
        }
      },
      triggerReplace: function () {
        var q = window.prompt('查找', '');
        if (!q) return;
        var r = window.prompt('替换为', '');
        if (r == null) return;
        area.value = area.value.split(q).join(r);
        window.__hmIde._notifyChange(area.value);
        refreshGutter();
      },
      revealLine: function (line) {
        var lines = area.value.split('\n');
        var ln = Math.max(1, Math.min(Number(line) || 1, lines.length));
        var pos = 0;
        for (var i = 0; i < ln - 1; i++) pos += lines[i].length + 1;
        area.focus();
        area.setSelectionRange(pos, pos);
      }
    };

    window.__hmIde._setEngine('fallback');
    window.__hmIde._notifyReady();
    console.info('[hm-ide] fallback editor:', reason);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bootMonaco);
  } else {
    bootMonaco();
  }
})();
