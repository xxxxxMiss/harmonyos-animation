# Animated Glowing Neon Line / Light-Trail on HarmonyOS NEXT — Pure-ArkTS Feasibility Report

**Scope:** HarmonyOS NEXT, ArkTS, Stage model, API 12 → API 24. **No native C++ / NAPI.**
**Target effect:** black background; two thin bright curves (magenta + blue) with white-hot cores and soft colored glow halos; animated continuously along a figure-eight at 60 fps; additive blending; bloom-like falloff.

**Research date:** docs pulled from `openharmony/docs@master` (mirror of the Huawei HarmonyOS guides/references) plus `developer.huawei.com` where noted.
**Verification rule used:** every API below is tagged with the API version printed in the official doc — ⭐ marks the ones additionally **verified against the `@since` tags in the installed HarmonyOS SDK type declarations** (API 24, DevEco 6.1.1.125), which is authoritative where the prose docs are silent. Two claims that the docs leave ambiguous were resolved by exhaustive `grep` over the whole SDK: **`requestAnimationFrame` and `getDrawingCanvas` do not exist.** Anything still unconfirmed is isolated in [§10 Unverified](#10-unverified--could-not-confirm) rather than smoothed over.

> **The single most important finding for implementation:** `CanvasRenderingContext2D` is a *W3C-compatibility wrapper* over the same native Drawing engine that the ArkTS `drawing` module exposes directly, and the official graphics overview says the Canvas component *"is not as close to the hardware as the Native Drawing Canvas"* and *"may cause performance problems such as frame freezing and frame loss"* under high load. For this effect, use `drawing` (§6), not `CanvasRenderingContext2D`.

---

## 1. TL;DR — the recommendation

**Use `@ohos.graphics.drawing`, with `displaySync` as the frame clock.** There are two ArkTS bridges to a live `drawing.Canvas`; both work, pick per your boilerplate tolerance:

| Bridge | Since | Boilerplate | Notes |
|---|---|---|---|
| **B1. `RenderNode` + `NodeController` + `NodeContainer`** | API 11 (RenderNode) | higher (3 classes) | `draw(context: DrawContext)` → `context.canvas` is a `drawing.Canvas`; redraw via `renderNode.invalidate()`. **This is the route the official docs point at for high-performance custom drawing.** |
| **B2. `DrawingRenderingContext` on a `Canvas` component** | API 12 | minimal (~5 lines) | `Canvas(this.ctx)` → `this.ctx.canvas` is a `drawing.Canvas`; redraw via `this.ctx.invalidate()`. Simpler, but goes through the Canvas component's encapsulation layer. |

⚠️ **Official architectural caveat that motivates this whole choice** (verbatim, `graphic-drawing-overview.md`):

> *"**CanvasRenderingContext2D** encapsulates the native Drawing APIs of ArkGraphics 2D based on the W3C standard… The bottom layer of the **Canvas component** also uses the **Native Drawing** API to implement the drawing function. The drawing capabilities of the two are the same. However, due to the **multi-layer encapsulation implementation, the Canvas component is not as close to the hardware as the Native Drawing Canvas**. Therefore, in scenarios with high performance requirements, complex drawing, and strong hardware dependency… using the Canvas component for drawing may cause performance problems such as **frame freezing and frame loss**."*

So `CanvasRenderingContext2D` is a *W3C-compatibility wrapper* over the very engine the `drawing` module exposes directly. You are one encapsulation layer closer by using `drawing`. (Note the doc's own escape hatch is the **Native C/C++** `OH_Drawing_*` API — out of scope here — but the same argument favours the ArkTS `drawing` bindings over `CanvasRenderingContext2D`.)

This is the only pure-ArkTS route that gives you **all four** required primitives at once:

| Requirement | API | Since | Where |
|---|---|---|---|
| Additive blending | `BlendMode.PLUS` (`r = min(s + d, 1)`) | **11** | `drawing.Brush.setBlendMode()` / `drawing.Pen.setBlendMode()` |
| Colored glow halo on a **stroke** | `MaskFilter.createBlurMaskFilter(BlurType.OUTER, sigma)` | API 12 | `drawing.Pen.setMaskFilter()` |
| Cheap blur (documented as cheaper than image filter) | same as above | API 12 | official guide says so explicitly |
| Smooth curve path | `drawing.Path.quadTo()` / `cubicTo()` | 11 | `attachPen(pen)` → `drawing.Canvas.drawPath(path)` → `detachPen()` |
| Per-frame clock | `displaySync.create()` + `on('frame')` | API 11 | `@kit.ArkGraphics2D` |

And it draws the **stroke**, which is what a neon line is. The declarative `Shape`/`Path` route cannot blur a stroke into a colored halo in a controllable way (§4), and `CanvasRenderingContext2D.shadowBlur` gives you only a single offset shadow, not a symmetric bloom (§3.4).

**Fallback for the very oldest target (API 12 exactly):** everything above is API 11/12, so the recommendation holds at API 12. The only API-23 conveniences you lose are `CanvasParams` and `getContext2DFromDrawingContext`, neither of which you need.

**Minimum viable version matrix** — ⭐ = **verified directly against the installed HarmonyOS SDK `@since` tags**, not just the docs (see §1.1):

| Feature you want | Earliest API |
|---|---|
| `drawing` module at all | 11 |
| `drawing.Canvas.drawPath` / `drawLine` / `drawCircle` ⭐ | **11** |
| `drawing.Path.moveTo` / `lineTo` / `quadTo` / `cubicTo` / `reset` ⭐ | **11** |
| `drawing.BlendMode.PLUS` / `SCREEN` / `LIGHTEN` ⭐ | **11** |
| `drawing.Pen/Brush.setBlendMode` ⭐ | **11** |
| `DrawingRenderingContext` (Canvas ↔ drawing bridge) ⭐ | 12 |
| `DrawingRenderingContext.canvas` / `.size` / `.invalidate()` ⭐ | 12 |
| `drawing.BlurType` (`OUTER` / `SOLID`) ⭐ | 12 |
| `MaskFilter.createBlurMaskFilter` ⭐ | 12 |
| `drawing.Pen/Brush.setMaskFilter` ⭐ | 12 |
| `ShaderEffect.createLinearGradient` / `createRadialGradient` ⭐ | 12 |
| `drawing.Pen/Brush.setShaderEffect` ⭐ | 12 |
| `ImageFilter.createBlurImageFilter` ⭐ | 12 |
| `ShadowLayer.create` ⭐ (⚠️ text-only) | 12 |
| `PathEffect.createDashPathEffect` ⭐ | 12 |
| `drawing.Pen.setCapStyle` ⭐ | 12 |
| `drawing.Canvas.saveLayer` / `clear` / `translate` / `rotate` ⭐ | 12 |
| `displaySync.create` / `on('frame')` / `start` / `stop` / `setExpectedFrameRateRange` ⭐ | 11 |
| `CanvasRenderingContext2D.globalCompositeOperation = 'lighter'` ⭐ | 8 |
| `CanvasRenderingContext2D.shadowBlur` / `shadowColor` ⭐ | 8 |
| `CanvasRenderingContext2D.filter` ⭐ | **8** (confirmed, not a later addition) |
| `CanvasRenderingContext2D.createLinearGradient` / `createRadialGradient` ⭐ | 8 |
| `CanvasRenderingContext2D.saveLayer()` / `restoreLayer()` / `reset()` ⭐ | 12 |
| `blendMode()` universal attribute (declarative) | 11 |
| `uiEffect.createFilter()` + `foregroundFilter()` | 12 |
| `Particle` component | **10** |

### 1.1 SDK verification method

Because several doc pages omit `@since` superscripts, I verified the version tags **directly against the installed HarmonyOS SDK**:
`/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/` (API **24**, DevEco Studio 6.1.1.125) and `/Users/chenxianlong/Library/OpenHarmony/Sdk/23/`.

⚠️ **Reading the `.d.ts` tags correctly matters.** The HarmonyOS SDK declares a symbol **multiple times** — one doc block per capability milestone. The **first** block is the original introduction; later blocks re-declare the same signature to add `@crossplatform` (API 20) or `@atomicservice` (API 22). Example, verbatim from `@ohos.graphics.drawing.d.ts`:

```ts
/**
 * Creates a mask filter with a blur effect.
 * ...
 * @since 12                       // ← ORIGINAL: this is the answer
 */
/**
 * Creates a mask filter with a blur effect.
 * ...
 * @crossplatform
 * @since 20                       // ← just "also works cross-platform since 20"
 */
static createBlurMaskFilter(blurType: BlurType, sigma: number): MaskFilter;
```

**Taking the last block instead of the first gives a wrong, too-new answer.** Every ⭐ above is the *first* block's tag.

---

## 2. Why not the other routes (summary)

| Route | Additive blend | Colored glow on stroke | Verdict |
|---|---|---|---|
| **A. `Canvas` 2D (`CanvasRenderingContext2D`)** | ✅ `globalCompositeOperation = 'lighter'` (API 8) | ⚠️ only via `shadowBlur`+`shadowColor` — offset shadow, not symmetric bloom; `filter='blur(Npx)'` blurs the *whole* subsequent draw, so you must draw the glow pass separately | Workable, but strictly weaker than B |
| **B. `@ohos.graphics.drawing` via `RenderNode` or `DrawingRenderingContext`** | ✅ `BlendMode.PLUS` (API 11) | ✅ `MaskFilter` `BlurType.OUTER` on a `Pen` — designed for exactly this | ✅ **Recommended** |
| **C. Declarative `Shape`/`Path` + `shadow()`/`blur()`** | ✅ `.blendMode(BlendMode.PLUS, BlendApplyType.OFFSCREEN)` (API 11) | ❌ `Shape.stroke` takes `ResourceColor` only — **no gradient on a stroke** (gradients colour the fill region); `shadow()` on a stroke is **undocumented/untested** as a glow; must rebuild the `commands` string every frame | Not viable for the full effect |
| **D. `effectKit`** | — | ❌ `createEffect(source: image.PixelMap)` — **PixelMap only**, explicitly not for live components | ❌ Out of scope (fine for pre-baked static glow) |
| **E. `Particle` component** | ❌ no stroke geometry | ❌ discrete points/images only | ❌ can't draw the curve — good as a *spark layer on top* |
| **F. `visualEffect()` / `uiEffect.VisualEffect`** | — | ❌ every `VisualEffect` member is `@systemapi` | ❌ Unusable for third-party apps |

---

## 3. Option A — ArkTS Canvas 2D

### 3.1 Exact declaration

```ts
// RenderingContextSettings
constructor(antialias?: boolean)          // since API 8; default value: false

// CanvasRenderingContext2D
constructor(settings?: RenderingContextSettings)                              // since API 8
constructor(settings?: RenderingContextSettings, unit?: LengthMetricsUnit)    // since API 12

// Canvas component
Canvas(context?: CanvasRenderingContext2D | DrawingRenderingContext)          // since API 8
Canvas(context: CanvasRenderingContext2D | DrawingRenderingContext,
       imageAIOptions: ImageAIOptions)                                        // since API 12
Canvas(params: CanvasParams)                                                  // since API 23
```

Canonical form:

```ts
private settings: RenderingContextSettings = new RenderingContextSettings(true);
private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

Canvas(this.ctx)
  .width('100%').height('100%')
  .backgroundColor(Color.Black)
  .onReady(() => { /* draw here */ })
```

**Caveats (all verbatim from the official reference):**

- *"It is recommended that the `CanvasRenderingContext2D` object and the `Canvas` component be encapsulated into the same custom component, ensuring a one-to-one correspondence and consistent lifecycle between them."*
- *"When you call drawing APIs in this module, the commands are stored in the associated `Canvas` component's command queue. These commands are only executed when the current frame enters the rendering phase and the associated `Canvas` component is visible. Therefore, when the `Canvas` component is invisible (for example, off-screen or hidden), avoid frequent drawing calls to prevent command queue buildup and excessive memory usage."* ← **This is a real trap for a 60 fps loop on a backgrounded page.**
- *"When the width or height of the `Canvas` component exceeds 8000 px, rendering via the CPU causes significant performance degradation."*
- Max `Canvas` size is **10000 px × 10000 px**; beyond that the component fails to create.
- `Canvas` and `OffscreenCanvasRenderingContext2D` do **not** share path state with `CanvasRenderingContext2D` — `beginPath`/`moveTo`/`lineTo`/`closePath`/`bezierCurveTo`/`quadraticCurveTo`/`arc`/`arcTo`/`ellipse`/`rect`/`roundRect` only apply to paths created inside `CanvasRenderingContext2D`.
- Default unit is **vp**, not px. Use `LengthMetricsUnit.PX` (API 12) if you want device pixels — recommended for a glow effect so that blur radii are resolution-independent.

### 3.2 `onReady` and the frame loop

```ts
onReady(event: VoidCallback)                                     // since API 8
onReady(event: Callback<DrawingRenderingContext | undefined>)    // since API 23 (CanvasParams only)
```

**Semantics (verbatim):** *"Triggered when the `Canvas` component is initialized or when its size changes. … When this event is triggered, the canvas is cleared. The width and height of the `Canvas` component are then determined and can be obtained… If only the position of the canvas changes, only the `onAreaChange` event is triggered, not the `onReady` event."*

So: `onReady` is a **one-shot setup hook (re-run on resize)**, *not* a per-frame hook. You must drive frames yourself. See §5.

### 3.3 Glow-relevant property support

| Property | Signature | Blend-relevant values | Since |
|---|---|---|---|
| `globalCompositeOperation` | `string` | `'source-over'`, `'source-atop'`, `'source-in'`, `'source-out'`, `'destination-over'`, `'destination-atop'`, `'destination-in'`, `'destination-out'`, **`'lighter'`**, `'copy'`, `'xor'` | API 8 |
| `shadowBlur` | `number` (px, ≥0, default `0.0`; negative/NaN/Infinity → default) | — | API 8 |
| `shadowColor` | `string` (default `'#00000000'` transparent black) | any `ResourceColor` string | API 8 |
| `shadowOffsetX` / `shadowOffsetY` | `number` | — | API 8 |
| `filter` | `string` | `'none'`, **`'blur(<length>)'`** (px/vp/rem, ≥0, default `blur(0px)`), `'brightness()'`, `'contrast()'`, `'grayscale()'`, `'hue-rotate()'`, `'invert()'`, `'opacity()'`, `'saturate()'`, `'sepia()'`; **combinable**: `'opacity(50%) contrast(200%) grayscale(50%)'` | API 8 |
| `globalAlpha` | `number` | — | API 8 |
| `lineCap` | `CanvasLineCap` = `'butt' \| 'round' \| 'square'` | default `'butt'`; use `'round'` | API 8 |
| `lineJoin` | `CanvasLineJoin` = `'round' \| 'bevel' \| 'miter'` | default `'miter'`; use `'round'` | API 8 |
| `miterLimit` | `number` (px, default 10px) | — | API 8 |
| `setLineDash(segments: number[]): void` / `getLineDash(): number[]` / `lineDashOffset` | — | — | API 8 |
| `createLinearGradient(x0,y0,x1,y1): CanvasGradient` | — | — | API 8 |
| `createRadialGradient(x0,y0,r0,x1,y1,r1): CanvasGradient` | — | — | API 8 |
| `createConicGradient(startAngle,x,y): CanvasGradient` | — | — | **API 10** |
| `bezierCurveTo(cp1x,cp1y,cp2x,cp2y,x,y): void` | — | — | API 8 |
| `quadraticCurveTo(cpx,cpy,x,y): void` | — | — | API 8 |
| `saveLayer(): void` / `restoreLayer(): void` | — | layer-scoped compositing | **API 12** |
| `reset(): void` | — | *"Resets this `CanvasRenderingContext2D` object to its default state and clears the background buffer, drawing state stack, defined paths, and styles."* | API 12 |
| `antialias` | `boolean \| undefined` | overrides `RenderingContextSettings` | **API 24** |
| `letterSpacing` | — | — | API 18 |

**Additive blending answer:** ✅ **`'lighter'` is supported** and is listed in the official enum table with the description *"Displays both the new and existing drawing."* The official example even draws two semi-transparent circles with `'lighter'` and notes *"The overlapping area turns purple (luminance blending)."*

> ⚠️ Unlike web canvas, this is a **string** here, not a numeric enum, and there is no `'screen'` / `'plus-lighter'` string. `'lighter'` is your additive mode. `'destination-out'` is available if you want a fade-to-black trail instead.

### 3.4 `shadowBlur` vs `filter='blur()'` — which gives the halo?

**`shadowBlur` + `shadowColor`** produces an *offset-capable* shadow of the drawn geometry. It **does** work with strokes (`stroke()`) and honours `shadowColor`, so `shadowBlur = 24; shadowColor = 'rgba(255,0,255,0.9)'` before a `stroke()` does give a magenta halo. The limitations that matter for a symmetric neon bloom:

- The shadow is a **copy of the geometry offset by `shadowOffsetX/Y`**. With offsets at `0,0` you get a symmetric halo, so this is usable — but you only get **one** shadow per draw call, so a physically-plausible multi-radius falloff needs repeated stroke passes.
- `shadowBlur` can only be set to a single scalar; there is no spread/opacity curve.
- ⚠️ I found **no official documented performance warning** about `shadowBlur`. See [§10](#10-unverified--could-not-confirm) — treat the widely-reported slowness as *unverified*.

**`filter = 'blur(Npx)'`** is documented and does support `blur(<length>)`. Important behavioural note: `filter` is a **draw-state property** that applies to *subsequent* drawing operations (every example in the docs sets `ctx.filter` and then calls `ctx.drawImage(...)`). It is not a post-process over already-drawn pixels. To use it for bloom you must either:

1. draw the curve with `filter='blur(12px)'` and a wide stroke + additive blend, **then** draw it again crisp with `filter='none'` and a thin white stroke; or
2. render the curve into an `OffscreenCanvas`, then `drawImage` that bitmap back with `filter='blur(12px)'` and `globalCompositeOperation='lighter'`.

**Verdict for Option A:** you can build the effect, but you are composing it by hand out of a whole-canvas filter or a single offset shadow. Option B gives you a purpose-built Gaussian mask filter on the stroke.

### 3.5 Clearing the canvas without flicker

- `clearRect(x, y, w, h)` (API 8) — the standard clear.
- `reset()` (API 12) — clears background buffer **and** resets state/paths/styles. Convenient but resets everything, so you re-set `lineWidth`/`strokeStyle` each frame.
- `globalCompositeOperation = 'destination-out'` + a filled rect — lets you dock the alpha for a decaying trail.
- **Flicker avoidance:** the Canvas is a retained command queue flushed once per render phase, so as long as all your clear+draw calls happen inside the *same* frame callback, you will not see a partially-drawn canvas. Do **not** clear in one `setInterval` tick and draw in another. Keep clear + draw atomic within one frame callback.
- For a full-screen black background, prefer setting `.backgroundColor(Color.Black)` on the component and using `globalCompositeOperation='destination-out'` trail decay, or just `fillRect` black with `'source-over'` — avoids `clearRect` exposing the layer beneath.

### 3.6 Threading & offscreen

- ⚠️ **I could not find any official statement that Canvas 2D renders on a separate render thread.** The drawing module docs say only *"This module operates under a single-threaded model. The caller needs to manage thread safety and context state transitions."* The `@ohos.graphics.displaySync` doc states the frame subscription *"runs in the UI main thread"* and warns *"time-consuming operations related to the UI thread should not run in the subscription function."* **Plan for UI-thread execution.** See §10.
- ✅ **Offscreen canvas exists:** `OffscreenCanvas` + `OffscreenCanvasRenderingContext2D`, same API surface as `CanvasRenderingContext2D`. `OffscreenCanvas.transferToImageBitmap(): ImageBitmap` + `CanvasRenderingContext2D.transferFromImageBitmap(bitmap)` is the documented pairing. The official best-practices guide describes it as *"content to draw onto the canvas is first drawn in the buffer, and then converted into a picture, and finally the picture is drawn on the canvas. This process increases the drawing efficiency."*
- The best-practices guide's **"Controlling Canvas Rendering Based on Component Visibility"** section (using `setOnVisibleAreaApproximateChange`, API 13) exists precisely to stop the command-queue buildup the reference warns about. Also available: `CanvasRenderingContext2D.canvas` (API 13) returns the associated `FrameNode`, or `CanvasRenderingContext2D.canvas` for visibility listening.

---

## 4. Option C — Declarative ArkUI graphics (and why it can't do the whole job)

### 4.1 `Shape` / `Path`

```ts
Shape(value?: PixelMap)                 // since API 7; child components: Rect, Path, Circle, Ellipse, Line, Polyline, Polygon
Path(value?: PathOptions)               // since API 7
```

`Shape` attributes: `viewPort`, `fill`, `fillOpacity`, `stroke`, `strokeDashArray`, `strokeDashOffset`, `strokeLineCap`, `strokeLineJoin`, `strokeMiterLimit`, `strokeOpacity`, `strokeWidth`, `antiAlias`, `mesh` (API 8).

🔴 **Critical:** `stroke(value: ResourceColor)` — **a stroke accepts a plain `ResourceColor` only.** There is no gradient/shader overload of `stroke` anywhere in the API surface.
⚠️ **Careful, the nuance matters:** `linearGradient` / `radialGradient` / `sweepGradient` **are** available on `Shape`/`Path` — they are *universal* attributes and `ShapeAttribute extends CommonMethod<ShapeAttribute>`, so they compile on a `Path`. Their signature has **no `stops` parameter**; the stop position is the **second element of each colour tuple**:
```ts
linearGradient(value: { angle?, direction?, colors: Array<[ResourceColor, number]>, repeating?: boolean })
```
**But they colour the FILL region, not the stroke geometry.** The ArkUI engine source `ShapePaintProperty` declares both paints as plain `Color` (`ACE_DEFINE_PROPERTY_ITEM_WITHOUT_GROUP(Stroke, Color, ...)`).
→ **You cannot give a `Path` stroke a gradient declaratively.** That kills the "white-hot core fading into magenta along the curve" look on this route.
⚠️ No official doc *sentence* states the prohibition; it is an inference from the complete API surface plus engine source. **Confirm with a one-shot on-device test.** For a gradient stroke you must use Canvas 2D `createLinearGradient` → `strokeStyle` (API 8), or `drawing.Pen.setShaderEffect(drawing.ShaderEffect.createLinearGradient(...))` (API 12).

`Path.commands(value: ResourceStr)` (since API 7) supports the full SVG path grammar — verified command table:

| Cmd | Name | Notes |
|---|---|---|
| `M` | moveto | |
| `L` | lineto | |
| `H` | horizontal lineto | |
| `V` | vertical lineto | |
| `C` | cubic Bezier | 6 params |
| `S` | smooth cubic | reflects previous `C`/`S` control point |
| `Q` | quadratic Bezier | |
| `T` | smooth quadratic | reflects previous `Q`/`T` |
| `A` | elliptical arc | `rx ry x-axis-rotation large-arc-flag sweep-flag x y` |
| `Z` | closepath | |

Unit is **px**. Example: `.commands('M0 0 C0 100 140 0 200 150 L100 300 Z')`.

### 4.2 `shadow()` — can it glow a stroke?

```ts
shadow(value: ShadowOptions | ShadowStyle): T                          // since API 10 (ShadowStyle since API 10)
shadow(options: Optional<ShadowOptions | ShadowStyle>): T              // since API 18
```

`ShadowOptions`:

| Field | Type | Since | Note |
|---|---|---|---|
| `radius` | `number \| Resource` | API 8 | **Unit px**, range [0,+∞) |
| `type` | `ShadowType` (`COLOR`=0, `BLUR`=1) | API 10 | default `COLOR` |
| `color` | `Color \| string \| Resource \| ColoringStrategy` | API 8 (`ColoringStrategy` since 11) | default black |
| `offsetX` / `offsetY` | `number \| Resource` | API 8 | unit px |
| `fill` | `boolean` | **API 11** | whether to fill the component interior with the shadow |

`shadow()` is a **universal attribute**, so it applies to a `Shape`/`Path` and *will* tint the rendered stroke. With `radius` and zero offsets you get a symmetric colored halo around the stroke — this is the one declarative thing that works. But:

- You get **one** shadow layer; no multi-radius bloom curve.
- `radius` is in **px**, so you must `vp2px()` for DPI independence.
- ⚠️ No official performance warning found for `shadow()`. Also see `useShadowBatching(value: boolean)` (**API 11**) — *"When this attribute is set, the shadows of all child components are drawn in batches, which reduces the number of rendering instructions"* — a hint that shadows are normally drawn per-component. Use it if you composite many glowing nodes.

### 4.3 `blur()`, `foregroundBlurStyle()`, `backgroundBlurStyle()`, `visualEffect()`, `uiEffect`

```ts
blur(value: number, options?: BlurOptions): T                                    // since API 8 (options API 11)
blur(blurRadius: Optional<number>, options?: BlurOptions): T                     // since API 18
blur(blurRadius: Optional<number>, options?, sysOptions?: SystemAdaptiveOptions) // since API 19
```
Applies a **foreground blur** to the component's own content. ✅ It does blur a stroked `Path`. But it blurs the whole component uniformly — to get "crisp core + blurred halo" you must render **two stacked components**: a blurred colored one underneath and a crisp white one on top.

```ts
foregroundBlurStyle(value: BlurStyle, options?: ForegroundBlurStyleOptions): T   // since API 9/10
backgroundBlurStyle(...)
```
🔴 **Documented performance warning (verbatim):** *"`foregroundBlurStyle` is a real-time blurring API that performs rendering frame by frame, which incurs significant performance overhead. When both the blur content and blur radius remain unchanged, it is recommended that you use the static blur API `blur`."* → **Do not put `foregroundBlurStyle` in a 60 fps animation.**

```ts
visualEffect(effect: VisualEffect): T       // since API 12
backgroundFilter(filter: Filter): T         // since API 12
foregroundFilter(filter: Filter): T         // since API 12
compositingFilter(filter: Filter): T        // since API 12
```
`Filter` / `VisualEffect` here are the `@ohos.graphics.uiEffect` types:

```ts
import { uiEffect } from '@kit.ArkGraphics2D';   // since API 12 — PUBLIC

let filter: uiEffect.Filter = uiEffect.createFilter();   // API 12, PUBLIC
filter.blur(10);                                         // blur(blurRadius: number): Filter, >= 0
```
Then `.foregroundFilter(filter)` on any component. `uiEffect.createFilter()` and `Filter.blur()` are **public** (`SystemCapability.Graphics.Drawing`).

🔴 **Correction — `visualEffect()` is effectively unusable for third-party apps.** Verified against both `master` and the API-12 tag `OpenHarmony-5.0.0-Release` of `@ohos.graphics.uiEffect.d.ts`:

- **API 12 `VisualEffect` has exactly ONE method:** `backgroundColorBlender(blender: BrightnessBlender)` — and it is `@systemapi`.
- Current `master` adds `borderLight` (20), `colorGradient` (20), `liquidMaterial` (22), `distortionCollapse` (26) — **all `@systemapi`**.

So **every member of `VisualEffect` is a system API**; there is no `backgroundBlur` / `foregroundBlur` / `borderRadius` on it. `visualEffect()` therefore has no callable payload for a normal app. ✅ Use `backgroundFilter` / `foregroundFilter` / `compositingFilter` with `uiEffect.Filter` instead.

Also note: **`filter.createBlur` / `createDisplacementMap` / `combine` / `createShader` do not exist.** `@kit.ArkUI` exports no graphics `filter` namespace at all — the `Filter` it exports is `@ohos.arkui.advanced.Filter`, a search-UI component. The real equivalents are `drawing.ImageFilter.createBlurImageFilter(...)` (API 12), `createComposeImageFilter(...)` (API 20), `createFromShaderEffect(...)` (API 20).

💡 `Filter.haloBloom(tintColor, bloomFactor, glowExposure)` — a literal bloom/glow filter — **does** exist, but is `@systemapi` (API 26). Not available to you.

### 4.4 `effectKit` — PixelMap only

```ts
import { effectKit } from '@kit.ArkGraphics2D';   // since API 9
effectKit.createEffect(source: image.PixelMap): Filter
effectKit.createColorPicker(source: image.PixelMap): Promise<ColorPicker>
Filter.blur(radius: number): Filter
Filter.invert() / Filter.setColorMatrix() / Filter.brightness() / Filter.grayscale()
Filter.getEffectPixelMap(): Promise<image.PixelMap>      // since API 11
```

🔴 **Verbatim note from the official doc:** *"This API provides the blur effect for static images. To provide the real-time blur effect for components, use dynamic blur."*
→ **`effectKit` takes an `image.PixelMap`. It does not operate on ArkUI components.** You *could* snapshot a component to a PixelMap and blur it, but that is a per-frame GPU→CPU→GPU round trip — unusable at 60 fps. ❌ Rule it out.

### 4.5 `blendMode()` — the declarative additive-blend win

```ts
blendMode(value: BlendMode, type?: BlendApplyType): T                // since API 11
blendMode(mode: Optional<BlendMode>, type?: BlendApplyType): T       // since API 18
```

- `BlendApplyType.FAST` (default): *"The content of the view is blended in sequence on the target image."*
- `BlendApplyType.OFFSCREEN`: *"The content of the component and its child components are drawn on the offscreen canvas, and then blended with the existing content on the canvas."* ← **you need this** for correct additive compositing of a group. Doc warns it *"may cause issues with screen capture for APIs such as `linearGradientBlur`, `backgroundEffect`, `brightness`, and `blur`."*
- `BlendMode.PLUS` = `13`, `r = min(s + d, 1)` — **additive**. Also `SCREEN` = 15, `LIGHTEN` = 18, `MODULATE` = 14.

So a declarative neon is *expressible* as:

```ts
Stack() {
  // glow layer: wide stroke, colored, blurred
  Path().commands(PATH).stroke(0xFFFF00FF).strokeWidth(18).blur(16)
    .blendMode(BlendMode.PLUS, BlendApplyType.OFFSCREEN)
  // core layer: thin, white
  Path().commands(PATH).stroke(Color.White).strokeWidth(2)
    .blendMode(BlendMode.PLUS, BlendApplyType.OFFSCREEN)
}
.backgroundColor(Color.Black)
```

…but you must **regenerate the `commands` string every frame** from ArkTS (a string build + full path re-parse per frame, per curve), you cannot gradient the stroke, and per-frame `.blur()` is a foreground blur on a re-laid-out component. **Inferior to Option B for this effect.**

### 4.6 `Particle` component — the first-class declarative particle system

```ts
Particle(value: ParticleOptions)      // component since API 10; emitter/disturbanceFields since API 12
```

> *"Particle animation is an animation composed of a multitude of particles randomly generated within a certain range. The particles can be points or images. By animating different aspects of the particles, such as color, opacity, scale, velocity, acceleration, and spin angle, you can create engaging and dynamic aesthetics."*

API surface: `emitter` (`emitRate`, `position`, `shape`, `size`), `disturbanceFields` (12+), `rippleFields` (22+), `velocityFields` (22+); `ParticleType` = `POINT | IMAGE`; `ParticleEmitterShape`; `DistributionType` (12+); `ParticleUpdater` = `RANDOM | CURVE`; `ParticleColorPropertyOptions`, `ParticlePropertyOptions`, `ParticleConfigs`, `PointParticleParameters`, `ImageParticleParameters`.

⚠️ **Documented caveat:** *"If the screen is turned off and then turned on again, or the application is switched to the background and then brought back to the foreground, the particle animation will automatically pause."*

**Relevance to your effect:** ✅ excellent for a **spark / ember / light-mote** layer riding along the figure-eight; ❌ it cannot draw the **continuous glowing curve** itself — particles are discrete points/images, not a stroked path with a Gaussian halo. Use `Particle` as an *accretion* on top of the Option-B curve, not as a replacement.

---

## 5. Frame driving — the four options ranked

### 5.1 `requestAnimationFrame` — does it exist in ArkTS?

🔴 **I could not find `requestAnimationFrame` anywhere in the official OpenHarmony/HarmonyOS API reference.** It is not in `CanvasRenderingContext2D`, not in `UIContext`, not in `@ohos.animator`, and it does not appear in the guides I pulled. The Huawei developer forum question *"Canvas 在绘制线条 如何添加动画，requestAnimationFrame(step) arkTS中没有这个方法呀"* is literally asking this, which corroborates that **there is no global `requestAnimationFrame` in ArkTS**. See [§10](#10-unverified--could-not-confirm).

**Use `displaySync` instead — it is the ArkTS analogue and is officially the mechanism for "draw its custom UI content at a specified frame rate".**

### 5.2 ✅ `@ohos.graphics.displaySync` — **recommended**

```ts
import { displaySync } from '@kit.ArkGraphics2D';    // initial APIs since API 11

displaySync.create(): DisplaySync
DisplaySync.setExpectedFrameRateRange(rateRange: ExpectedFrameRateRange): void
DisplaySync.on(type: 'frame', callback: Callback<IntervalInfo>): void
DisplaySync.off(type: 'frame', callback?: Callback<IntervalInfo>): void
DisplaySync.start(): void
DisplaySync.stop(): void

interface IntervalInfo {
  timestamp: number;        // current frame arrival, NANOSECONDS
  targetTimestamp: number;  // expected next frame arrival, NANOSECONDS
}
```
`ExpectedFrameRateRange` = `{ expected: number, min: number, max: number }`.

**Official caveats (verbatim):**
- *"The `start()` API associates a `DisplaySync` object with a UI instance and window. If the start operation is performed on a non-UI page or in an asynchronous callback, the context of the current UI may not be obtained, causing the API call to fail… you can use `runScopedTask` of `UIContext` to specify the UI context for executing the `start()` API."*
- *"The subscription function runs in the UI main thread. To avoid adverse impact on the performance, time-consuming operations related to the UI thread should not run in the subscription function."*
- *"After `start()` is called, the `stop()` API must be performed and the `DisplaySync` instance must be set to null in the `aboutToDisappear` function to avoid memory leaks."*
- *"The actual frame rate may be different from the expected one configured. It is limited by the system power consumption and hardware capability of the screen refresh rate."*

✅ Use `frameInfo.timestamp` (ns) to compute **delta time**, so motion is frame-rate independent and smooth even if the system drops to 30/90/120 Hz.

### 5.3 `@ohos.animator` / `AnimatorResult`

```ts
import { AnimatorResult } from '@kit.ArkUI';

// deprecated: animator.create(options)
// since API 18:
this.getUIContext().createAnimator(options: AnimatorOptions): AnimatorResult

interface AnimatorResult {
  onFrame?: (progress: number) => void;   // since API 12 — range [begin, end], default [0,1]
  onFinish?: () => void;                  // since API 12
  onCancel?: () => void;                  // since API 12
  onRepeat?: () => void;                  // since API 12
  play(): void; finish(): void; pause(): void; cancel(): void; reverse(): void;
  reset(options: AnimatorOptions): void;             // API 9 / 18
  setExpectedFrameRateRange(rateRange: ExpectedFrameRateRange): void;  // since API 12
}
```
**Verdict:** ✅ usable — set `iterations: -1` for an infinite loop and do your drawing in `onFrame`. But `onFrame` hands you a **normalized progress value**, not a timestamp, so you get no delta-time and no vsync timestamp. ⚠️ **Documented gotcha:** *"When the object of `Animator` is destructed or proactively calls `cancel` or `finish`, an additional `onFrame` API will be triggered. The return value is the end point value of the animation. Therefore, if `cancel` or `finish` is called during the animation, the property value will jump to the end point value within a frame."*
→ **`displaySync` is cleaner for a continuous loop.**

### 5.4 `UIContext.postFrameCallback` — the literal one-frame-later hook

```ts
// @kit.ArkUI
class MyFrameCallback extends FrameCallback {
  onFrame(frameTimeInNano: number): void   // since API 12
  onIdle(timeLeftInNano: number): void     // since API 12
}
this.getUIContext().postFrameCallback(frameCallback: FrameCallback): void              // since API 12
this.getUIContext().postDelayedFrameCallback(frameCallback: FrameCallback,
                                             delayTime: number): void                 // since API 12
```
`FrameCallback.onFrame` gives you `frameTimeInNano`. ✅ This is a viable self-rescheduling loop (call `postFrameCallback` again at the end of `onFrame`). It is lower-level than `displaySync` and gives you **no frame-rate negotiation**. Use it if you need a strict one-shot next-frame hook.

### 5.5 `setInterval` / `setTimeout`

❌ **Not recommended.** They are not vsync-aligned, so you get beat-frequency jitter against the display refresh and cannot hit a stable 60 fps. No official doc endorses them for animation. Fine for a low-frequency state tick; wrong for this.

**Recommendation:** `displaySync` with `{ expected: 60, min: 0, max: 120 }`, delta-time from `frameInfo.timestamp`.

---

## 6. Option B in depth — `@ohos.graphics.drawing`

### 6.1 Module import, and the two bridges

```ts
import { drawing } from '@kit.ArkGraphics2D';
```
> *"The initial APIs of this module are supported since API version 11."*
> *"This module uses the physical pixel unit, **px**."* ← differs from Canvas 2D's default **vp**.
> *"The module operates under a single-threaded model. The caller needs to manage thread safety and context state transitions."*

**Bridge B1 — `RenderNode` + `NodeController` (highest-performance ArkTS route):**

```ts
import { UIContext, NodeController, FrameNode, RenderNode, DrawContext } from '@kit.ArkUI';
import { drawing } from '@kit.ArkGraphics2D';

class NeonRenderNode extends RenderNode {
  draw(context: DrawContext) {          // invoked by the render pipeline
    const canvas: drawing.Canvas = context.canvas;   // ← a real drawing.Canvas
    // ... attachPen / drawPath / detachPen ...
  }
}

class NeonController extends NodeController {
  private rootNode: FrameNode | null = null;
  private node = new NeonRenderNode();
  makeNode(uiContext: UIContext): FrameNode {
    this.rootNode = new FrameNode(uiContext);
    const rn = this.rootNode.getRenderNode();
    if (rn !== null) {
      this.node.backgroundColor = 0xFF000000;          // opaque black
      this.node.frame = { x: 0, y: 0, width: 1080, height: 1080 };
      rn.appendChild(this.node);
      rn.clipToFrame = true;
    }
    return this.rootNode;
  }
  redraw(): void { this.node.invalidate(); }           // request a repaint
}

// usage:  NodeContainer(this.controller).width('100%').height('100%')
```
This is the pattern from the official *"Obtaining a Canvas and Displaying Drawing Results (ArkTS)"* guide. ⚠️ Two documented subtleties: `RenderNode.draw()`'s canvas is *"a temporary command-recording canvas, not the actual rendering canvas"*, and `draw()` is invoked **twice** at initialization. Frames are **px**.

**Bridge B2 (simplest) — `DrawingRenderingContext`, since API 12:**

```ts
// @kit.ArkUI
class DrawingRenderingContext {
  constructor(unit?: LengthMetricsUnit)          // API 12
  get size(): Size                               // API 12  → { width, height }
  get canvas(): DrawingCanvas                    // API 12  → type DrawingCanvas = drawing.Canvas
  invalidate(): void                             // API 12  → "Invalidates the component and triggers re-rendering"
}
```
Bind it to `Canvas(this.context)`, then draw with `this.context.canvas` — a **real `drawing.Canvas`** with the full Brush/Pen/Path/MaskFilter/ShaderEffect API. Call `this.context.invalidate()` after mutating to schedule a repaint.

**Bridge B3 — `CanvasRenderingContext2D.getContext2DFromDrawingContext`, since API 23:**
```ts
static getContext2DFromDrawingContext(drawingContext: DrawingRenderingContext,
                                      options?: RenderingContextOptions): CanvasRenderingContext2D
// options default { antialias: false }; error 103702 if the drawingContext is not bound to a Canvas
```
⚠️ *"The `CanvasRenderingContext2D` object obtained via this API cannot be used as a parameter to create a `Canvas` component. Otherwise, the application crashes."*

🔴 **I found no `getDrawingCanvas(canvas: Canvas)` function in the official docs.** The supported direction is *Canvas component → `DrawingRenderingContext` → `.canvas`*. See [§10](#10-unverified--could-not-confirm).

### 6.2 `Pen` — the stroke workhorse (all since API 12 unless noted)

```ts
new drawing.Pen()
pen.setColor(alpha: number, red: number, green: number, blue: number): void   // API 11
pen.setColor(color: common2D.Color): void                                     // API 12
pen.setColor(color: number): void                                             // API 18  (ARGB hex)
pen.setColor4f(color: common2D.Color4f): void                                 // API 20
pen.setStrokeWidth(width: number): void                                       // API 11
pen.setAntiAlias(aa: boolean): void                                           // API 11
pen.setAlpha(alpha: number): void                                             // API 11
pen.setCapStyle(style: CapStyle): void            // FLAT_CAP | SQUARE_CAP | ROUND_CAP
pen.setJoinStyle(style: JoinStyle): void          // MITER_JOIN | ROUND_JOIN | BEVEL_JOIN
pen.setMiterLimit(miter: number): void
pen.setDither(dither: boolean): void
pen.setBlendMode(mode: BlendMode): void                                       // API 11
pen.setMaskFilter(filter: MaskFilter | null): void                            // API 12
pen.setPathEffect(effect: PathEffect | null): void                            // API 12
pen.setShaderEffect(shaderEffect: ShaderEffect | null): void                  // API 12
pen.setImageFilter(filter: ImageFilter | null): void                          // API 12
pen.setColorFilter(filter: ColorFilter | null): void                          // API 11
pen.setShadowLayer(shadowLayer: ShadowLayer | null): void                     // API 12  ⚠️ SEE WARNING
pen.reset(): void
```

🔴 **`setShadowLayer` warning (verbatim, on both `Pen` and `Brush`):** *"Sets a shadow layer for this pen. **The shadow layer effect takes effect only when text is drawn.**"*
→ **`ShadowLayer` is text-only.** It cannot produce a glow on a stroked path. Do not plan around it.

✅ **`setMaskFilter` is the glow primitive.** From the official guide:

> *"The blur effect of the mask filter only blurs the transparency and shape edges, **which is less costly than that of the image filter.**"*

```ts
// drawing.MaskFilter — class since API 12
static createBlurMaskFilter(blurType: BlurType, sigma: number): MaskFilter    // since API 12

// drawing.BlurType — since API 12
NORMAL = 0   // both outer edges and inner solid parts blurred
SOLID  = 1   // inner solid unchanged, only outer edges blurred
OUTER  = 2   // only outer edges blurred, inner solid FULLY TRANSPARENT
INNER  = 3   // only inner solid blurred, outer edges sharp
```

💡 **This maps exactly onto the neon effect.** `BlurType.OUTER` on a `Pen` = *only the outside of the stroke is blurred, the stroke itself vanishes* → a pure glow halo. `BlurType.SOLID` = *core stays solid, edges blur* → a soft-edged bright line. So:

- **Glow pass:** wide `Pen` + `BlurType.OUTER` + `BlendMode.PLUS` + magenta/blue color.
- **Core pass:** thin `Pen` + `BlurType.SOLID` (or no filter) + white + `BlendMode.PLUS`.

### 6.3 `Brush` — fill (same API shape)

```ts
new drawing.Brush()
brush.setColor(...)                        // API 11 / 12 / 18 / 20 variants as Pen
brush.setAntiAlias(aa: boolean): void
brush.setAlpha(alpha: number): void
brush.setBlendMode(mode: BlendMode): void                                  // API 11
brush.setMaskFilter(filter: MaskFilter | null): void                        // API 12
brush.setShaderEffect(shaderEffect: ShaderEffect | null): void              // API 12
brush.setImageFilter(filter: ImageFilter | null): void                      // API 12
brush.setColorFilter(filter: ColorFilter | null): void                      // API 11
brush.setShadowLayer(shadowLayer: ShadowLayer | null): void                 // API 12 ⚠️ text-only
brush.reset(): void
```
⚠️ `Brush` has **no** `setPathEffect` — path effects (dashes) are **Pen-only**, confirmed by the guide: *"The path effect, such as dashed lines, is available only for the pen."*

### 6.4 ✅ Blend modes — `BlendMode.PLUS` is additive

`drawing.BlendMode` — ⭐ **all 29 members are `@since 11`, SDK-verified.** There is **no `ADD` mode**; `PLUS` *is* the additive mode. Verified values relevant to neon:

| Enum | Value | Formula | Use |
|---|---|---|---|
| `SRC_OVER` | 3 | `r = s + (1 - sa) * d` | normal painting |
| **`PLUS`** | **12** | **`r = min(s + d, 1)`** | ✅ **additive — the neon blend** |
| `MODULATE` | 13 | `r = s * d` | darken |
| **`SCREEN`** | **14** | `r = s + d - s * d` | softer additive glow |
| `OVERLAY` | 15 | — | — |
| **`LIGHTEN`** | **17** | `rc = s + d - min(s * da, d * sa)` | lighten |
| `COLOR_DODGE` | 18 | — | hot cores |
| `MULTIPLY` | 24 | — | — |

Usage:
```ts
const pen = new drawing.Pen();
pen.setBlendMode(drawing.BlendMode.PLUS);
```

### 6.5 ✅ Shaders (gradients) — on both `Pen` and `Brush`

```ts
// drawing.ShaderEffect — all since API 12 unless noted
static createColorShader(color: number): ShaderEffect                                   // 12
static createLinearGradient(startPt: common2D.Point, endPt: common2D.Point,
                            colors: Array<number>, mode: TileMode,
                            pos?: Array<number> | null,
                            matrix?: Matrix | null): ShaderEffect                       // 12
static createRadialGradient(centerPt: common2D.Point, radius: number,
                            colors: Array<number>, mode: TileMode,
                            pos?: Array<number> | null,
                            matrix?: Matrix | null): ShaderEffect                       // 12
static createSweepGradient(centerPt: common2D.Point, colors: Array<number>,
                           mode: TileMode, startAngle?: number, endAngle?: number,
                           pos?: Array<number> | null,
                           matrix?: Matrix | null): ShaderEffect                        // 12
static createConicalGradient(startPt, startRadius, endPt, endRadius,
                             colors, mode, pos?, matrix?): ShaderEffect                 // 12
static createComposeShader(...)                                                         // 20
static createImageShader(...)                                                           // 20
```
- `colors` are **32-bit ARGB unsigned integers** (`0xFFFF00FF` = opaque magenta).
- `pos` must match `colors` length, start at `0.0`, end at `1.0`, strictly increasing.
- `TileMode`: `CLAMP` | `REPEAT` | `MIRROR` | `DECAL`.
- ✅ *"The shader effect is implemented based on the brush or pen. You can use the `setShaderEffect()` API to set the shader effect of the brush or pen."* → **gradients DO work on a stroke.**

💡 **This is how you get the white-hot core that fades into color along the path.** A `ShaderEffect.createLinearGradient` from the trail head to the tail, with `colors = [0xFFFFFFFF, 0xFFFF00FF, 0x00FF00FF]` (white → magenta → transparent magenta) and `pos = [0.0, 0.25, 1.0]`, set on the glow `Pen`. Note gradients are in *canvas space*, not path space, so for a curve you either recompute the gradient endpoints per frame or move the canvas with `canvas.save()/translate()/rotate()/restore()`.

### 6.6 Path building & drawing

```ts
// drawing.Path — class since API 11/12
new drawing.Path()
path.moveTo(x: number, y: number): void                         // 11
path.lineTo(x: number, y: number): void                         // 11
path.quadTo(ctrlX, ctrlY, endX, endY): void                     // 11  ← quadratic Bezier
path.cubicTo(ctrlX1, ctrlY1, ctrlX2, ctrlY2, endX, endY): void  // 11  ← cubic Bezier
path.conicTo(ctrlX, ctrlY, endX, endY, weight): void            // 12
path.arcTo(x1, y1, x2, y2, startDeg, sweepDeg): void            // 11
path.addCircle(x, y, radius): void                              // 12
path.addArc(...) / addOval / addRect / addRoundRect / addPolygon / addPath   // 12
path.rMoveTo / rLineTo / rQuadTo / rConicTo / rCubicTo          // 12  (relative variants)
path.close(): void                                              // 11
path.reset(): void                                              // 11
path.rewind(): void                                             // 20
path.offset(dx, dy): void                                       // 12
path.setLastPoint(x, y): void                                   // 20
path.getLength(forceClosed: boolean): number                    // 12  ← useful for dash-cycling a trail
path.getBounds(): common2D.Rect                                 // 12
path.isEmpty(): boolean                                         // 20
```

Drawing it — 🔴 **`drawPath` takes ONLY a path:**

```ts
canvas.drawPath(path: Path): void      // since API 11 — the ONLY overload (SDK-verified)
```

⚠️ **There is no `drawPath(path, pen)` overload.** Style comes from a pen/brush **attached before** the draw call:

```ts
canvas.attachPen(pen);        // API 11
canvas.drawPath(path);
canvas.detachPen();           // API 12

canvas.attachBrush(brush);    // API 11 — do this too if you want fill
canvas.drawPath(path);
canvas.detachBrush();
```
`attachPen` and `attachBrush` can be active **simultaneously** — the official `PathRenderNode.ets` sample does exactly that (stroke + fill in one `drawPath`). Other draw calls: `drawLine(x0,y0,x1,y1)`, `drawCircle(x,y,r)`, `drawRect(rect)` / `drawRect(l,t,r,b)` — all API 11, all taking their style from the currently attached pen/brush.

### 6.7 `drawing.Canvas` — the operations you need

```ts
// Transform / state (all API 12 unless noted)
canvas.save(): number
canvas.saveLayer(rect?: common2D.Rect | null, brush?: Brush | null): number    // 12  ← layer compositing
canvas.restore(): void
canvas.restoreToCount(count: number): void
canvas.getSaveCount(): number
canvas.translate(dx: number, dy: number): void
canvas.rotate(degrees: number, sx?: number, sy?: number): void
canvas.scale(sx: number, sy: number, px?: number, py?: number): void
canvas.skew(sx: number, sy: number): void
canvas.concatMatrix(matrix: Matrix): void
canvas.setMatrix(matrix: Matrix): void
canvas.resetMatrix(): void
canvas.getTotalMatrix(): Matrix

// Clipping
canvas.clipPath(path: Path, clipOp?: ClipOp, doAntiAlias?: boolean): void    // 12
canvas.clipRect(rect: common2D.Rect, clipOp?: ClipOp, doAntiAlias?: boolean): void
canvas.clipRoundRect(...) / clipRegion(...)
canvas.isClipEmpty(): boolean
canvas.getLocalClipBounds(): common2D.Rect

// Painting
canvas.attachPen(pen: Pen): void
canvas.detachPen(): void
canvas.attachBrush(brush: Brush): void
canvas.detachBrush(): void
canvas.drawPath(path)          // takes ONLY a Path — style comes from the attached pen/brush
canvas.drawLine(x0, y0, x1, y1): void
canvas.drawCircle(x, y, radius): void
canvas.drawRect(rect): void / drawRect(left, top, right, bottom)
canvas.drawRoundRect(roundRect) / drawOval(oval) / drawArc(arc) / drawPoint(x, y) / drawPoints(points)
canvas.drawColor(...)                                   // 11; overloads 12, 18
canvas.clear(color: common2D.Color): void               // 12 ; clear(color: number) 18  ← per-frame clear
canvas.drawShadow(...)                                  // 12 ; overload 18
canvas.drawVertices(...)                                // 23
canvas.getWidth() / getHeight(): number                 // 12

// Culling (API 18) — useful to skip off-screen trail segments
canvas.quickRejectPath(path: Path): boolean
canvas.quickRejectRect(rect: common2D.Rect): boolean
```

💡 **`saveLayer(rect, brush)` is how you do group-level additive compositing**: draw your glow+core into a layer, restore it with a `Brush` whose `blendMode = PLUS`, and the whole group composites additively against the black background in one operation. The official Complex Drawing Effects guide uses exactly this pattern (with `SRC_IN`) as its canonical blend-mode example.

💡 **`canvas.clear(color)` per frame** is the clean clear: `canvas.clear({alpha: 0, red: 0, green: 0, blue: 0})` gives a fully transparent canvas; use opaque black `{alpha:255,...}` if you want to wipe. `invalidate()` afterwards schedules the repaint.

### 6.8 Other drawing-module effects

```ts
// PathEffect (Pen only) — all API 12 unless noted
static createDashPathEffect(intervals: Array<number>, phase: number): PathEffect      // 12
static createCornerPathEffect(radius: number): PathEffect                             // 12
static createPathDashEffect(path, advance, phase, style): PathEffect                  // 18
static createSumPathEffect(first, second): PathEffect                                 // 18
static createDiscretePathEffect(segLength, deviation, seed?): PathEffect              // 18
static createComposePathEffect(outer, inner): PathEffect                              // 18
```
💡 `createDiscretePathEffect` (API 18) is an *electric/neon flicker* primitive — it randomly displaces segments, which is exactly the "unstable neon tube" look. Since it is API 18, it is unavailable at API 12.

```ts
// ImageFilter — API 12 unless noted
static createBlurImageFilter(sigmaX: number, sigmaY: number,
                             tileMode: TileMode, imageFilter?: ImageFilter | null): ImageFilter  // 12
static createFromColorFilter(colorFilter, imageFilter?): ImageFilter                                // 12
static createBlendImageFilter(mode, background, foreground?, ...): ImageFilter                      // 20
static createComposeImageFilter(outer, inner): ImageFilter                                          // 20
static createOffsetImageFilter(...)                                                                 // 20
static createFromShaderEffect(shader): ImageFilter                                                  // 20
```
⚠️ Docs explicitly state mask filter blur is **cheaper** than image filter blur. Prefer `MaskFilter` for glow; use `ImageFilter` only if you need `sigmaX ≠ sigmaY` or composition.

```ts
// ColorFilter — the "white-hot core" trick
static createMatrixColorFilter(matrix: Array<number>): ColorFilter       // 12  (5x4 = 20 floats)
static createBlendModeColorFilter(color: common2D.Color, mode: BlendMode): ColorFilter
static createLinearToSrgbGamma(): ColorFilter
static createSrgbGammaToLinear(): ColorFilter
static createLuminanceColorFilter(): ColorFilter
static createComposeColorFilter(outer, inner): ColorFilter
```
💡 `createMatrixColorFilter` with a matrix that pushes high luminance toward white lets you turn one magenta pen into "magenta glow + white core" without a second geometry pass.

### 6.9 Official samples for the drawing module

- **ArkTSGraphicsDraw (API 20)** — the doc-linked sample for all Drawing APIs:
  `https://gitcode.com/openharmony/applications_app_samples/tree/master/code/DocsSample/ArkGraphics2D/Drawing/ArkTSGraphicsDraw`
  Files referenced by the guides: `entry/src/main/ets/drawing/pages/BasicEffect.ets` and `.../ComplexEffect.ets`.
  ⚠️ **Path discrepancy:** a delegated researcher reported that the doc-linked path above does not resolve and that the live path is `code/DocsSample/Drawing/ArkTSGraphicsDraw` (without the `ArkGraphics2D` segment). Both returned HTTP 200 in my check, but gitcode is a SPA and 200 does not prove the tree exists. **Try both.** The most valuable file is **`ComplexEffect.ets`**, which demos `BlendMode.PLUS` (its Chinese comment says 叠加模式 = additive), the dash path effect, all three gradient shaders, the colour-matrix filter, the blur image filter, and **`createBlurMaskFilter`**. Sibling `ArkTSDrawing` has `PathRenderNode.ets` (Bézier path + `attachPen` + `attachBrush` + `drawPath`), `RectRenderNode.ets`, `TextRenderNode.ets`.
- **`CanvasGetResult.ets`** — the **Bridge B1** sample: `RenderNode` + `NodeController` + `NodeContainer`, direct-display canvas, plus offscreen `new drawing.Canvas(pixelMap)` in a `taskpool` task. Same repo.
- **DisplaySync (API 14)** — per-frame rate sample:
  `https://gitcode.com/openharmony/applications_app_samples/tree/master/code/DocsSample/ArkGraphics2D/DisplaySync`
  Files: `.../DispalySync/CustomDrawDisplaySync.ets` (note: the repo really does spell it "DispalySync"), `.../PropertyAnimationDisplaySync.ets`.
- **CustomCanvas** — the Canvas best-practices sample (offscreen drawing, visibility gating):
  `https://gitcode.com/openharmony/applications_app_samples/tree/master/code/DocsSample/ArkUISample/CustomCanvas`
  Files: `entry/src/main/ets/pages/canvas/OffScreenDrawing.ets`, `CanvasRenderingContext2D.ets`, `CanvasContentUpdate.ets`, `CanvasComponentDrawingMethod.ets`.
- **Particle** — official particle templates live in `applications_app_samples` → `code/DocsSample/ArkUISample/Animation/entry/src/main/ets/pages/particle/template{3,4,5,6}/Index.ets`.
- ⚠️ **No official Huawei/OpenHarmony sample is presented as a neon / glow / light-trail demo, and no official doc frames `shadow()` as a glow mechanism.** The building blocks above are official; the neon composition is yours. See [§10](#10-unverified--could-not-confirm).

---

## 7. Recommended implementation

### 7.1 Architecture

Variant **A** below is the minimal-boilerplate one (`DrawingRenderingContext`, Bridge B2). Swapping in Bridge B1 (`RenderNode` + `NodeController` + `NodeContainer`) is mechanically identical — replace `this.ctx.canvas` with `context.canvas` inside `draw()`, and replace `this.ctx.invalidate()` with `this.renderNode.invalidate()`. Everything from step 3 onward is unchanged.

```
// Variant A: DrawingRenderingContext (Bridge B2)
Canvas(new DrawingRenderingContext(LengthMetricsUnit.PX))   // API 12
  └─ onReady  ──► start displaySync, set up Pens/Paths (once)
  └─ displaySync.on('frame')  ──► per frame:
        1. dt = (frameInfo.timestamp - lastTs) / 1e9
        2. advance trail parameter t += speed * dt
        3. rebuild the two Paths (reuse the same Path + reset(), in px)
        4. ctx.canvas.clear(black)                     // API 12
        5. saveLayer(null, layerBrush)                 // layerBrush.blendMode = PLUS
             for each curve (magenta, then blue offset by PI):
               a. GLOW pass: wide Pen,  BlurType.OUTER, magenta/blue, BlendMode.PLUS
               b. MID  pass: medium Pen, BlurType.SOLID, saturated color, PLUS
               c. CORE pass: thin Pen,   white, PLUS
             (each pass = attachPen -> drawPath(path) -> detachPen)
        6. restoreToCount(layerCount)                  // composites additively
        7. ctx.invalidate()                            // REQUIRED
  └─ aboutToDisappear ──► displaySync.stop(); displaySync = undefined
```

**Critical API-shape reminders for the loop body:**
- `drawPath(path: Path): void` — **only a path**. Style comes from `attachPen`/`attachBrush` called *before*.
- `attachPen`/`attachBrush` can be active **simultaneously**; call `detachPen()`/`detachBrush()` after.
- `clear(color)` is API 12; transparent = `{alpha:0,red:0,green:0,blue:0}`.
- `saveLayer(rect?, brush?)` is API 12; the **brush's alpha, filter effect and blend mode are applied when the layer is drawn**, so `PLUS` on the layer brush = group-level additive compositing.

### 7.2 Runnable ArkTS (API 12 baseline)

```ts
// entry/src/main/ets/pages/NeonEight.ets
import { drawing, common2D, displaySync } from '@kit.ArkGraphics2D';
import { LengthMetricsUnit } from '@kit.ArkUI';

const MAGENTA = 0xFFFF00FF;   // ARGB
const BLUE    = 0xFF00A8FF;
const WHITE   = 0xFFFFFFFF;

@Entry
@Component
struct NeonEight {
  // ---- Canvas <-> drawing bridge (API 12) ----------------------------------
  // PX unit so blur sigmas are in device pixels and DPI-independent.
  private ctx: DrawingRenderingContext =
    new DrawingRenderingContext(LengthMetricsUnit.PX);

  // ---- frame clock (API 11) ------------------------------------------------
  private sync: displaySync.DisplaySync | undefined = undefined;
  private lastTs: number = 0;
  private phase: number = 0;          // seconds along the figure-eight

  // ---- reusable drawing objects (allocate ONCE) ----------------------------
  private glowPen = new drawing.Pen();
  private midPen  = new drawing.Pen();
  private corePen = new drawing.Pen();
  private layerBrush = new drawing.Brush();
  private path = new drawing.Path();

  aboutToAppear(): void {
    // Glow: ONLY the outside is blurred -> pure halo, no visible band
    this.glowPen.setAntiAlias(true);
    this.glowPen.setStrokeWidth(26);
    this.glowPen.setCapStyle(drawing.CapStyle.ROUND_CAP);
    this.glowPen.setJoinStyle(drawing.JoinStyle.ROUND_JOIN);
    this.glowPen.setColor(MAGENTA);
    this.glowPen.setBlendMode(drawing.BlendMode.PLUS);              // additive
    this.glowPen.setMaskFilter(
      drawing.MaskFilter.createBlurMaskFilter(drawing.BlurType.OUTER, 18));

    // Mid: solid core, softly blurred edges -> the hot colored line
    this.midPen.setAntiAlias(true);
    this.midPen.setStrokeWidth(8);
    this.midPen.setCapStyle(drawing.CapStyle.ROUND_CAP);
    this.midPen.setJoinStyle(drawing.JoinStyle.ROUND_JOIN);
    this.midPen.setColor(MAGENTA);
    this.midPen.setBlendMode(drawing.BlendMode.PLUS);
    this.midPen.setMaskFilter(
      drawing.MaskFilter.createBlurMaskFilter(drawing.BlurType.SOLID, 4));

    // Core: thin white-hot filament
    this.corePen.setAntiAlias(true);
    this.corePen.setStrokeWidth(2);
    this.corePen.setCapStyle(drawing.CapStyle.ROUND_CAP);
    this.corePen.setJoinStyle(drawing.JoinStyle.ROUND_JOIN);
    this.corePen.setColor(WHITE);
    this.corePen.setBlendMode(drawing.BlendMode.PLUS);

    // Layer-compositing brush. Docs for saveLayer: "The alpha value, filter
    // effect, and blend mode of the brush are applied when the PixelMap is drawn"
    // -> PLUS here makes the whole layer composite additively in one operation.
    this.layerBrush.setColor({ alpha: 255, red: 255, green: 255, blue: 255 });
    this.layerBrush.setBlendMode(drawing.BlendMode.PLUS);
  }

  aboutToDisappear(): void {
    if (this.sync) {
      this.sync.stop();
      this.sync = undefined;     // required by the docs to avoid a leak
    }
  }

  // ---- build a figure-eight (lemniscate of Gerono) into this.path ----------
  private buildEight(cx: number, cy: number, ax: number, ay: number,
                     t: number, trailSpan: number, segments: number): void {
    this.path.reset();
    for (let i = 0; i <= segments; i++) {
      const u = t - (trailSpan * i) / segments;   // walk backwards = trail
      const x = cx + ax * Math.sin(u);
      const y = cy + ay * Math.sin(u) * Math.cos(u);
      if (i === 0) {
        this.path.moveTo(x, y);
      } else {
        this.path.lineTo(x, y);                   // dense polyline ≈ smooth curve
      }
    }
  }

  private startLoop(): void {
    const range: ExpectedFrameRateRange = { expected: 60, min: 0, max: 120 };
    this.sync = displaySync.create();
    this.sync.setExpectedFrameRateRange(range);
    this.sync.on('frame', (info: displaySync.IntervalInfo) => {
      const dt = this.lastTs === 0 ? 0 : (info.timestamp - this.lastTs) / 1e9;
      this.lastTs = info.timestamp;
      this.render(dt);
    });
    // start() must run inside the UI context
    this.getUIContext().runScopedTask(() => { this.sync?.start(); });
  }

  // Helper: attach the pen, stroke the shared path, detach.
  // NOTE: drawPath() takes ONLY a Path (SDK-verified) -- the pen/brush must be
  // attached BEFORE the draw call and detached AFTER.
  private strokePath(canvas: drawing.Canvas, pen: drawing.Pen): void {
    canvas.attachPen(pen);
    canvas.drawPath(this.path);
    canvas.detachPen();
  }

  private render(dt: number): void {
    const canvas = this.ctx.canvas;
    const w = this.ctx.size.width;
    const h = this.ctx.size.height;
    this.phase += dt * 1.1;

    // 1. clear -- clear(color) is API 12 and is documented as equivalent to drawColor
    canvas.clear({ alpha: 255, red: 0, green: 0, blue: 0 });

    // 2. group-additive layer: on restore, layerBrush's blend mode (PLUS) is applied
    const layerCount = canvas.saveLayer(null, this.layerBrush);

    // 3. magenta curve: glow -> mid -> core, each an attach/draw/detach triple
    this.buildEight(w * 0.5, h * 0.5, w * 0.34, h * 0.34, this.phase, 3.2, 96);
    this.strokePath(canvas, this.glowPen);
    this.strokePath(canvas, this.midPen);
    this.strokePath(canvas, this.corePen);

    // 4. blue curve, offset half a period -> the two cross at the centre
    this.glowPen.setColor(BLUE);
    this.midPen.setColor(BLUE);
    this.buildEight(w * 0.5, h * 0.5, w * 0.34, h * 0.34,
                    this.phase + Math.PI, 3.2, 96);
    this.strokePath(canvas, this.glowPen);
    this.strokePath(canvas, this.midPen);
    this.strokePath(canvas, this.corePen);

    canvas.restoreToCount(layerCount);

    // 5. schedule the repaint -- REQUIRED; nothing repaints without it
    this.ctx.invalidate();
  }

  build() {
    Stack() {
      Canvas(this.ctx)
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)
        .onReady(() => {
          if (this.sync === undefined) {
            this.startLoop();
          }
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }
}
```

### 7.3 Why this reproduces the target look

| Target feature | Mechanism |
|---|---|
| white-hot core | separate 2 px `corePen` at `0xFFFFFFFF`, `BlendMode.PLUS` |
| colored glow halo | `glowPen` 26 px with `MaskFilter` `BlurType.OUTER` σ=18 → **only** the outside blurs, so the halo has no hard inner band |
| soft falloff, bloom-like | three concentric passes (26 px / 8 px / 2 px) with decreasing blur σ; additive stacking produces a smooth Gaussian-ish profile |
| additive blending | `BlendMode.PLUS` on every pen + a `saveLayer` so the group composites once |
| two thin curves, magenta + blue | one `Path`, drawn three times — re-color the shared pens between the two curves |
| 60 fps, continuous | `displaySync` at `expected: 60`, delta-time integration, no per-frame allocation |
| no flicker | `clear()` + all draws + `invalidate()` happen inside one frame callback |

### 7.4 Per-frame allocation discipline

The code above allocates **zero** objects per frame: `Pen`/`Brush`/`Path` are created once; `path.reset()` reuses the same path; `buildEight` writes into it. This matters because `displaySync`'s callback runs on the UI main thread (documented).

If you need per-frame `common2D.Color` objects, hoist them into fields — `drawing` APIs take `common2D.Color` by value.

---

## 8. API 12 vs later — what you give up below API 24

| Capability | Since | Impact on this effect |
|---|---|---|
| `drawing` module | 11 | ✅ fine |
| `DrawingRenderingContext` | 12 | ✅ fine — this is the whole bridge |
| `MaskFilter.createBlurMaskFilter` | 12 | ✅ fine — the glow |
| `BlendMode.PLUS` | 12 | ✅ fine |
| `Path.quadTo` / `cubicTo` | 11 | ✅ fine |
| `Canvas.saveLayer` | 12 | ✅ fine |
| `displaySync` | 11 | ✅ fine |
| `PathEffect.createDiscretePathEffect` (electric flicker) | **18** | ❌ unavailable at 12 |
| `Path.getSegment` | 18 | ❌ |
| `Canvas.quickRejectPath/Rect` (culling) | 18 | ❌ |
| `drawing.Vertices` / `Canvas.drawVertices` (batched particles) | **23** | ❌ — matters only if you add a particle spark layer |
| `Canvas(params: CanvasParams)` (no command caching) | **23** | ❌ — see below |
| `getContext2DFromDrawingContext` | **23** | ❌ — not needed |
| `CanvasRenderingContext2D.antialias` attribute | **24** | ❌ — use `RenderingContextSettings(true)` |
| `ShadowLayer.create(..., color: number)` | 18 | ❌ — use the `common2D.Color` overload (API 12) |
| `Brush/Pen.setColor4f` | 20 | ❌ |

🔴 **Most important API-23 gap:** the default `Canvas` component **caches drawing commands**. The API-23 `CanvasParams` constructor exists specifically to create *"a `Canvas` component that does not cache commands for drawing"*, and it also documents that such a component *"will not respond to drawing commands when it is not visible."* At API 12 you are on the caching path, so you **must** pair your loop with visibility gating (`setOnVisibleAreaApproximateChange`, API 13) or stop the `displaySync` when the page is not foregrounded — otherwise you accumulate commands, which the reference explicitly warns causes *"command queue buildup and excessive memory usage."*

---

## 9. Performance checklist (all doc-grounded)

1. ✅ **Use `MaskFilter`, not `ImageFilter`, for glow.** Official: mask-filter blur *"only blurs the transparency and shape edges, which is less costly than that of the image filter."*
2. ✅ **Keep `Canvas` under 8000 px** in each dimension — beyond that *"rendering via the CPU causes significant performance degradation."* Hard cap 10000 px.
3. ✅ **Gate on visibility.** Use `setOnVisibleAreaApproximateChange` (API 13) or `CanvasRenderingContext2D.canvas` (API 13) → `FrameNode.commonEvent.setOnVisibleAreaApproximateChange(...)`; stop `displaySync` when hidden. The reference warns about command-queue buildup on invisible canvases.
4. ✅ **Never call UI-thread-heavy work in the `displaySync` callback.** Verbatim warning in the doc.
5. ✅ **Always `stop()` + null the `DisplaySync` in `aboutToDisappear`.** Verbatim: required *"to avoid memory leaks."*
6. ✅ **Prefer `LengthMetricsUnit.PX`** for `DrawingRenderingContext`/`CanvasRenderingContext2D` so blur sigma and stroke widths are in physical pixels and don't rescale across densities.
7. ❌ **Avoid `foregroundBlurStyle` / `backgroundBlurStyle` / `backdropBlur` / `blur` / `motionBlur` in the animation.** Verbatim: *"The preceding APIs are real-time blurring APIs that perform rendering on a frame-by-frame basis, which incurs significant performance overhead. When both the blur content and blur radius remain unchanged, it is recommended that you use the static blur API `blur`."* Official measurements from the in-repo best-practice doc (`zh-cn/application-dev/performance/fuzzy_scene_performance_optimization.md`): dynamic blur ≈ **6.113 ms / 108 fps** vs static blur ≈ **3.357 ms / 119.9 fps** — **≈45 % less render time** when static.
8. ❌ **Do not wrap a per-frame-animated glow subtree in `renderGroup(true)`.** `renderGroup` (API 10+) renders a subtree offscreen and caches it — but the official performance guide documents the negative case: when children animate every frame the cache is invalidated every frame (frame-drop 77 % → 100 %, `FlushFrame` 3 ms → 15 ms). Note `blendMode(..., OFFSCREEN)` already forces an offscreen canvas, so you are paying for one anyway.
9. 💡 **For a static/pre-baked glow**, the cheap pattern is: render the glow once → blur with `effectKit` on a `PixelMap` → display as `Image` → animate only opacity/scale. Avoids the per-frame blur cost entirely. Only viable if the geometry does not change per frame.
8. ❌ **Avoid `effectKit` for live content** — PixelMap-only, static-image oriented. See item 9 for its only good use.
9. ⚠️ **`useShadowBatching(true)`** if you fall back to per-node `shadow()` for many glowing elements. API 11+: *"Sets whether to render child node shadows at the same layer, enabling shadow overlap within the same layer."*
10. ✅ **Reuse `Path`/`Pen`/`Brush` objects**; `path.reset()` instead of `new drawing.Path()` per frame.
11. ✅ **Prefer `BlendApplyType.OFFSCREEN`** for group additive blending declaratively; note it *"may cause issues with screen capture"* for `blur`/`backgroundEffect`/`brightness`/`linearGradientBlur`. `BlendMode.NONE` silently degrades to `SRC_OVER` and ignores `type`.
12. 💡 **`pixelRound`** may be needed to avoid hairline seams where two components sharing a `blendMode` edge land on fractional pixel coordinates.

---

## 10. Unverified / could not confirm

These are things I could **not** substantiate from an official Huawei/OpenHarmony source. Treat them as open questions, not facts.

1. **`getDrawingCanvas(canvas: Canvas): DrawingCanvas`** — ✅ **RESOLVED: IT DOES NOT EXIST.** `grep -rn "getDrawingCanvas"` over the entire installed HarmonyOS SDK (`.../ets/component`, `/api`, `/kits`, `/arkts`) returns **0 hits**, and it appears in no `openharmony/docs` branch. `DrawingCanvas` is **only a type alias** — `type DrawingCanvas = Canvas` where `Canvas` is `drawing.Canvas`; there is no `getDrawingCanvas` free function and no `drawing.DrawingCanvas` class. Use Bridge B1 (`RenderNode.draw(context)`) or Bridge B2 (`DrawingRenderingContext.canvas`).
2. **Global `requestAnimationFrame` in ArkTS** — ✅ **RESOLVED: IT DOES NOT EXIST.** `grep -rn "requestAnimationFrame"` over the entire installed HarmonyOS SDK (`component`, `api`, `kits`, `arkts`) returns **0 hits**. The only matches anywhere under the DevEco install are inside the bundled TypeScript compiler's own `lib.dom.d.ts` / `lib.webworker.d.ts` and a linter's `globals.json` — i.e. **web** typings that ArkTS does not expose. There is no `UIContext.requestAnimationFrame` either. Use `displaySync` (§5.2) or `UIContext.postFrameCallback` (§5.4).
3. **Canvas 2D UI-thread vs render-thread** — ⚠️ **Still not answerable from the docs, even after SDK inspection.** Neither the Canvas reference, the Canvas best-practices guide, the drawing module docs, `canvas.d.ts`, nor the RenderNode docs name the executing thread. What *is* documented: (a) the drawing module is *"single-threaded"* — and that note appears **only in API 20/master docs, it is absent from the API 12 docs**; (b) the `displaySync` frame callback *"runs in the UI main thread"*; (c) the official graphics overview recommends **Native (C/C++) Drawing** — not any ArkTS binding — for *"high performance requirements… frame freezing and frame loss"*, which implies the ArkTS paths are not render-thread-exempt. **Assume UI-thread and measure on device; do not assert a render thread.**
4. **`CanvasRenderingContext2D.shadowBlur` slowness/bugs** — ⚠️ **No official performance warning or bug note found.** The reference documents `shadowBlur` neutrally (float ≥ 0, px). Community reports of slowness are plausible but I could not verify them against an official source. Do not cite a "documented" slowness — there isn't one.
5. **`CanvasRenderingContext2D.filter` "since which API"** — ✅ **RESOLVED: API 8.** SDK-verified from `component/canvas.d.ts` — the first doc block for the `filter` property carries `@since 8`. Same for `shadowBlur`, `shadowColor`, `shadowOffsetX/Y`, `globalCompositeOperation`, `createLinearGradient`, `createRadialGradient`, `setLineDash`, `quadraticCurveTo`, `bezierCurveTo` — **all API 8**. `saveLayer` / `restoreLayer` / `reset` are **API 12**.
6. **Official neon / light-trail / particle sample** — ❌ **Not found.** The official samples I could confirm are the three listed in §6.9 (ArkTSGraphicsDraw, DisplaySync, CustomCanvas). No official "glow"/"neon"/"particle" sample surfaced in the docs or the `applications_app_samples` doc-linked paths.
7. **Huawei best-practice page "Using Custom Drawing to Improve Performance"** — the page exists at
   `https://developer.huawei.com/consumer/en/doc/best-practices-V5/bpta-drawing-capability-improve-performance-V5`
   but it is **JavaScript-rendered**; `web_fetch` returned only an empty document shell. **Its content is unverified.** Read it manually in a browser.
8. **Community/blog sources** — several CSDN / 51CTO / ost.51cto articles on "HarmonyOS Canvas performance", "分层渲染架构", "Canvas 粒子动画" appeared in search results. **I deliberately did not use them as sources** for any claim in this report, since they are not official. They may contain useful engineering war stories; verify independently.
9. **Exact `CanvasParams` / API-23 semantics at runtime** — I read the doc but could not test. The claim that the non-caching `Canvas` *"will not respond to drawing commands when it is not visible"* is quoted verbatim but untested.
10. **`displaySync` requiring a specific permission** — ❌ **Not found.** The `@ohos.graphics.displaySync` reference and the variable-frame-rate guides list no permission requirement. (`NativeDisplaySoloist` is the C/C++ route and is explicitly out of scope here.)
11. **Gradient-on-stroke prohibition has no prose source.** No official sentence states *"gradients do not apply to a `Shape`/`Path` stroke."* The conclusion in §4.1 rests on (a) the complete documented attribute surface containing only `stroke(value: ResourceColor)`, (b) `ShapeAttribute extends CommonMethod<ShapeAttribute>`, and (c) ArkUI engine source `ShapePaintProperty` declaring `Fill`/`Stroke` as plain `Color`. It is an **inference**, not a quote. **On-device test advised.**
12. **`shadow()` on a `Shape`/`Path` stroke** — ⚠️ **No official statement either way.** No document says whether the shadow silhouette is taken from the *stroked path geometry* or from the component box, nor whether a background is required. `fill: true` (API 11+) implies silhouette-based shadow generation. The only official example using `shadow({ radius: >0, offsetX: 0, offsetY: 0 })` is a *shadow* demo (the `useShadowBatching` example), **never a glow recipe**. Treat the glow trick as untested.
13. **`shadow()` performance / offscreen claims** — ❌ **None documented.** I searched `ts-universal-attributes-image-effect.md` (en + zh-cn) and `ts-universal-attributes-background.md`: there is no *"shadow forces offscreen rendering"* sentence. Do not cite one.
14. **Lowercase / relative SVG path commands in `Path.commands`** — ⚠️ Only the **uppercase (absolute)** forms `M L H V C S Q T A Z` appear in the official table. Whether `m l h v c s q t a z` (relative) are accepted is **unverified**.
15. **`renderGroup` / `Particle` numeric claims** — the frame-drop 77 % → 100 % and `FlushFrame` 3 ms → 15 ms figures come from `zh-cn/application-dev/performance/reasonable-using-renderGroup.md` via a delegated researcher; I did not fetch that file directly. The `Particle` API-10 baseline I *did* verify first-hand (`"This component is supported since API version 10"`).
16. **`uiEffect` / `@ohos.graphics.uiEffect.d.ts` access levels** — the `@systemapi` markings on `VisualEffect` and `Filter` methods were verified against the `interface_sdk-js` `.d.ts` (master + `OpenHarmony-5.0.0-Release` tag) by a delegated researcher, not by me directly. They are consistent with the public `js-apis-uiEffect.md` documenting only `blur()`.

---

## 11. Source URLs

### 11.1 ArkUI Canvas 2D
- `Canvas` component — https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-components-canvas-canvas
  mirror: https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-components-canvas-canvas.md
- `CanvasRenderingContext2D` — https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-canvasrenderingcontext2d
  mirror: https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-canvasrenderingcontext2d.md
- `OffscreenCanvasRenderingContext2D` — https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-offscreencanvasrenderingcontext2d
  mirror: https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-offscreencanvasrenderingcontext2d.md
- `DrawingRenderingContext` — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-drawingrenderingcontext.md
- Canvas best practices (Drawing Custom Graphics; offscreen; visibility; state-variable refresh) — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/ui/arkts-drawing-customization-on-canvas.md
  Chinese: https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/ui/arkts-drawing-customization-on-canvas.md

### 11.2 `@ohos.graphics.drawing`
- Module overview — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing.md
- `Canvas` — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-Canvas.md
- `Pen` — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-Pen.md
- `Brush` — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-Brush.md
- `Path` — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-Path.md
- `MaskFilter` — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-MaskFilter.md
- `ShadowLayer` — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-ShadowLayer.md
- `PathEffect` — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-PathEffect.md
- `ShaderEffect` — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-ShaderEffect.md
- `ImageFilter` — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-ImageFilter.md
- `ColorFilter` — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-ColorFilter.md
- Enums (`BlendMode`, `BlurType`, `TileMode`, `CapStyle`, `JoinStyle`) — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-e.md
- Guide: Complex Drawing Effects (ArkTS) — blend modes, path effects, shaders, filters — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/graphics/complex-drawing-effect-arkts.md
- Guide: Basic Drawing Effects (ArkTS) — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/graphics/basic-drawing-effect-arkts.md
- Guide: Drawing Effect Overview — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/graphics/drawing-effect-overview.md
- Guide: Geometric Shape Drawing (ArkTS) — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/graphics/geometric-shape-drawing-arkts.md

### 11.3 Frame driving
- `@ohos.graphics.displaySync` — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/js-apis-graphics-displaySync.md
- Guide: Requesting Frame Rates for UI Components — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/graphics/displaysync-ui.md
- Guide: Requesting Frame Rates for Animations — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/graphics/displaysync-animation.md
- Guide: Introduction to Variable Frame Rates — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/graphics/displaysync-overview.md
- `@ohos.animator` — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/js-apis-animator.md
- `FrameCallback` — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkts-apis-uicontext-framecallback.md
- `UIContext` (`postFrameCallback`, `postDelayedFrameCallback`, `createAnimator`, `runScopedTask`, `vp2px`) — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkts-apis-uicontext-uicontext.md
- Huawei forum: "Canvas 在绘制线条 如何添加动画，requestAnimationFrame(step) arkTS中没有这个方法呀" — https://developer.huawei.com/consumer/cn/forum/topic/0203168716307777786
- Huawei blog: "第二十五课：动画循环——使用 requestAnimationFrame 让 Canvas 动起来" — https://developer.huawei.com/consumer/cn/blog/topic/03222887748154144

### 11.4 Declarative ArkUI graphics
- `Shape` — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-drawing-components-shape.md
- `Path` (+ SVG path syntax table) — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-drawing-components-path.md
- Universal image effects (`blur`, `shadow`, `blendMode`, `BlendApplyType`, `BlendMode`, `ShadowOptions`, `ShadowType`, `useShadowBatching`, `linearGradientBlur`) — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-image-effect.md
- `foregroundBlurStyle` / `BlurOptions` — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-foreground-blur-style.md
- `visualEffect` / `backgroundFilter` / `foregroundFilter` / `compositingFilter` — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-filter-effect.md
- `@ohos.graphics.uiEffect` — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/js-apis-uiEffect.md
- `@ohos.graphics.uiEffect` **SDK declarations** (the `@systemapi` markings) — https://raw.githubusercontent.com/openharmony/interface_sdk-js/master/api/@ohos.graphics.uiEffect.d.ts and the API-12 tag https://raw.githubusercontent.com/openharmony/interface_sdk-js/OpenHarmony-5.0.0-Release/api/@ohos.graphics.uiEffect.d.ts
- `@ohos.effectKit` — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/js-apis-effectKit.md
- `@ohos.effectKit` **SDK declarations** — https://raw.githubusercontent.com/openharmony/interface_sdk-js/master/api/@ohos.effectKit.d.ts
- `Particle` component — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-particle-animation.md
- Particle animation guide (zh-cn) — https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/ui/arkts-particle-animation.md
- Blur performance best practice (zh-cn, has the ms/fps numbers) — https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/performance/fuzzy_scene_performance_optimization.md
- `renderGroup` performance pitfall (zh-cn) — https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/performance/reasonable-using-renderGroup.md
- Dynamic blur guide — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/ui/arkts-blur-effect.md

### 11.5 Architecture / rationale
- Guide: **Overview of Graphics Drawing and Display** (the Canvas-vs-Native-Drawing architecture statement) — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/graphics/graphic-drawing-overview.md
- Guide: **Obtaining a Canvas and Displaying Drawing Results (ArkTS)** — the `RenderNode` + `NodeController` + `NodeContainer` route (Bridge B1) and the offscreen-PixelMap route — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/graphics/canvas-get-result-draw-arkts.md
- Guide: Canvas Operation State (save/restore/layer semantics) — https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/graphics/canvas-operation-state-arkts.md

### 11.6 SDK sources used for `@since` verification
- HarmonyOS SDK (DevEco Studio 6.1.1.125, **API 24**) — local install:
  `/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/api/@ohos.graphics.drawing.d.ts`
  `/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/api/@ohos.graphics.displaySync.d.ts`
  `/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/component/canvas.d.ts`
- OpenHarmony SDK **API 23** — local install: `/Users/chenxianlong/Library/OpenHarmony/Sdk/23/ets/`
- Upstream equivalents: https://raw.githubusercontent.com/openharmony/interface_sdk-js/master/api/@ohos.graphics.drawing.d.ts · https://raw.githubusercontent.com/openharmony/interface_sdk-js/master/api/@ohos.graphics.uiEffect.d.ts · https://raw.githubusercontent.com/openharmony/interface_sdk-js/master/api/@ohos.effectKit.d.ts
- ⚠️ Branch-name corrections (from a delegated researcher): `OpenHarmony-5.1-Release` and `OpenHarmony-6.0.0-Release` **do not exist** — use `OpenHarmony-5.1.0-Release` and `OpenHarmony-6.0-Release`. And `master` has **no** `js-apis-graphics-drawing.md` (404) — it was split into `arkts-apis-graphics-drawing-*.md`.

### 11.7 Official samples- ArkTSGraphicsDraw (API 20) — https://gitcode.com/openharmony/applications_app_samples/tree/master/code/DocsSample/ArkGraphics2D/Drawing/ArkTSGraphicsDraw
- DisplaySync (API 14) — https://gitcode.com/openharmony/applications_app_samples/tree/master/code/DocsSample/ArkGraphics2D/DisplaySync
- CustomCanvas (Canvas best practices) — https://gitcode.com/openharmony/applications_app_samples/tree/master/code/DocsSample/ArkUISample/CustomCanvas
- Huawei best practices: "Using Custom Drawing to Improve Performance" (**JS-rendered, content unverified**) — https://developer.huawei.com/consumer/en/doc/best-practices-V5/bpta-drawing-capability-improve-performance-V5

---

## 12. One-paragraph answer

**Yes, a 60 fps additive neon light-trail is achievable in pure ArkTS with no C++.** Get a live `drawing.Canvas` (`@kit.ArkGraphics2D`) into the render pipeline — either via **Bridge B1**, a `RenderNode` subclass whose `draw(context: DrawContext)` hands you `context.canvas` (the route the official graphics overview points at for performance), or via **Bridge B2**, `new DrawingRenderingContext(LengthMetricsUnit.PX)` bound to `Canvas(this.ctx)` (API 12, far less boilerplate). Then use `BlendMode.PLUS` — *all 29 `BlendMode` members are `@since 11`, and there is no `ADD`; `PLUS` is the additive mode* — on every `Pen`, and `MaskFilter.createBlurMaskFilter(BlurType.OUTER, sigma)` on a `Pen` (`@since 12`, **SDK-verified**) for a true outer-glow halo; the official guide states mask-filter blur is *"less costly than that of the image filter."* Build the figure-eight with `Path.quadTo`/`cubicTo` (`@since 11`) and get the white→colour falloff with `ShaderEffect.createLinearGradient` on the pen (`@since 12`) — **all on a stroke**, which declarative `Shape`/`Path` cannot do because `stroke(value: ResourceColor)` is colour-only. Drive frames with `displaySync.create()` + `on('frame')` (**all `displaySync` members `@since 11`**) using `IntervalInfo.timestamp` (nanoseconds) for delta-time, doing `canvas.clear(...)` → draw → `invalidate()` inside one callback to avoid flicker, and `stop()` + null the `DisplaySync` in `aboutToDisappear` as the docs require. Remember `drawPath()` takes **only** a path — attach the pen first. Two SDK-verified negatives will save you time: **`requestAnimationFrame` does not exist in ArkTS**, and **`getDrawingCanvas` does not exist at all**. Remaining caveats: the Canvas command queue grows while the component is invisible (gate with `setOnVisibleAreaApproximateChange`, API 13), keep the canvas under 8000 px per side, and `requestAnimationFrame` alternatives aside, `PathEffect.createDiscretePathEffect` (electric flicker) is API 18 so it is unavailable at API 12. See §10 for what remains unverified.
