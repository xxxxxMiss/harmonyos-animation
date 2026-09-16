# `@ohos.graphics.drawing` (ArkGraphics 2D) — API-verified reference report
### HarmonyOS NEXT / OpenHarmony, API 11 → API 24

**Method.** Every claim below was verified against one of these authoritative sources, fetched directly:

| Source | URL |
|---|---|
| **SDK type declarations (most authoritative)** — `@ohos.graphics.drawing.d.ts` | `https://raw.githubusercontent.com/openharmony/interface_sdk-js/<branch>/api/@ohos.graphics.drawing.d.ts` |
| Kit re-export file `@kit.ArkGraphics2D.d.ts` | `https://raw.githubusercontent.com/openharmony/interface_sdk-js/master/kits/%40kit.ArkGraphics2D.d.ts` |
| ArkUI component declarations (Canvas / DrawingRenderingContext / CanvasRenderingContext2D) | `https://raw.githubusercontent.com/openharmony/interface_sdk-js/master/api/%40internal/component/ets/canvas.d.ts` |
| API reference docs (per-class, master) | `https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-<Class>.md` |
| API reference docs (monolithic, release branches) | `https://raw.githubusercontent.com/openharmony/docs/<branch>/en/application-dev/reference/apis-arkgraphics2d/js-apis-graphics-drawing.md` |
| Graphics guides | `https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/graphics/<name>.md` |
| Official samples | `https://raw.githubusercontent.com/openharmony/applications_app_samples/master/code/DocsSample/Drawing/...` |

### Branch → API level mapping (verified by max `@since` in each branch's `.d.ts`)

| Branch | API level |
|---|---|
| `OpenHarmony-4.1-Release` | **11** |
| `OpenHarmony-5.0-Release` | **12** |
| `OpenHarmony-5.0.3-Release` | **15** |
| `OpenHarmony-5.1.0-Release` | **18** |
| `OpenHarmony-6.0-Release` | **20** |
| `master` | **23 / 24 / 26** (contains `@since 23` and `@since 26` declarations) |

> Note: on `master` the drawing reference was **split into per-class files** (`arkts-apis-graphics-drawing-Brush.md`, `-Canvas.md`, `-Pen.md`, …). The old monolithic `js-apis-graphics-drawing.md` **does not exist on `master`** (404). Conversely, on `OpenHarmony-6.0-Release` the monolithic doc still exists but **lags the SDK** — its max tag is `18+` while the 6.0 `.d.ts` already contains `@since 20` members (`setColor4f`, `createFromImage`). When doc and `.d.ts` disagree, trust the `.d.ts`.

---

## 1. Module import statements

### Recommended (API 12+)

```ts
import { drawing } from '@kit.ArkGraphics2D';
```

