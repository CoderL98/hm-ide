import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { IdeTheme, IdeThemeMode } from '../theme/IdeColors';

const PREF_NAME = 'hm_ide_settings';
const SIDEBAR_MIN = 160;
const SIDEBAR_MAX = 480;
const BOTTOM_MIN = 100;
const BOTTOM_MAX = 420;

export class SettingsStore {
  private static instance: SettingsStore = new SettingsStore();
  private prefs: preferences.Preferences | null = null;
  private context: common.UIAbilityContext | null = null;

  themeMode: IdeThemeMode = 'dark';
  fontSize: number = 13;
  tabSize: number = 2;
  bottomPanelCollapsed: boolean = false;
  sidebarVisible: boolean = true;
  sidebarWidth: number = 260;
  bottomPanelHeight: number = 180;
  recentRoots: string[] = [];

  static getInstance(): SettingsStore {
    return SettingsStore.instance;
  }

  static clampSidebar(w: number): number {
    return Math.max(SIDEBAR_MIN, Math.min(SIDEBAR_MAX, Math.round(w)));
  }

  static clampBottom(h: number): number {
    return Math.max(BOTTOM_MIN, Math.min(BOTTOM_MAX, Math.round(h)));
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    this.prefs = await preferences.getPreferences(context, PREF_NAME);
    this.themeMode = (await this.prefs.get('themeMode', 'dark')) as IdeThemeMode;
    this.fontSize = Number(await this.prefs.get('fontSize', 13));
    this.tabSize = Number(await this.prefs.get('tabSize', 2));
    this.bottomPanelCollapsed = Boolean(await this.prefs.get('bottomPanelCollapsed', false));
    this.sidebarVisible = Boolean(await this.prefs.get('sidebarVisible', true));
    this.sidebarWidth = SettingsStore.clampSidebar(Number(await this.prefs.get('sidebarWidth', 260)));
    this.bottomPanelHeight = SettingsStore.clampBottom(Number(await this.prefs.get('bottomPanelHeight', 180)));
    const recentRaw = String(await this.prefs.get('recentRoots', '[]'));
    try {
      const parsed: string[] = JSON.parse(recentRaw) as string[];
      this.recentRoots = Array.isArray(parsed) ? parsed.slice(0, 8) : [];
    } catch (_e) {
      this.recentRoots = [];
    }
    this.applyTheme();
    this.bump();
  }

  private bump(): void {
    try {
      const cur = AppStorage.get<number>('settingsRev') ?? 0;
      AppStorage.setOrCreate('settingsRev', cur + 1);
    } catch (_e) {
      // ignore
    }
  }

  private async save(key: string, value: preferences.ValueType): Promise<void> {
    if (!this.prefs) {
      return;
    }
    await this.prefs.put(key, value);
    await this.prefs.flush();
  }

  applyTheme(): void {
    let isDark = true;
    if (this.themeMode === 'light') {
      isDark = false;
    } else if (this.themeMode === 'dark') {
      isDark = true;
    } else if (this.context) {
      try {
        const cfg = this.context.config;
        isDark = cfg.colorMode !== ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      } catch (_e) {
        isDark = true;
      }
    }
    IdeTheme.setEffectiveDark(isDark);
    try {
      if (this.context) {
        const mode = this.themeMode === 'light'
          ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
          : this.themeMode === 'dark'
            ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
            : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
        this.context.getApplicationContext().setColorMode(mode);
      }
    } catch (_e) {
      // ignore
    }
  }

  async setThemeMode(mode: IdeThemeMode): Promise<void> {
    this.themeMode = mode;
    this.applyTheme();
    await this.save('themeMode', mode);
    this.bump();
  }

  async setFontSize(size: number): Promise<void> {
    this.fontSize = Math.max(10, Math.min(24, size));
    await this.save('fontSize', this.fontSize);
    this.bump();
  }

  async setTabSize(size: number): Promise<void> {
    this.tabSize = size === 4 ? 4 : 2;
    await this.save('tabSize', this.tabSize);
    this.bump();
  }

  async setBottomPanelCollapsed(v: boolean): Promise<void> {
    this.bottomPanelCollapsed = v;
    await this.save('bottomPanelCollapsed', v);
    this.bump();
  }

  async setSidebarVisible(v: boolean): Promise<void> {
    this.sidebarVisible = v;
    await this.save('sidebarVisible', v);
    this.bump();
  }

  async setSidebarWidth(w: number): Promise<void> {
    this.sidebarWidth = SettingsStore.clampSidebar(w);
    await this.save('sidebarWidth', this.sidebarWidth);
    this.bump();
  }

  /** 拖拽中仅更新内存，松手再 flush */
  setSidebarWidthLive(w: number): void {
    this.sidebarWidth = SettingsStore.clampSidebar(w);
    this.bump();
  }

  async persistSidebarWidth(): Promise<void> {
    await this.save('sidebarWidth', this.sidebarWidth);
  }

  async setBottomPanelHeight(h: number): Promise<void> {
    this.bottomPanelHeight = SettingsStore.clampBottom(h);
    await this.save('bottomPanelHeight', this.bottomPanelHeight);
    this.bump();
  }

  setBottomPanelHeightLive(h: number): void {
    this.bottomPanelHeight = SettingsStore.clampBottom(h);
    this.bump();
  }

  async persistBottomPanelHeight(): Promise<void> {
    await this.save('bottomPanelHeight', this.bottomPanelHeight);
  }

  async pushRecentRoot(root: string): Promise<void> {
    if (!root) {
      return;
    }
    const next: string[] = [root];
    for (let i = 0; i < this.recentRoots.length; i++) {
      if (this.recentRoots[i] !== root) {
        next.push(this.recentRoots[i]);
      }
    }
    this.recentRoots = next.slice(0, 8);
    await this.save('recentRoots', JSON.stringify(this.recentRoots));
    this.bump();
  }

  onConfigurationChanged(): void {
    if (this.themeMode === 'system') {
      this.applyTheme();
      this.bump();
    }
  }
}
