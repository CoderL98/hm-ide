/**
 * 首页 — 鸿蒙原生应用入口
 */
@Entry
@Component
struct Index {
  @State message: string = 'Hello HarmonyOS';
  @State count: number = 0;

  build() {
    Column() {
      Text(this.message)
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
        .margin({ bottom: 16 })

      Text(`点击次数：${this.count}`)
        .fontSize(16)
        .fontColor('#a1a1aa')
        .margin({ bottom: 24 })

      Button('Increment')
        .onClick(() => {
          this.count += 1;
          this.message = `Hello HarmonyOS × ${this.count}`;
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#09090b')
  }
}
