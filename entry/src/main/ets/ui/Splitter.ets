import { IdeTheme } from '../theme/IdeColors';
import { SettingsStore } from '../services/SettingsStore';

/**
 * 垂直分割条（调整侧栏宽度）— 对齐原型 thin hit area（视觉 1px，命中 ~5vp）
 */
@Component
export struct VSplitter {
  @StorageLink('settingsRev') settingsRev: number = 0;
  @Prop baseWidth: number = 260;
  private dragStartW: number = 260;

  build() {
    Stack() {
      Row()
        .width(1)
        .height('100%')
        .backgroundColor(IdeTheme.palette().border)
      Row()
        .width(5)
        .height('100%')
        .backgroundColor(Color.Transparent)
    }
    .width(5)
    .height('100%')
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 1 })
        .onActionStart(() => {
          this.dragStartW = SettingsStore.getInstance().sidebarWidth || this.baseWidth;
        })
        .onActionUpdate((e: GestureEvent) => {
          SettingsStore.getInstance().setSidebarWidthLive(this.dragStartW + e.offsetX);
        })
        .onActionEnd(() => {
          SettingsStore.getInstance().persistSidebarWidth();
        })
    )
  }
}

/**
 * 水平分割条（调整底栏高度）
 */
@Component
export struct HSplitter {
  @StorageLink('settingsRev') settingsRev: number = 0;
  private dragStartH: number = 180;

  build() {
    Stack() {
      Column()
        .width('100%')
        .height(1)
        .backgroundColor(IdeTheme.palette().border)
      Column()
        .width('100%')
        .height(5)
        .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .height(5)
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Vertical, distance: 1 })
        .onActionStart(() => {
          this.dragStartH = SettingsStore.getInstance().bottomPanelHeight;
        })
        .onActionUpdate((e: GestureEvent) => {
          // 向上拖 → 增高底栏（offsetY 向下为正）
          SettingsStore.getInstance().setBottomPanelHeightLive(this.dragStartH - e.offsetY);
        })
        .onActionEnd(() => {
          SettingsStore.getInstance().persistBottomPanelHeight();
        })
    )
  }
}
