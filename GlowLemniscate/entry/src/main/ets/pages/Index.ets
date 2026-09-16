/*
 * Index.ets — the demo page.
 *
 *   Canvas(DrawingRenderingContext)        the on-screen Skia surface (API 12+)
 *   GlowRenderer                           draws the two trails into it
 *   displaySync                            vsync-aligned frame loop (API 11+)
 *   DrawingRenderingContext.invalidate()   schedules a repaint of the component
 *
 * Orientation is declared in module.json5 (`"orientation": "auto_rotation"`), so
 * rotating the device rebuilds the window and the canvas is re-measured here.
 * Note there is no `requestAnimationFrame` in ArkTS — `displaySync` is the
 * supported per-frame clock on the UI thread.
 */

import { displaySync, drawing } from '@kit.ArkGraphics2D';
import { LengthMetricsUnit } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SizeMode, TIME_STEP, Viewport } from '../glow/GlowCurve';
import { GlowRenderer } from '../glow/GlowRenderer';

const DOMAIN: number = 0x0000;
const TAG: string = 'GlowLemniscate';

@Entry
@ComponentV2
struct Index {
  /**
   * Unlike `CanvasRenderingContext2D`, this hands out a real `drawing.Canvas`
   * that paints into the component's own surface — no offscreen PixelMap and no
   * `drawImage` round-trip.
   *
   * `LengthMetricsUnit.PX` matters: the `drawing` module always works in
   * physical pixels, while a default `DrawingRenderingContext()` reports sizes
   * in vp. Pinning the unit means `ctx.size` is directly usable as drawing
   * coordinates, in either orientation.
   */
  private ctx: DrawingRenderingContext = new DrawingRenderingContext(LengthMetricsUnit.PX);
  private renderer: GlowRenderer = new GlowRenderer();

  /** `displaySync` ticks with the display pipeline rather than a free-running timer. */
  private sync: displaySync.DisplaySync = displaySync.create();

  /** Cached handle to `ctx.canvas`; the getter is not meant to be called per frame. */
  private surface: drawing.Canvas | undefined = undefined;

  /** Last measured canvas size in physical pixels; 0 until the first measure. */
  private pxWidth: number = 0;
  private pxHeight: number = 0;

  /** Shader `time` uniform, advanced by TIME_STEP (0.015) per frame — as in the original. */
  private time: number = 0;

  private running: boolean = false;

  aboutToAppear(): void {
    // Ask for 60 fps; the system may clamp this to the display's refresh rate.
    this.sync.setExpectedFrameRateRange({ expected: 60, min: 30, max: 120 });
    this.sync.on('frame', () => {
      this.onFrame();
    });
    // SizeMode.FIT keeps the whole figure on screen in any aspect ratio;
    // SizeMode.SHADER restores the original WebGL framing (overflows portrait).
    this.renderer.setSizeMode(SizeMode.FIT);
  }

  aboutToDisappear(): void {
    // Required: an un-stopped DisplaySync keeps the component alive.
    this.running = false;
    this.sync.stop();
    this.sync.off('frame');
  }

  /**
   * Re-measures the surface and re-projects if the size changed.
   *
   * Called from `onReady`, from `onAreaChange`, and once per frame. The
   * per-frame check is what makes orientation changes robust: rotation rebuilds
   * the window, and the canvas size can settle a frame or two after
   * `onAreaChange` fires. The cost is two number reads.
   */
  private refreshSize(): void {
    const width: number = this.ctx.size.width;
    const height: number = this.ctx.size.height;
    if (width <= 0 || height <= 0) {
      return;
    }
    if (width === this.pxWidth && height === this.pxHeight) {
      return;
    }
    this.pxWidth = width;
    this.pxHeight = height;
    this.renderer.resize(width, height);

    const vp: Viewport = this.renderer.viewport;
    hilog.info(DOMAIN, TAG, 'surface %{public}dx%{public}d px, %{public}s, scale %{public}s',
      width, height,
      width >= height ? 'landscape' : 'portrait',
      vp.scale.toFixed(5));
    hilog.info(DOMAIN, TAG, 'figure %{public}dx%{public}d px in a %{public}dx%{public}d px viewport',
      Math.round(vp.shapeHalfWidthPx() * 2), Math.round(vp.shapeHalfHeightPx() * 2), width, height);

    if (!this.running && this.surface !== undefined) {
      this.running = true;
      this.sync.start();
    }
  }

  private onFrame(): void {
    const surface: drawing.Canvas | undefined = this.surface;
    if (!this.running || surface === undefined) {
      return;
    }
    this.refreshSize();          // picks up rotation
    this.time += TIME_STEP;
    this.renderer.render(surface, this.time);
    // Ask ArkUI to repaint the Canvas component with what we just drew.
    this.ctx.invalidate();
  }

  build() {
    Stack() {
      Canvas(this.ctx)
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)
        .onReady(() => {
          this.surface = this.ctx.canvas;
          this.refreshSize();
        })

      // Entry point for the second route (pages/ListPage, registered in
      // resources/base/profile/main_pages.json).
      //
      // `TouchType`-transparent wrapper rather than `.align()`: `align` sets how
      // a component's own content sits inside its box, it does not position a
      // Stack child, so the button ended up centred on device.
      Column() {
        Button('列表 Demo')
          .fontSize(13)
          .height(32)
          .backgroundColor('#1E1E2A')
          .fontColor('#B8B8CC')
          .onClick(() => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/ListPage' });
          })
      }
      .width('100%')
      .height('100%')
      .padding({ top: 48, right: 16 })
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.End)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .onAreaChange((_oldValue: Area, _newValue: Area) => {
      this.refreshSize();
    })
  }
}
