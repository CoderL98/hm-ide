/**
 * 断点与方向 — 对齐 design/prototypes/README.md
 * <600 手机竖屏；横屏侧轨
 * 600–840 大屏手机/折叠折叠态
 * 840–1024 折叠展开/小平板
 * ≥1024 平板/桌面完整壳层
 */
export enum IdeShellMode {
  /** 桌面完整 IDE：活动栏|资源管理器|编辑器|底栏|状态栏 */
  DESKTOP = 'desktop',
  /** 平板横屏：无活动栏，双栏+底栏 */
  TABLET_LANDSCAPE = 'tablet_landscape',
  /** 平板竖屏：窄侧栏 */
  TABLET_PORTRAIT = 'tablet_portrait',
  /** 手机竖屏：底栏导航 */
  PHONE_PORTRAIT = 'phone_portrait',
  /** 手机横屏：侧轨+双栏 */
  PHONE_LANDSCAPE = 'phone_landscape',
  /** 折叠屏横屏：近平板密度 */
  FOLD_LANDSCAPE = 'fold_landscape'
}

export class BreakpointConstants {
  static readonly PHONE_MAX: number = 600;
  static readonly FOLD_MIN: number = 840;
  static readonly DESKTOP_MIN: number = 1024;
  static readonly TABLET_MIN: number = 600;
}

export class WindowSizeState {
  widthVp: number = 360;
  heightVp: number = 780;

  update(widthVp: number, heightVp: number): void {
    this.widthVp = widthVp;
    this.heightVp = heightVp;
  }

  isLandscape(): boolean {
    return this.widthVp > this.heightVp;
  }

  shellMode(): IdeShellMode {
    const w = this.widthVp;
    const land = this.isLandscape();

    if (w >= BreakpointConstants.DESKTOP_MIN) {
      return IdeShellMode.DESKTOP;
    }
    // 折叠展开横屏 ~840–1100
    if (land && w >= BreakpointConstants.FOLD_MIN && w < BreakpointConstants.DESKTOP_MIN) {
      return IdeShellMode.FOLD_LANDSCAPE;
    }
    // 平板
    if (w >= BreakpointConstants.TABLET_MIN) {
      return land ? IdeShellMode.TABLET_LANDSCAPE : IdeShellMode.TABLET_PORTRAIT;
    }
    // 手机
    return land ? IdeShellMode.PHONE_LANDSCAPE : IdeShellMode.PHONE_PORTRAIT;
  }

  showActivityBar(): boolean {
    const m = this.shellMode();
    return m === IdeShellMode.DESKTOP || m === IdeShellMode.FOLD_LANDSCAPE;
  }

  showSideRail(): boolean {
    return this.shellMode() === IdeShellMode.PHONE_LANDSCAPE;
  }

  showBottomNav(): boolean {
    return this.shellMode() === IdeShellMode.PHONE_PORTRAIT;
  }

  showSidebar(): boolean {
    const m = this.shellMode();
    return m !== IdeShellMode.PHONE_PORTRAIT;
  }

  sidebarWidth(): number {
    const m = this.shellMode();
    if (m === IdeShellMode.TABLET_PORTRAIT) {
      return 200;
    }
    if (m === IdeShellMode.TABLET_LANDSCAPE || m === IdeShellMode.FOLD_LANDSCAPE) {
      return 220;
    }
    if (m === IdeShellMode.PHONE_LANDSCAPE) {
      return 180;
    }
    return 260;
  }

  showBottomPanel(): boolean {
    const m = this.shellMode();
    return m === IdeShellMode.DESKTOP ||
      m === IdeShellMode.TABLET_LANDSCAPE ||
      m === IdeShellMode.TABLET_PORTRAIT ||
      m === IdeShellMode.FOLD_LANDSCAPE;
  }

  showStatusBar(): boolean {
    return this.shellMode() !== IdeShellMode.PHONE_PORTRAIT;
  }

  modeLabel(): string {
    switch (this.shellMode()) {
      case IdeShellMode.DESKTOP:
        return '桌面';
      case IdeShellMode.TABLET_LANDSCAPE:
        return '平板横屏';
      case IdeShellMode.TABLET_PORTRAIT:
        return '平板竖屏';
      case IdeShellMode.PHONE_PORTRAIT:
        return '手机竖屏';
      case IdeShellMode.PHONE_LANDSCAPE:
        return '手机横屏';
      case IdeShellMode.FOLD_LANDSCAPE:
        return '折叠屏横屏';
      default:
        return '';
    }
  }
}
