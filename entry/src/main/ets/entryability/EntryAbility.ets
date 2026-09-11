import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { SettingsStore } from '../services/SettingsStore';
import { WorkspaceService } from '../services/WorkspaceService';
import { IdeStore } from '../services/IdeStore';
import { LocalTerminalService } from '../services/LocalTerminalService';
import { HvigorService } from '../services/HvigorService';
import { GitService } from '../services/GitService';
import { ClangService } from '../services/ClangService';

const DOMAIN = 0x1DE0;
const TAG = 'HmIDE';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      AppStorage.setOrCreate('settingsRev', 0);
      AppStorage.setOrCreate('ideRev', 0);
      AppStorage.setOrCreate('workspaceRev', 0);
      AppStorage.setOrCreate('editorReadyRev', 0);
      AppStorage.setOrCreate('editorCmdRev', 0);
      AppStorage.setOrCreate('editorEngine', '');
      AppStorage.setOrCreate('termReadyRev', 0);
      AppStorage.setOrCreate('termDataRev', 0);
      AppStorage.setOrCreate('termCmdRev', 0);
      AppStorage.setOrCreate('termSessionRev', 0);
      AppStorage.setOrCreate('termPendingData', '');
      AppStorage.setOrCreate('termPendingCmd', '');
      AppStorage.setOrCreate('termMode', 'local');
      AppStorage.setOrCreate('scmRev', 0);
      AppStorage.setOrCreate('buildRev', 0);
      AppStorage.setOrCreate('remoteSessionRev', 0);
      AppStorage.setOrCreate('remotePtyRev', 0);
      AppStorage.setOrCreate('remotePtyChunk', '');
    } catch (_e) {
      // ignore
    }
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (_e) {
      // ignore
    }
    hilog.info(DOMAIN, TAG, 'Ability onCreate');
  }

  onDestroy(): void {
    try {
      IdeStore.getInstance().stopWatchers();
      LocalTerminalService.getInstance().stopSession();
    } catch (_e) {
      // ignore
    }
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageCreate');

    Promise.all([
      SettingsStore.getInstance().init(this.context),
      WorkspaceService.getInstance().init(this.context),
      HvigorService.getInstance().init(this.context)
    ]).then(() => {
      IdeStore.getInstance().bootstrap();
      LocalTerminalService.getInstance().startSession();
      try { GitService.getInstance().probe(); } catch (_g) {}
      try { ClangService.getInstance().probe(); } catch (_c) {}
      hilog.info(DOMAIN, TAG, 'stores ready');
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'init failed %{public}s', JSON.stringify(err));
      try {
        IdeStore.getInstance().bootstrap();
        try { LocalTerminalService.getInstance().startSession(); } catch (_t) {}
      } catch (_e) {
        // ignore
      }
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'loadContent success');
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, TAG, 'onConfigurationUpdate');
    SettingsStore.getInstance().onConfigurationChanged();
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
  }
}
