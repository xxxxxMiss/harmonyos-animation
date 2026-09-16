import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x0000;
const TAG = 'GlowLemniscate';

/**
 * Layout policy. The visual gains real estate from both:
 *   - `setWindowLayoutFullScreen(true)` lets the black canvas extend under the
 *     status bar and the navigation indicator, instead of being letterboxed
 *     between them;
 *   - the navigation indicator is hidden, since this page has no interactive
 *     content and the system swipe-up gesture still works.
 * Set `IMMERSIVE = false` to get the plain system-bar layout back.
 */
const IMMERSIVE: boolean = true;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');

    if (IMMERSIVE) {
      // Ordered deliberately: the page reads `topSafeInsetPx` from AppStorage in
      // its field initialisers (`@StorageProp` is a V1 decorator and the pages
      // are V2), so the value has to be published before loadContent runs.
      this.applyImmersiveLayout(windowStage).then(() => {
        this.loadIndex(windowStage);
      });
    } else {
      this.loadIndex(windowStage);
    }
  }

  private loadIndex(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
    });
  }

  /**
   * Best-effort: every call is allowed to fail on its own (some device types
   * reject individual system-bar settings) without taking the ability down.
   */
  private applyImmersiveLayout(windowStage: window.WindowStage): Promise<void> {
    try {
      const win: window.Window = windowStage.getMainWindowSync();
      // Publish synchronously: the avoid area is already known, and the page
      // needs it before it is constructed.
      this.publishSafeInsets(win);
      win.setWindowLayoutFullScreen(true)
        .then(() => {
          hilog.info(DOMAIN, TAG, 'full-screen layout enabled');
        })
        .catch((err: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'setWindowLayoutFullScreen failed: %{public}s', JSON.stringify(err));
        });
      // Keep 'status' visible; hide only the navigation indicator.
      win.setWindowSystemBarEnable(['status'])
        .then(() => {
          hilog.info(DOMAIN, TAG, 'system bars: status only');
        })
        .catch((err: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'setWindowSystemBarEnable failed: %{public}s', JSON.stringify(err));
        });
      return win.setWindowLayoutFullScreen(true).then(() => {
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'immersive layout unavailable: %{public}s', JSON.stringify(err));
      return Promise.resolve();
    }
  }

  /**
   * Full-screen layout means page content starts underneath the status bar, so
   * every page that is not deliberately full-bleed needs the inset. Publishing
   * it here keeps the pages from each having to query the window
   * asynchronously — and this is the one place that already holds a synchronous
   * `Window` handle.
   */
  private publishSafeInsets(win: window.Window): void {
    try {
      const avoid: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const topPx: number = avoid.visible ? avoid.topRect.height : 0;
      AppStorage.setOrCreate<number>('topSafeInsetPx', topPx);
      hilog.info(DOMAIN, TAG, 'top safe inset = %{public}d px', topPx);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'getWindowAvoidArea failed: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }
}