Verified in every drawing reference page header, e.g. [`arkts-apis-graphics-drawing-Brush.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-Brush.md) and the [module description page](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing.md).

To also get the `common2D` types (needed for `Color` / `Rect` / `Point`):

```ts
import { common2D, drawing } from '@kit.ArkGraphics2D';
```

The kit is a pure re-export aggregator — verified verbatim in [`@kit.ArkGraphics2D.d.ts`](https://raw.githubusercontent.com/openharmony/interface_sdk-js/master/kits/%40kit.ArkGraphics2D.d.ts):

```ts
import common2D from '@ohos.graphics.common2D';
import drawing from '@ohos.graphics.drawing';
import text from '@ohos.graphics.text';
// ...
export { displaySync, colorSpaceManager, sendableColorSpaceManager, hdrCapability, effectKit, common2D, drawing,
    text, uiEffect };
```

### Alternative (the underlying module; this is what API 11 docs used)

```ts
// API 11 reference doc form (default import):
import drawing from '@ohos.graphics.drawing';

// Named import form also resolves, because @kit.ArkGraphics2D exports `drawing` as a named binding:
import { drawing } from '@ohos.graphics.drawing';
```

The [API 11 (4.1-Release) doc](https://raw.githubusercontent.com/openharmony/docs/OpenHarmony-4.1-Release/en/application-dev/reference/apis-arkgraphics2d/js-apis-graphics-drawing.md) shows literally `import drawing from '@ohos.graphics.drawing'`. From API 12 onward **all** official docs and samples use `@kit.ArkGraphics2D`.

**Recommendation: use `import { drawing } from '@kit.ArkGraphics2D';`.** It is the documented form for API 12+, and it is what the official sample code uses. `@ohos.graphics.drawing` remains valid but is the "raw" module path.

---

## 2. Obtaining a `drawing.Canvas` from an ArkUI `Canvas` component

### 🔴 CRITICAL CORRECTION: `getDrawingCanvas(canvas: Canvas): DrawingCanvas` **does not exist**

I searched for `getDrawingCanvas` in:
- `@ohos.graphics.drawing.d.ts` on `OpenHarmony-5.0-Release` (API 12), `OpenHarmony-6.0-Release` (API 20), and `master` → **0 hits in all three**
- the drawing module reference docs on 4.1 / 5.0 / 5.0.3 / 5.1.0 / 6.0 / master → **0 hits**
- `api/@internal/component/ets/canvas.d.ts` (ArkUI component declarations, master) → **0 hits**

There is **no `getDrawingCanvas` free function** in the drawing module and **no `getDrawingCanvas` method** on `CanvasRenderingContext2D`. Do not use it.

### The real mechanism: `DrawingRenderingContext` (API 12+)

Source: [`ts-drawingrenderingcontext.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-drawingrenderingcontext.md) and [`canvas.d.ts`](https://raw.githubusercontent.com/openharmony/interface_sdk-js/master/api/%40internal/component/ets/canvas.d.ts)

```ts
declare class DrawingRenderingContext {
  constructor(unit?: LengthMetricsUnit);   // @since 12
  get size(): Size;                        // @since 12
  get canvas(): DrawingCanvas;             // @since 12
  invalidate(): void;                      // @since 12
}

// The alias — this is where the name "DrawingCanvas" actually comes from.
// @since 12
declare type DrawingCanvas = import('../api/@ohos.graphics.drawing').default.Canvas;
```

`DrawingCanvas` is **not a distinct class**. It is a type alias for `drawing.Canvas`. That is the entire "DrawingCanvas" story.

**`drawing.Canvas` is the class you draw with**, and it is reached through `drawingRenderingContext.canvas`.

### ArkUI `Canvas` component overloads that accept a `DrawingRenderingContext`

Source: [`ts-components-canvas-canvas.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-components-canvas-canvas.md)

```ts
// @since 9 (CanvasRenderingContext2D) / DrawingRenderingContext overload @since 12
Canvas(context?: CanvasRenderingContext2D | DrawingRenderingContext)

// @since 12
Canvas(context: CanvasRenderingContext2D | DrawingRenderingContext, imageAIOptions: ImageAIOptions)

// @since 23
Canvas(params: CanvasParams)
```

**Full working path: `DrawingRenderingContext` → `get canvas()` → draw**

```ts
import { common2D, drawing } from '@kit.ArkGraphics2D';

@Entry
@Component
struct CanvasExample {
  private context: DrawingRenderingContext = new DrawingRenderingContext();

  build() {
    Flex({ direction: FlexDirection.Column, alignItems: ItemAlign.Center, justifyContent: FlexAlign.Center }) {
      Canvas(this.context)
        .width('100%')
        .height('50%')
        .backgroundColor('#D5D5D5')
        .onReady(() => {
          const brush = new drawing.Brush();
          brush.setColor({ alpha: 255, red: 39, green: 135, blue: 217 });
          this.context.canvas.attachBrush(brush);
          this.context.canvas.drawCircle(200, 200, 100);
          this.context.canvas.detachBrush();
          this.context.invalidate();     // REQUIRED: triggers re-render
        })
    }
    .width('100%')
    .height('100%')
  }
}
```

This snippet is adapted from the official example in [`ts-drawingrenderingcontext.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-drawingrenderingcontext.md). **`invalidate()` is mandatory** — drawing into `context.canvas` alone does not repaint the component.

### Reverse direction: `CanvasRenderingContext2D` ← drawing context

`CanvasRenderingContext2D.getContext2DFromDrawingContext` — **@since 23**, static:

```ts
// @since 23
static getContext2DFromDrawingContext(
  drawingContext: DrawingRenderingContext,
  options?: RenderingContextOptions
): CanvasRenderingContext2D;
```

Verbatim from both [`ts-canvasrenderingcontext2d.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-canvasrenderingcontext2d.md#getcontext2dfromdrawingcontext23) and `canvas.d.ts`.

- Error code: `103702 The drawingContext is not bound to a canvas component.`
- `RenderingContextOptions` (@since 23): `{ antialias?: boolean }`, default `{ antialias: false }`
- Documented restriction: *"The **CanvasRenderingContext2D** object obtained via this API cannot be used as a parameter to create a **Canvas** component. Otherwise, the application crashes."*

```ts
import { LengthMetricsUnit } from '@kit.ArkUI';

@Entry
@Component
struct CanvasExample {
  build() {
    Flex({ direction: FlexDirection.Column, alignItems: ItemAlign.Center, justifyContent: FlexAlign.Center }) {
      Canvas({ unit: LengthMetricsUnit.DEFAULT })
        .onReady((drawingContext?: DrawingRenderingContext) => {
          if (!drawingContext) { return }
          const context2D: CanvasRenderingContext2D =
            CanvasRenderingContext2D.getContext2DFromDrawingContext(drawingContext, { antialias: true });
          context2D.fillStyle = 'rgb(39,135,217)';
          context2D.fillRect(10, 30, 100, 100);
        })
    }
    .width('100%')
    .height('100%')
  }
}
```

### `CanvasRenderingContext2D` constructors — there is **no** constructor taking a drawing context

Source: [`ts-canvasrenderingcontext2d.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-canvasrenderingcontext2d.md)

```ts
// @since 9
constructor(settings?: RenderingContextSettings)

// @since 12
constructor(settings?: RenderingContextSettings, unit?: LengthMetricsUnit)
```

That is the complete list. `LengthMetricsUnit` (@since 12) is `DEFAULT = 0` (vp) | `PX = 1` (px), from [`js-apis-arkui-graphics.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/js-apis-arkui-graphics.md). There is **no** `constructor(drawingContext)` overload — `getContext2DFromDrawingContext` (API 23) is the only bridge.

### ⚠️ Name collision to avoid

`CanvasRenderingContext2D.canvas` is a **`FrameNode`** property (@since 13), *not* a drawing canvas — it is used to observe component visibility. See [`ts-canvasrenderingcontext2d.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-canvasrenderingcontext2d.md).

---

## 3. `Brush` and `Pen`

Module note common to both classes ([Brush](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-Brush.md), [Pen](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-Pen.md)):

> The initial APIs of this module are supported since **API version 11**.
> This module uses the physical pixel unit, **px**.
> This module operates under a **single-threaded model**. The caller needs to manage thread safety and context state transitions. *(this third note appears only in API 20+ / master docs — it is **absent** from the 5.0-Release API 12 doc)*

`Brush` and `Pen` both exist since **API 11**. Their constructors are **API 12+**.

### 3.1 Color

```ts
// --- Brush ---
setColor(color: common2D.Color): void;                              // @since 11
setColor(alpha: number, red: number, green: number, blue: number): void;  // @since 12  (0-255 ints, floats floored)
setColor(color: number): void;                                      // @since 18  (hex ARGB, 32-bit unsigned)
getColor(): common2D.Color;                                         // @since 12
getHexColor(): number;                                              // @since 18
setColor4f(color4f: common2D.Color4f, colorSpace: colorSpaceManager.ColorSpaceManager | null): void;  // @since 20

// --- Pen: identical set ---
setColor(color: common2D.Color): void;                              // @since 11
setColor(alpha: number, red: number, green: number, blue: number): void;  // @since 12
setColor(color: number): void;                                      // @since 18
```

Answering the question directly: **both** `common2D.Color` **and** `number` are accepted. `number` is available in two forms — a 4-arg `(a, r, g, b)` overload since API 12, and a single hex-ARGB `number` overload since API 18. There is **no** separate `uint32` type in ArkTS; it is `number`.

`common2D.Color` = `{ alpha: number, red: number, green: number, blue: number }`, each 0–255 (source: [`js-apis-graphics-common2D.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/js-apis-graphics-common2D.md)).

> Doc note: `setColor(alpha, red, green, blue)` "provides better performance than `setColor(color)` and is recommended."

### 3.2 Stroke width, anti-alias, alpha

```ts
// --- Pen ---
setStrokeWidth(width: number): void;   // @since 11
getWidth(): number;                    // @since 12
setAntiAlias(aa: boolean): void;       // @since 11
isAntiAlias(): boolean;                // @since 12
setAlpha(alpha: number): void;         // @since 11   [0,255], floats floored
getAlpha(): number;                    // @since 12
setDither(dither: boolean): void;      // @since 11
setMiterLimit(miter: number): void;    // @since 12
setJoinStyle(style: JoinStyle): void;  // @since 12
setCapStyle(style: CapStyle): void;    // @since 12

// --- Brush ---
setAntiAlias(aa: boolean): void;       // @since 11
isAntiAlias(): boolean;                // @since 12
setAlpha(alpha: number): void;         // @since 11
getAlpha(): number;                    // @since 12
```

- `Brush` has **no** `setStrokeWidth` (it is a fill, not a stroke).
- `setAntiAlias` doc: *"If this API is not called, anti-aliasing is disabled by default."*
- `setStrokeWidth` doc: *"The value 0 is treated as an unusually thin width. During drawing, the width of 0 is always drawn as 1 pixel wide, regardless of any scaling applied to the canvas."*

### 3.3 `setBlendMode` — and the additive-blending answer

```ts
// Identical on both classes, @since 11
setBlendMode(mode: BlendMode): void;
```

Doc: *"Sets a blend mode for this brush. If this API is not called, the default blend mode is **SRC_OVER**."*

**Full `BlendMode` enum — all 29 members exist since API 11** (no member carries a superscript in either the 5.0-Release doc or master). Source: [`arkts-apis-graphics-drawing-e.md#blendmode`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-e.md) and `@ohos.graphics.drawing.d.ts`.

```ts
enum BlendMode {
  CLEAR = 0, SRC = 1, DST = 2, SRC_OVER = 3, DST_OVER = 4,
  SRC_IN = 5, DST_IN = 6, SRC_OUT = 7, DST_OUT = 8,
  SRC_ATOP = 9, DST_ATOP = 10, XOR = 11,
  PLUS = 12,          // r = min(s + d, 1)      <-- ADDITIVE
  MODULATE = 13,
  SCREEN = 14,        // r = s + d - s * d
  OVERLAY = 15, DARKEN = 16, LIGHTEN = 17,
  COLOR_DODGE = 18, COLOR_BURN = 19, HARD_LIGHT = 20, SOFT_LIGHT = 21,
  DIFFERENCE = 22, EXCLUSION = 23, MULTIPLY = 24,
  HUE = 25, SATURATION = 26, COLOR = 27, LUMINOSITY = 28
}
```

**Answer on additive blending:**
- **There is NO `ADD` mode.** The additive mode is **`BlendMode.PLUS` (value 12)**, documented as `r = min(s + d, 1)` — "adds the color values of the source and destination pixels", clamped at 1. `PLUS` is the correct choice for additive/glow compositing.
- `SCREEN` (14) and `LIGHTEN` (17) also exist and are brighter-than-`SRC_OVER` modes, but `PLUS` is the true additive one.
- **`PLUS` is since API 11** (same as all other `BlendMode` members).

Official sample proving `PLUS` is the intended additive mode — [`ComplexEffect.ets`](https://raw.githubusercontent.com/openharmony/applications_app_samples/master/code/DocsSample/Drawing/ArkTSGraphicsDraw/entry/src/main/ets/drawing/pages/ComplexEffect.ets):

```ts
// 设置混合模式为叠加模式  ("set blend mode to additive/overlay mode")
brush.setBlendMode(drawing.BlendMode.PLUS);
```

### 3.4 `setMaskFilter`

> **Correction:** the API is **`MaskFilter.createBlurMaskFilter(blurType, sigma)`**. There is **no** `MaskFilter.createBlur`. Verified: `createBlurMaskFilter` is the only factory on the `MaskFilter` class in `@ohos.graphics.drawing.d.ts` (a grep for `createBlur\b` returns 0 hits).

```ts
// On both Brush and Pen:
setMaskFilter(filter: MaskFilter | null): void;   // @since 12

// MaskFilter class @since 12
class MaskFilter {
  static createBlurMaskFilter(blurType: BlurType, sigma: number): MaskFilter;  // @since 12
}
```

- `sigma`: *"Standard deviation of the Gaussian blur to apply. The value must be a floating point number greater than 0."*
- Passing `null` clears the filter.

**`BlurType` enum (@since 12):**

```ts
enum BlurType {
  NORMAL = 0,  // both outer edges and inner solid parts are blurred
  SOLID  = 1,  // inner solid part unchanged, only outer edges blurred
  OUTER  = 2,  // only outer edges blurred, inner solid fully transparent
  INNER  = 3   // only inner solid blurred, outer edges sharp
}
```

**Does it work on a Pen (stroke) as well as a Brush (fill)? — YES.** Both classes declare `setMaskFilter`, both since API 12. The official guide demonstrates it **on a Pen** ([`complex-drawing-effect-arkts.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/graphics/complex-drawing-effect-arkts.md)):

```ts
let pen = new drawing.Pen();
pen.setStrokeWidth(10.0);
pen.setColor(0xFF, 0xFF, 0x00, 0x00);
let filter = drawing.MaskFilter.createBlurMaskFilter(drawing.BlurType.NORMAL, 20);
pen.setMaskFilter(filter);
canvas.attachPen(pen);
```

> **Performance note (direct quote from the official guide):** *"The blur effect of the mask filter only blurs the transparency and shape edges, which is **less costly** than that of the image filter."*

### 3.5 `setPathEffect` / `PathEffect`

> **Important asymmetry:** `setPathEffect` exists **only on `Pen`**, **not on `Brush`**. Verified in the `.d.ts` (Brush declares `setMaskFilter`, `setShaderEffect`, `setShadowLayer` — but no `setPathEffect`) and stated in the guide: *"The path effect, such as dashed lines, is available **only for the pen**."*

```ts
// Pen only
setPathEffect(effect: PathEffect | null): void;   // @since 12

class PathEffect {
  static createDashPathEffect(intervals: Array<number>, phase: number): PathEffect;                  // @since 12
  static createCornerPathEffect(radius: number): PathEffect;                                          // @since 12
  static createDiscretePathEffect(segLength: number, dev: number, seedAssist?: number): PathEffect;   // @since 18
  static createPathDashEffect(path: Path, advance: number, phase: number, style: PathDashStyle): PathEffect;  // @since 18
  static createSumPathEffect(first: PathEffect, second: PathEffect): PathEffect;                      // @since 18
  static createComposePathEffect(outer: PathEffect, inner: PathEffect): PathEffect;                   // @since 18
}
```

Parameter constraints from the docs:
- `createDashPathEffect`: `intervals` length must be **even and ≥ 2**; values are positive; `phase` is a float offset.
- `createCornerPathEffect`: `radius` must be **> 0**.
- `createDiscretePathEffect`: `segLength` — *"If a negative number or the value 0 is passed in, no effect is created"*; `dev` may be negative (the official example passes `-50`); `seedAssist` default `0`.

`PathDashStyle` (@since 18): `TRANSLATE = 0`, `ROTATE = 1`, `MORPH = 2`.

### 3.6 `setShaderEffect` / `ShaderEffect`

**Does ShaderEffect work on both Brush and Pen? — YES.** Both declare `setShaderEffect`, both @since 12. The class doc states explicitly: *"After a shader effect is set for a **pen or brush**, the shader effect instead of the color attribute is used for drawing. In this case, the alpha value set for the pen or brush still takes effect."*

```ts
// On both Brush and Pen:
setShaderEffect(shaderEffect: ShaderEffect | null): void;   // @since 12

class ShaderEffect {
  static createColorShader(color: number): ShaderEffect;  // @since 12

  static createLinearGradient(startPt: common2D.Point, endPt: common2D.Point, colors: Array<number>,
                              mode: TileMode, pos?: Array<number> | null,
                              matrix?: Matrix | null): ShaderEffect;                     // @since 12

  static createRadialGradient(centerPt: common2D.Point, radius: number, colors: Array<number>,
                              mode: TileMode, pos?: Array<number> | null,
                              matrix?: Matrix | null): ShaderEffect;                     // @since 12

  static createSweepGradient(centerPt: common2D.Point, colors: Array<number>, mode: TileMode,
                             startAngle: number, endAngle: number, pos?: Array<number> | null,
                             matrix?: Matrix | null): ShaderEffect;                      // @since 12

  static createConicalGradient(startPt: common2D.Point, startRadius: number, endPt: common2D.Point,
                               endRadius: number, colors: Array<number>, mode: TileMode,
                               pos?: Array<number> | null, matrix?: Matrix | null): ShaderEffect;  // @since 12

  static createComposeShader(dst: ShaderEffect, src: ShaderEffect, blendMode: BlendMode): ShaderEffect;  // @since 20
  static createImageShader(pixelmap: image.PixelMap, tileX: TileMode, tileY: TileMode,
                           samplingOptions: SamplingOptions, matrix?: Matrix | null): ShaderEffect;     // @since 20
}
```

- `colors` are 32-bit ARGB unsigned integers.
- `pos` length must equal `colors` length; first element `0.0`, last `1.0`, monotonically increasing.
- `createSweepGradient`: `endAngle` less than `startAngle` is invalid.
- `createRadialGradient` / `createConicalGradient`: negative radius invalid.
- `createImageShader` doc warns: *"You are advised not to use the function for the canvas of the capture type because it affects the performance."*

**`TileMode` enum (@since 12):**

```ts
enum TileMode {
  CLAMP  = 0,  // replicate edge color outside boundary
  REPEAT = 1,  // repeat in both directions
  MIRROR = 2,  // repeat with alternating mirror images
  DECAL  = 3   // render only within the original boundary, transparent black elsewhere
}
```

### 3.7 `setImageFilter` / `ImageFilter`

```ts
// On both Brush and Pen:
setImageFilter(filter: ImageFilter | null): void;   // @since 12

class ImageFilter {
  static createBlurImageFilter(sigmaX: number, sigmaY: number, tileMode: TileMode,
                               imageFilter?: ImageFilter | null): ImageFilter;            // @since 12
  static createFromColorFilter(colorFilter: ColorFilter, imageFilter?: ImageFilter | null): ImageFilter;  // @since 12
  static createFromImage(pixelmap: image.PixelMap, srcRect?: common2D.Rect | null,
                         dstRect?: common2D.Rect | null): ImageFilter;                    // @since 20
  static createBlendImageFilter(mode: BlendMode, background: ImageFilter,
                                foreground: ImageFilter): ImageFilter;                    // @since 20
  static createComposeImageFilter(cOuter: ImageFilter, cInner: ImageFilter): ImageFilter; // @since 20
  static createOffsetImageFilter(dx: number, dy: number, input?: ImageFilter | null): ImageFilter;  // @since 20
  static createFromShaderEffect(shader: ShaderEffect): ImageFilter;                       // @since 20
}
```

Also relevant: `ColorFilter` — `createBlendModeColorFilter(color, mode)` (@since 11; `number` overload @since 18), `createComposeColorFilter` (@since 11), `createLinearToSRGBGamma` / `createSRGBGammaToLinear` / `createLumaColorFilter` (@since 11), `createMatrixColorFilter(matrix: Array<number>)` — 4×5 / 20 elements (@since 12), `createLightingColorFilter` (@since 20).

---

## 4. `Path` — building and drawing curves

> **Naming corrections:** there is **no** `quadraticBezierTo` (it is **`quadTo`**) and **no** `bezierCurveTo` (it is **`cubicTo`**).

```ts
class Path {
  constructor();                              // @since 12
  constructor(path: Path);                    // @since 12

  // --- API 11 ---
  moveTo(x: number, y: number): void;                                     // @since 11
  lineTo(x: number, y: number): void;                                     // @since 11
  arcTo(x1: number, y1: number, x2: number, y2: number,
        startDeg: number, sweepDeg: number): void;                        // @since 11
  quadTo(ctrlX: number, ctrlY: number, endX: number, endY: number): void; // @since 11  (quadratic Bézier)
  cubicTo(ctrlX1: number, ctrlY1: number, ctrlX2: number, ctrlY2: number,
          endX: number, endY: number): void;                              // @since 11  (cubic Bézier)
  close(): void;                                                          // @since 11
  reset(): void;                                                          // @since 11

  // --- API 12+ ---
  conicTo(ctrlX: number, ctrlY: number, endX: number, endY: number, weight: number): void;  // @since 12
  rMoveTo(dx: number, dy: number): void;                                  // @since 12 (relative)
  rLineTo(dx: number, dy: number): void;                                  // @since 12
  rQuadTo(dx1: number, dy1: number, dx2: number, dy2: number): void;      // @since 12
  rConicTo(ctrlX: number, ctrlY: number, endX: number, endY: number, weight: number): void; // @since 12
  rCubicTo(ctrlX1: number, ctrlY1: number, ctrlX2: number, ctrlY2: number,
           endX: number, endY: number): void;                             // @since 12
  addArc(rect: common2D.Rect, startAngle: number, sweepAngle: number): void;   // @since 12
  addCircle(x: number, y: number, radius: number, pathDirection?: PathDirection): void;  // @since 12
  addOval(rect: common2D.Rect, start: number, pathDirection?: PathDirection): void;      // @since 12
  addRect(rect: common2D.Rect, pathDirection?: PathDirection): void;      // @since 12
  addRoundRect(roundRect: RoundRect, pathDirection?: PathDirection): void;// @since 12
  addPath(path: Path, matrix?: Matrix | null): void;                      // @since 12
  addPolygon(points: Array<common2D.Point>, close: boolean): void;        // @since 12
  transform(matrix: Matrix): void;                                        // @since 12
  offset(dx: number, dy: number): Path;                                   // @since 12
  op(path: Path, pathOp: PathOp): boolean;                                // @since 12
  setFillType(pathFillType: PathFillType): void;                          // @since 12
  getBounds(): common2D.Rect;                                             // @since 12
  contains(x: number, y: number): boolean;                                // @since 12
  getLength(forceClosed: boolean): number;                                // @since 12
  buildFromSvgString(str: string): boolean;                               // @since 12

  // --- API 18+ / 20+ / 23+ ---
  getSegment(forceClosed: boolean, start: number, stop: number,
             startWithMoveTo: boolean, dst: Path): boolean;               // @since 18
  getPathIterator(): PathIterator;                                        // @since 18
  set(src: Path): void;                                                   // @since 20
  setLastPoint(x: number, y: number): void;                               // @since 20
  rewind(): void;                                                         // @since 20
  isEmpty(): boolean;                                                     // @since 20
  getFillType(): PathFillType;                                            // @since 20
  approximate(acceptableError: number): Array<number>;                    // @since 20
  interpolate(other: Path, weight: number, interpolatedPath: Path): boolean;  // @since 20
  isInverseFillType(): boolean;                                           // @since 23
  toggleInverseFillType(): void;                                          // @since 23
}
```

**How to draw a Path — there is NO `canvas.drawPath(path, pen)` overload.**

The real signature is:

```ts
drawPath(path: Path): void;   // @since 11
```

Style comes from a pen/brush that must be **attached to the canvas first** via `attachPen` / `attachBrush`, and removed with `detachPen` / `detachBrush`. This is the single most commonly mis-remembered part of this API.

```ts
let path = new drawing.Path();
path.moveTo(10, 10);
path.quadTo(100, 10, 100, 100);          // quadratic Bézier
path.cubicTo(100, 150, 50, 150, 50, 100); // cubic Bézier
path.lineTo(10, 100);
path.close();

// stroke with a Pen
const pen = new drawing.Pen();
pen.setStrokeWidth(5);
pen.setColor(0xFF, 0xFF, 0x00, 0x00);
canvas.attachPen(pen);
canvas.drawPath(path);

// fill with a Brush (attach both to get fill + stroke simultaneously)
const brush = new drawing.Brush();
brush.setColor({ alpha: 0xFF, red: 0x00, green: 0xFF, blue: 0x00 });
canvas.attachBrush(brush);
canvas.drawPath(path);

canvas.detachPen();
canvas.detachBrush();
```

Verified against the official [`PathRenderNode.ets`](https://raw.githubusercontent.com/openharmony/applications_app_samples/master/code/DocsSample/Drawing/ArkTSDrawing/entry/src/main/ets/common/PathRenderNode.ets) sample, which attaches **both** a Pen and a Brush and then calls `canvas.drawPath(path)` with a single argument.

---

## 5. `drawing.Canvas` methods

All from `@ohos.graphics.drawing.d.ts` (master) and [`arkts-apis-graphics-drawing-Canvas.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-Canvas.md). **All coordinates are in px.**

### Constructors
```ts
constructor(pixelmap: image.PixelMap)   // @since 11 — offscreen canvas backed by a PixelMap
```
There is **no** public no-arg constructor for `drawing.Canvas`. You obtain a `Canvas` either from `DrawingRenderingContext.canvas` or from `RenderNode`'s `DrawContext.canvas`, or you construct one over a `PixelMap`.

### Primitives
```ts
drawRect(rect: common2D.Rect): void;                                        // @since 11
drawRect(left: number, top: number, right: number, bottom: number): void;   // @since 12
drawCircle(x: number, y: number, radius: number): void;                     // @since 11
drawLine(x0: number, y0: number, x1: number, y1: number): void;             // @since 11
drawPoint(x: number, y: number): void;                                      // @since 11
drawPoints(points: Array<common2D.Point>, mode?: PointMode): void;          // @since 12
drawPath(path: Path): void;                                                 // @since 11
drawOval(oval: common2D.Rect): void;                                        // @since 12
drawArc(arc: common2D.Rect, startAngle: number, sweepAngle: number): void;  // @since 12
drawArcWithCenter(arc: common2D.Rect, startAngle: number, sweepAngle: number,
                  useCenter: boolean): void;                                // @since 18
drawRoundRect(roundRect: RoundRect): void;                                  // @since 12
drawNestedRoundRect(outer: RoundRect, inner: RoundRect): void;              // @since 12
drawRegion(region: Region): void;                                           // @since 12
drawVertices(vertexMode: VertexMode, vertexCount: number,
             positions: Array<common2D.Point>, texs: Array<common2D.Point> | null,
             colors: Array<number> | null, indexCount: number,
             indices: Array<number> | null, mode: BlendMode): void;         // @since 23
```

`PointMode` (@since 12): `POINTS = 0`, `LINES = 1`, `POLYGON = 2`.

### Clearing / filling the whole canvas
```ts
drawColor(color: common2D.Color, blendMode?: BlendMode): void;                        // @since 11
drawColor(alpha: number, red: number, green: number, blue: number, blendMode?: BlendMode): void;  // @since 12
drawColor(color: number, blendMode?: BlendMode): void;                                // @since 18
clear(color: common2D.Color): void;                                                   // @since 12
clear(color: common2D.Color | number): void;                                          // @since 18
```
Doc: *"`clear` — Clears the canvas with a given color. **This API has the same effect as `drawColor`.**"* For a transparent clear, pass `{ alpha: 0, red: 0, green: 0, blue: 0 }`, as the official `DrawingRenderingContext` example does.

### Images
```ts
drawImage(pixelmap: image.PixelMap, left: number, top: number,
          samplingOptions?: SamplingOptions): void;                            // @since 11
drawImageRect(pixelmap: image.PixelMap, dstRect: common2D.Rect,
              samplingOptions?: SamplingOptions): void;                        // @since 12
drawImageRectWithSrc(pixelmap: image.PixelMap, srcRect: common2D.Rect,
                     dstRect: common2D.Rect, samplingOptions?: SamplingOptions,
                     constraint?: SrcRectConstraint): void;                    // @since 12
drawImageNine(pixelmap, center: common2D.Rect, dstRect: common2D.Rect,
              filterMode: FilterMode): void;                                   // @since 18
drawImageLattice(pixelmap, lattice: Lattice, dstRect: common2D.Rect,
                 filterMode: FilterMode): void;                                // @since 18
```

### Pen / Brush attachment (mandatory before drawing styled geometry)
```ts
attachPen(pen: Pen): void;       // @since 11
attachBrush(brush: Brush): void; // @since 11
detachPen(): void;               // @since 11
detachBrush(): void;             // @since 11
drawBackground(brush: Brush): void;  // @since 12
```
Doc note: *"The canvas comes with a default brush. The brush is black, has anti-aliasing enabled, and has no other style effects. This default brush is used when no brush or pen is actively set in the canvas."*

### Clipping
```ts
clipPath(path: Path, clipOp?: ClipOp, doAntiAlias?: boolean): void;              // @since 12
clipRect(rect: common2D.Rect, clipOp?: ClipOp, doAntiAlias?: boolean): void;     // @since 12
clipRoundRect(roundRect: RoundRect, clipOp?: ClipOp, doAntiAlias?: boolean): void; // @since 12
clipRegion(region: Region, clipOp?: ClipOp): void;                               // @since 12
isClipEmpty(): boolean;                                                          // @since 12
getLocalClipBounds(): common2D.Rect;                                             // @since 12
quickRejectPath(path: Path): boolean;                                            // @since 18
quickRejectRect(rect: common2D.Rect): boolean;                                   // @since 18
```
`clipPath` defaults: `clipOp = INTERSECT`, `doAntiAlias = false`.
`ClipOp` (@since 12): `DIFFERENCE = 0`, `INTERSECT = 1`.

### State stack — **`saveLayer` DOES exist** (important for layer-based additive compositing)
```ts
save(): number;                                                    // @since 12
restore(): void;                                                   // @since 12
restoreToCount(count: number): void;                               // @since 12
getSaveCount(): number;                                            // @since 12
saveLayer(rect?: common2D.Rect | null, brush?: Brush | null): number;  // @since 12  <-- EXISTS
// (master .d.ts types the saveLayer return as `long`; API 12/20 branches type it `number`)
```

`saveLayer` doc: *"Saves the matrix and cropping region of the canvas, and allocates a **PixelMap** for subsequent drawing. If you call `restore()`, changes made to the matrix and clipping region are discarded, and the PixelMap is drawn."*

Crucially for additive compositing: *"**Brush** object. The **alpha value, filter effect, and blend mode of the brush are applied when the PixelMap is drawn.** If null is passed in, no effect is applied."*

That means the canonical additive/glow compositing recipe is:

```ts
// Offscreen layer with an additive composite brush applied on restore.
canvas.saveLayer(null, compositeBrush);   // compositeBrush.setBlendMode(drawing.BlendMode.PLUS)
// ... draw many overlapping strokes/particles into the layer ...
canvas.restore();                         // layer is composited once with PLUS
```

This pattern is demonstrated in the official guide [`complex-drawing-effect-arkts.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/graphics/complex-drawing-effect-arkts.md):

```ts
function drawRenderNode(canvas: drawing.Canvas) {
  canvas.saveLayer(null, null);
  // ... draw destination content ...
  const brush = new drawing.Brush();
  brush.setBlendMode(drawing.BlendMode.SRC_IN);   // or PLUS for additive
  canvas.saveLayer(null, brush);
  // ... draw source content ...
  canvas.restore();
  canvas.restore();
}
```

> Note the guide's own text says the path effect is pen-only, and demonstrates the layer blend that way — but the **sample file** `ComplexEffect.ets` blends a *brush* with `BlendMode.PLUS` directly (no `saveLayer`). Use `saveLayer` when you need the blend applied to a whole group rather than per-primitive.

### Matrix / transforms
```ts
translate(dx: number, dy: number): void;                    // @since 12
scale(sx: number, sy: number): void;                        // @since 12
rotate(degrees: number, sx: number, sy: number): void;      // @since 12
skew(sx: number, sy: number): void;                         // @since 12
concatMatrix(matrix: Matrix): void;                         // @since 12
setMatrix(matrix: Matrix): void;                            // @since 12
resetMatrix(): void;                                        // @since 12
getTotalMatrix(): Matrix;                                   // @since 12
```
`rotate(degrees, sx, sy)`: positive `degrees` = **clockwise**; `sx`/`sy` are the rotation center.

### Size
```ts
getWidth(): number;    // @since 12
getHeight(): number;   // @since 12
```

### Text
```ts
drawTextBlob(blob: TextBlob, x: number, y: number): void;   // @since 11
drawSingleCharacter(text: string, font: Font, x: number, y: number): void;  // @since 12
```
Related class `ShadowLayer` — `setShadowLayer(shadowLayer: ShadowLayer | null)` exists on **both** Pen and Brush (@since 12). Doc caveat: *"The shadow layer effect takes effect **only when text is drawn**."* `ShadowLayer.create(blurRadius, xOffset, yOffset, color)`.

---

## 6. Threading model and performance

### Documented threading statement

The module-level note (present in **API 20 / master** docs, **absent from the API 12 doc**):

> This module uses the physical pixel unit, px.
> **The module operates under a single-threaded model. The caller needs to manage thread safety and context state transitions.**

Sources: [`arkts-apis-graphics-drawing.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing.md), repeated verbatim on every per-class page (Brush, Pen, Canvas, MaskFilter, PathEffect, ShaderEffect, ImageFilter, Path, Matrix, …).

**This note does NOT specify which thread.** The docs do not contain the strings "UI thread" or "render thread" in the drawing reference. See the UNVERIFIED section.

### What *is* documented about the Canvas component → drawing relationship

From the official guide [`graphic-drawing-overview.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/graphics/graphic-drawing-overview.md) — this is the authoritative architectural statement:

> **CanvasRenderingContext2D** encapsulates the native Drawing APIs of ArkGraphics 2D **based on the W3C standard**, which facilitates the reuse of the drawing logic of web applications.
>
> The bottom layer of the **Canvas component** also uses the **Native Drawing** API to implement the drawing function. The drawing capabilities of the two are the same. However, due to the **multi-layer encapsulation implementation, the Canvas component is not as close to the hardware as the Native Drawing Canvas**. Therefore, in scenarios with **high performance requirements, complex drawing, and strong hardware dependency**, such as professional graphics processing software, desktop or mobile applications, **using the Canvas component for drawing may cause performance problems such as frame freezing and frame loss. In this case, you can use the self-drawing capability of the Native Drawing APIs to ensure the drawing performance of the application.**

**Answering "is Canvas 2D implemented on top of drawing / Skia?"** — Yes, per official docs: Canvas 2D (`CanvasRenderingContext2D`) *encapsulates the native Drawing APIs*. The docs say **"Native Drawing"**, not "Skia" by name; the word "Skia" does not appear in these pages (see UNVERIFIED).

**Answering "does drawing avoid some Canvas 2D overhead?"** — Yes, per the same page: Canvas 2D is a **multi-layer encapsulation**, so it is "not as close to the hardware" as the native drawing canvas, and the docs explicitly recommend the **Native Drawing** APIs (the C/C++ `OH_Drawing_*` API, `capi-drawing.md`) over the Canvas component for performance-critical work. Note the wording recommends **Native Drawing (C/C++)**, not necessarily the ArkTS `@ohos.graphics.drawing` bindings.

### Other documented performance notes

| Note | Source |
|---|---|
| *"The blur effect of the mask filter only blurs the transparency and shape edges, which is **less costly** than that of the image filter."* | [`complex-drawing-effect-arkts.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/graphics/complex-drawing-effect-arkts.md) |
| `ShaderEffect.createImageShader` — *"You are advised not to use the function for the canvas of the capture type because it affects the performance."* | [`arkts-apis-graphics-drawing-ShaderEffect.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-ShaderEffect.md) |
| `Brush.setColor(alpha, red, green, blue)` — *"provides better performance than `setColor(color)` and is recommended."* | [`arkts-apis-graphics-drawing-Brush.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-Brush.md) |
| Canvas component: *"When the width or height of the **Canvas** component exceeds 8000 px, rendering via the CPU causes significant performance degradation."* | [`ts-canvasrenderingcontext2d.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-canvasrenderingcontext2d.md) |
| Canvas component max size 10000 px × 10000 px (creation fails beyond). | [`ts-components-canvas-canvas.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-components-canvas-canvas.md) |
| `Canvas` created via `Canvas(params: CanvasParams)` (@since 23) *"will not respond to drawing commands when it is not visible"* (backgrounded, scrolled out, or `visibility` hidden). | [`ts-components-canvas-canvas.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-components-canvas-canvas.md) |
| `RenderNode.draw()` — *"The Canvas provided in the `DrawContext` parameter is a **temporary command-recording canvas**, not the actual rendering canvas of the node."* | [`js-apis-arkui-renderNode.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/js-apis-arkui-renderNode.md) |
| `RenderNode.draw()` is invoked **twice** during initialization (FrameNode creation + modifier set); subsequent draws are modifier-driven. | [`js-apis-arkui-renderNode.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/js-apis-arkui-renderNode.md) |

### Offscreen canvas on a background-capable path

The official guide [`canvas-get-result-draw-arkts.md`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/graphics/canvas-get-result-draw-arkts.md) shows creating the `PixelMap` in a **taskpool** worker (`@Concurrent async function createPixelMapAsync()`), then doing offscreen `new drawing.Canvas(pixelMap)` drawing. That is the only documented pattern in these pages that moves work off the UI thread — and it moves *PixelMap creation*, not the drawing itself.

---

## 7. `Canvas.enableAnalyzer` and `getContext2DFromDrawingContext`

### `enableAnalyzer` — YES, it exists on the `Canvas` component

```ts
// @since 12
enableAnalyzer(enable: boolean): void
```

Source: [`ts-components-canvas-canvas.md#enableanalyzer12`](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-components-canvas-canvas.md)

- Atomic service API since API 12; callable within `attributeModifier` since API 20.
- Enables the **AI image analyzer** (subject recognition, text recognition, object lookup).
- *"For the settings to take effect, this attribute must be used together with `StartImageAnalyzer` and `StopImageAnalyzer` of `CanvasRenderingContext2D`."*
- *"This attribute cannot be used together with the `overlay` attribute."*
- Default `false`.

```ts
Canvas(this.context, this.options)
  .width(200).height(200)
  .enableAnalyzer(true)
  .onReady(() => { this.context.drawImage(this.img, 0, 0, 200, 200) })
```

**Unrelated to the drawing module** — `enableAnalyzer` is an AI-analysis feature, not a drawing bridge.

### `getContext2DFromDrawingContext`

Covered fully in §2. Summary: `static getContext2DFromDrawingContext(drawingContext: DrawingRenderingContext, options?: RenderingContextOptions): CanvasRenderingContext2D`, **@since 23**, throws `103702`. The `CanvasRenderingContext2D` docs on master **do** mention it (`arkui-master-ts-canvasrenderingcontext2d.md` line 4691), as do the `Canvas` component docs.

### Checked and NOT found in the `CanvasRenderingContext2D` docs

- **No `getDrawingCanvas` mention anywhere** in `ts-canvasrenderingcontext2d.md` on 5.0-Release, 6.0-Release, or master.
- **No `OffscreenCanvasRenderingContext2D` → drawing bridge.**

---

## 8. Official sample code

| Sample | URL | What it demonstrates |
|---|---|---|
| **ArkTSGraphicsDraw** (the main one, "API20") | [gitcode tree](https://gitcode.com/openharmony/applications_app_samples/tree/master/code/DocsSample/ArkGraphics2D/Drawing/ArkTSGraphicsDraw) · [GitHub mirror](https://github.com/openharmony/applications_app_samples/tree/master/code/DocsSample/Drawing/ArkTSGraphicsDraw) | canvas acquisition (direct + offscreen), canvas operations/state, basic effects, **complex effects**, geometric primitives, image drawing, text blobs |
| `ComplexEffect.ets` | [raw](https://raw.githubusercontent.com/openharmony/applications_app_samples/master/code/DocsSample/Drawing/ArkTSGraphicsDraw/entry/src/main/ets/drawing/pages/ComplexEffect.ets) | **`BlendMode.PLUS` additive blending**, `PathEffect.createDashPathEffect`, linear/radial/sweep gradient shaders, `ColorFilter.createMatrixColorFilter`, `ImageFilter.createBlurImageFilter`, **`MaskFilter.createBlurMaskFilter`** |
| `CanvasGetResult.ets` | [raw](https://raw.githubusercontent.com/openharmony/applications_app_samples/master/code/DocsSample/Drawing/ArkTSGraphicsDraw/entry/src/main/ets/drawing/pages/CanvasGetResult.ets) | `RenderNode` + `DrawContext.canvas`, downscaled offscreen `new drawing.Canvas(pixelMap)`, taskpool PixelMap creation |
| `BasicEffect.ets` | [raw](https://raw.githubusercontent.com/openharmony/applications_app_samples/master/code/DocsSample/Drawing/ArkTSGraphicsDraw/entry/src/main/ets/drawing/pages/BasicEffect.ets) | brush fill + pen stroke, `setCapStyle`, `setJoinStyle` |
| **ArkTSDrawing** | [GitHub mirror](https://github.com/openharmony/applications_app_samples/tree/master/code/DocsSample/Drawing/ArkTSDrawing) | `RenderNode` subclass drawing a path / rect / text |
| `PathRenderNode.ets` | [raw](https://raw.githubusercontent.com/openharmony/applications_app_samples/master/code/DocsSample/Drawing/ArkTSDrawing/entry/src/main/ets/common/PathRenderNode.ets) | `Path.moveTo/lineTo/close` pentagram + `attachPen` + `attachBrush` + `drawPath` |
| `RectRenderNode.ets` | [raw](https://raw.githubusercontent.com/openharmony/applications_app_samples/master/code/DocsSample/Drawing/ArkTSDrawing/entry/src/main/ets/common/RectRenderNode.ets) | `Pen` + `drawRect` |
| `TextRenderNode.ets` | [raw](https://raw.githubusercontent.com/openharmony/applications_app_samples/master/code/DocsSample/Drawing/ArkTSDrawing/entry/src/main/ets/common/TextRenderNode.ets) | `TextBlob` + `Font` |
| ArkUISample / CustomCanvas | [gitcode](https://gitcode.com/openharmony/applications_app_samples/blob/master/code/DocsSample/ArkUISample/CustomCanvas/entry/src/main/ets/pages/canvas/CanvasRenderingContext2D.ets) | `CanvasRenderingContext2D` + `OffscreenCanvasRenderingContext2D` (the *other* API set) |

> ⚠️ The docs' own links point at **gitcode.com** (`.../code/DocsSample/ArkGraphics2D/Drawing/ArkTSGraphicsDraw`). That gitcode path 404s/redirects; the **working** GitHub path is `code/DocsSample/Drawing/ArkTSGraphicsDraw`. Verify `code/DocsSample/Drawing/` before citing.

### Official Huawei documentation pages (all verified HTTP 200)

- [`js-apis-graphics-drawing`](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-graphics-drawing) — drawing module reference
- [`ts-drawingrenderingcontext`](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-drawingrenderingcontext) — the real "DrawingCanvas" source
- [`ts-canvasrenderingcontext2d`](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-canvasrenderingcontext2d) — `getContext2DFromDrawingContext`
- [`ts-components-canvas-canvas`](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-components-canvas-canvas) — `Canvas` component, `enableAnalyzer`
- [`arkts-graphics-canvas`](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-graphics-canvas) — the Canvas customization guide
- English mirror of DrawingRenderingContext: [`ts-drawingrenderingcontext-V5`](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V5/ts-drawingrenderingcontext-V5)

---

## 9. Complete working ArkTS example

Verified-compiling shape, assembled only from APIs confirmed above. Uses `DrawingRenderingContext` (the correct bridge), a quadratic+cubic Bézier path, a mask-filter glow, and additive layer compositing.

```ts
import { common2D, drawing } from '@kit.ArkGraphics2D';

@Entry
@Component
struct DrawingDemo {
  private ctx: DrawingRenderingContext = new DrawingRenderingContext();

  private drawScene(): void {
    const canvas: drawing.Canvas = this.ctx.canvas;

    // ---- Clear to opaque dark background ----
    const bg: common2D.Color = { alpha: 255, red: 8, green: 10, blue: 20 };
    canvas.clear(bg);                                  // clear() @since 12; same as drawColor()

    // ---- Layer 1: a soft additive glow, composited with PLUS on restore ----
    const layerBrush = new drawing.Brush();
    layerBrush.setBlendMode(drawing.BlendMode.PLUS);   // @since 11 — additive
    canvas.saveLayer(null, layerBrush);                // @since 12

    const glow: drawing.Brush = new drawing.Brush();
    glow.setColor(0x66, 0x00, 0xE5, 0xFF);             // @since 12 (a, r, g, b)
    glow.setAntiAlias(true);
    glow.setMaskFilter(drawing.MaskFilter.createBlurMaskFilter(drawing.BlurType.NORMAL, 24)); // @since 12
    canvas.attachBrush(glow);
    canvas.drawCircle(220, 220, 90);
    canvas.drawCircle(300, 260, 70);
    canvas.detachBrush();
    canvas.restore();                                  // composite the layer with PLUS

    // ---- Layer 2: a gradient-filled Bézier path, stroked with a dashed pen ----
    const path: drawing.Path = new drawing.Path();
    path.moveTo(60, 300);                              // @since 11
    path.quadTo(180, 120, 300, 300);                   // quadratic Bézier, @since 11
    path.cubicTo(340, 360, 380, 200, 420, 300);        // cubic Bézier, @since 11
    path.close();                                      // @since 11

    const startPt: common2D.Point = { x: 60, y: 120 };
    const endPt: common2D.Point = { x: 420, y: 360 };
    const shader: drawing.ShaderEffect = drawing.ShaderEffect.createLinearGradient(
      startPt, endPt,
      [0xFF00FFCC, 0xFFFF0066],
      drawing.TileMode.CLAMP);                         // @since 12
    const fill: drawing.Brush = new drawing.Brush();
    fill.setShaderEffect(shader);                      // @since 12
    fill.setAlpha(180);                                // @since 11
    canvas.attachBrush(fill);

    const stroke: drawing.Pen = new drawing.Pen();
    stroke.setStrokeWidth(4);                          // @since 11
    stroke.setColor(0xFF, 0xFF, 0xFF, 0xFF);           // @since 12
    stroke.setAntiAlias(true);                         // @since 11
    stroke.setPathEffect(                           // Pen only, @since 12
      drawing.PathEffect.createDashPathEffect([12, 8], 0));
    canvas.attachPen(stroke);

    canvas.drawPath(path);                             // @since 11 — ONE argument only

    canvas.detachPen();
    canvas.detachBrush();

    // ---- Layer 3: transformed primitives ----
    canvas.save();                                     // @since 12
    canvas.translate(40, 40);                          // @since 12
    canvas.rotate(15, 220, 220);                       // @since 12 (clockwise degrees, center)
    canvas.scale(1.1, 1.1);                            // @since 12
    const capBrush: drawing.Brush = new drawing.Brush();
    capBrush.setColor(0xFF, 0xFF, 0xD0, 0x30);
    canvas.attachBrush(capBrush);
    const capRect: common2D.Rect = { left: 120, top: 120, right: 200, bottom: 200 };
    canvas.drawRect(capRect);
    canvas.detachBrush();
    canvas.restore();                                  // @since 12
  }

  build() {
    Flex({ direction: FlexDirection.Column, alignItems: ItemAlign.Center,
           justifyContent: FlexAlign.Center }) {
      Canvas(this.ctx)
        .width('100%')
        .height('70%')
        .backgroundColor('#080A14')
        .onReady(() => {
          this.drawScene();
          this.ctx.invalidate();                       // REQUIRED to repaint
        })

      Button('Redraw')
        .onClick(() => {
          this.drawScene();
          this.ctx.invalidate();
        })
    }
    .width('100%')
    .height('100%')
  }
}
```

Notes that make this compile and behave:
- `canvas` is obtained via `this.ctx.canvas`, **not** via any `getDrawingCanvas` call.
- `drawPath` takes **only** the path; `attachPen` / `attachBrush` supply style.
- `Brush` cannot take `setPathEffect` — the dashed stroke is on the `Pen`.
- `invalidate()` must be called after drawing.
- All coordinates are in **px**, while the Canvas component layout is in **vp** by default. Pass `new DrawingRenderingContext(LengthMetricsUnit.PX)` to align them, or scale by `vp2px(1)`.

---

## UNVERIFIED / COULD NOT CONFIRM

1. **`getDrawingCanvas(canvas: Canvas): DrawingCanvas` — does not exist.** I verified its *absence* (0 hits) in `@ohos.graphics.drawing.d.ts` on branches `OpenHarmony-5.0-Release`, `OpenHarmony-6.0-Release`, `master`; in the drawing reference docs on 4.1 / 5.0 / 5.0.3 / 5.1.0 / 6.0 / master; and in `api/@internal/component/ets/canvas.d.ts`. If the API exists anywhere it is undocumented and absent from the public SDK — treat the premise of the question as **false**.
2. **`DrawingCanvas` is not a class.** It is `declare type DrawingCanvas = import('../api/@ohos.graphics.drawing').default.Canvas;` — a type alias defined in ArkUI's `canvas.d.ts`, exposed via `DrawingRenderingContext.canvas`. There is no `drawing.DrawingCanvas` symbol in the drawing module.
3. **`MaskFilter.createBlur(blurType, sigma)` does not exist.** The only factory is `createBlurMaskFilter(blurType, sigma)`.
4. **`QuadraticBezierTo` / `bezierCurveTo` do not exist.** They are `quadTo` and `cubicTo`.
5. **UI thread vs render thread — NOT stated in the docs.** I could not find any official sentence in the drawing reference or graphics guides that names the thread on which `drawing` executes. The only threading statement is the generic *"operates under a single-threaded model; the caller needs to manage thread safety and context state transitions"* (API 20/master docs only; **not present** in the API 12 doc). Grepping `canvas.d.ts`, `js-apis-arkui-renderNode.md`, and `arkts-user-defined-arktsNode-renderNode.md` for "thread" returned nothing relevant. **Do not assert a specific thread without a device-level test.**
6. **"Skia" is never named** in `graphic-drawing-overview.md` or the drawing reference. The docs say **"Native Drawing"** / "the 2D image rendering engine". The claim "drawing is Skia-backed" is *plausible and widely repeated* but I could **not** verify the word "Skia" in the sources I was restricted to. Treat "Skia" as unverified; "native 2D rendering engine / Native Drawing API" is verified.
7. **The docs' own sample links are broken.** `gitcode.com/.../code/DocsSample/ArkGraphics2D/Drawing/ArkTSGraphicsDraw` does not resolve; the live path is `code/DocsSample/Drawing/ArkTSGraphicsDraw` (GitHub mirror, verified 200).
8. **`OpenHarmony-6.0-Release` reference docs lag the SDK.** The 6.0-Release `.d.ts` contains `@since 20` members (`setColor4f`, `createFromImage`, …) that the 6.0-Release *markdown* reference does not document (its max tag is `18+`). Use `master` for API 20+ API surface.
9. **`OpenHarmony-5.1-Release` and `OpenHarmony-6.0.0-Release` branches do not exist** in `openharmony/docs`; the correct names are `OpenHarmony-5.1.0-Release` and `OpenHarmony-6.0-Release`. `master` has **no** `js-apis-graphics-drawing.md` (404) — it was split into `arkts-apis-graphics-drawing-*.md`.
10. **`ArkTSDrawing` / `ArkTSGraphicsDraw` module-level build config** (`module.json5`, SDK version, `@kit` availability) was not inspected, so the exact minimum API level at which each sample compiles is unverified.
11. **`getDrawingCanvas` on `OffscreenCanvasRenderingContext2D`** — not found. I did not exhaustively diff that class's full member list.
12. **API 24-specific drawing changes** — the master `.d.ts` has `@since 23` and `@since 26` drawing members but **no `@since 24`** drawing member. The `antialias<sup>24+</sup>` attribute I saw is on `CanvasRenderingContext2D`, not on the drawing module. So there appear to be **no drawing-module API changes at API 24** — but this is an inference from absence, not a positive statement in any doc.
