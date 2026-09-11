import { IdeTheme } from '../theme/IdeColors';

@CustomDialog
export struct NameInputDialog {
  controller: CustomDialogController;
  title: string = '输入名称';
  placeholder: string = '';
  initial: string = '';
  onConfirm: (name: string) => void = (_n: string) => {};
  @State value: string = '';

  aboutToAppear(): void {
    this.value = this.initial;
  }

  build() {
    Column({ space: 12 }) {
      Text(this.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(IdeTheme.palette().foreground)
        .width('100%')

      TextInput({ text: this.value, placeholder: this.placeholder })
        .onChange((v: string) => {
          this.value = v;
        })
        .height(40)
        .backgroundColor(IdeTheme.palette().muted)
        .fontColor(IdeTheme.palette().foreground)
        .placeholderColor(IdeTheme.palette().mutedForeground)

      Row({ space: 8 }) {
        Blank()
        Text('取消')
          .fontSize(13)
          .fontColor(IdeTheme.palette().mutedForeground)
          .padding(8)
          .onClick(() => this.controller.close())
        Text('确定')
          .fontSize(13)
          .fontColor(IdeTheme.palette().primaryForeground)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(6)
          .backgroundColor(IdeTheme.palette().primary)
          .onClick(() => {
            const v = this.value.trim();
            if (v) {
              this.onConfirm(v);
            }
            this.controller.close();
          })
      }
      .width('100%')
    }
    .padding(16)
    .backgroundColor(IdeTheme.palette().card)
  }
}
