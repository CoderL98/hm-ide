/**
 * 设计令牌 — 与 design/prototypes/styles.css 一一对应（shadcn zinc）
 */
export type IdeThemeMode = 'system' | 'light' | 'dark';

export class IdePalette {
  background: string = '#09090b';
  foreground: string = '#fafafa';
  card: string = '#18181b';
  cardHover: string = '#1f1f23';
  muted: string = '#27272a';
  mutedForeground: string = '#a1a1aa';
  border: string = '#27272a';
  borderSubtle: string = '#3f3f46';
  accent: string = '#27272a';
  accentForeground: string = '#fafafa';
  primary: string = '#e4e4e7';
  primaryForeground: string = '#18181b';
  sidebar: string = '#09090b';
  sidebarActive: string = '#18181b';
  activity: string = '#09090b';
  editor: string = '#0c0c0e';
  status: string = '#18181b';
  tabActive: string = '#0c0c0e';
  tabInactive: string = '#141416';
  dirty: string = '#a1a1aa';
  gutter: string = '#52525b';
  statusOk: string = '#4ade80';
  syntaxKeyword: string = '#c4b5fd';
  syntaxString: string = '#86efac';
  syntaxComment: string = '#71717a';
  syntaxFn: string = '#93c5fd';
  syntaxType: string = '#67e8f9';
  syntaxNumber: string = '#fdba74';
  syntaxDecorator: string = '#f0abfc';
  radius: number = 6;

  static dark(): IdePalette {
    return new IdePalette();
  }

  static light(): IdePalette {
    const p = new IdePalette();
    p.background = '#fafafa';
    p.foreground = '#09090b';
    p.card = '#ffffff';
    p.cardHover = '#f4f4f5';
    p.muted = '#f4f4f5';
    p.mutedForeground = '#71717a';
    p.border = '#e4e4e7';
    p.borderSubtle = '#d4d4d8';
    p.accent = '#f4f4f5';
    p.accentForeground = '#09090b';
    p.primary = '#18181b';
    p.primaryForeground = '#fafafa';
    p.sidebar = '#f4f4f5';
    p.sidebarActive = '#ffffff';
    p.activity = '#f4f4f5';
    p.editor = '#ffffff';
    p.status = '#f4f4f5';
    p.tabActive = '#ffffff';
    p.tabInactive = '#f4f4f5';
    p.dirty = '#71717a';
    p.gutter = '#a1a1aa';
    p.statusOk = '#16a34a';
    p.syntaxKeyword = '#7c3aed';
    p.syntaxString = '#15803d';
    p.syntaxComment = '#a1a1aa';
    p.syntaxFn = '#2563eb';
    p.syntaxType = '#0891b2';
    p.syntaxNumber = '#c2410c';
    p.syntaxDecorator = '#a21caf';
    return p;
  }
}

export class IdeTheme {
  private static darkOverride: boolean = true;

  static setEffectiveDark(isDark: boolean): void {
    IdeTheme.darkOverride = isDark;
  }

  static isDark(): boolean {
    return IdeTheme.darkOverride;
  }

  static palette(): IdePalette {
    return IdeTheme.isDark() ? IdePalette.dark() : IdePalette.light();
  }

  static monacoThemeName(): string {
    return IdeTheme.isDark() ? 'dark' : 'light';
  }

  static modeLabel(mode: IdeThemeMode): string {
    if (mode === 'light') {
      return '浅色';
    }
    if (mode === 'dark') {
      return '深色';
    }
    return '跟随系统';
  }
}
