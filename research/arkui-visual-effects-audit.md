# HarmonyOS NEXT / OpenHarmony — Declarative ArkTS Graphics & Visual-Effect APIs (API 12 – API 24+)

**Scope**: `Shape`, `Path`, gradient attributes, `shadow()`, `blur()`, `foregroundBlurStyle()`, `backgroundBlurStyle()`, `visualEffect()`, `uiEffect`, `effectKit`, `blendMode()`.
**Sources**: OpenHarmony docs GitHub mirror (`raw.githubusercontent.com/openharmony/docs`), OpenHarmony SDK declarations (`openharmony/interface_sdk-js`). Every claim below carries its source URL.

> **Reading note on "Since API version N"**: the OpenHarmony docs use two conventions: a module-level note ("The initial APIs of this module are supported since API version 7") plus per-member superscripts (`blur<sup>18+</sup>`). Where a member has no superscript, its since-version equals the module-level version. I mark these as `API 7 (module-level)` etc.

---

## 1. `Shape` component

### 1.1 Declaration and constructor

```ts
// API 7+  (widget support since API 9, except PixelMap; atomic service since API 11)
Shape(value?: PixelMap)
```

| Item | Value | Since |
|---|---|---|
| `Shape(value?: PixelMap)` | `value` optional `PixelMap` — drawing target. `undefined`/`null` treated as invalid, no effect | **API 7** (module), widget **9**, atomic service **11** |
| `Shape()` (no arg) | draws into the current drawing target | **API 7** |
| Dynamic constructor update via `AttributeUpdater.updateConstructorParams` | — | **API 20** |
| Child components | `Rect`, `Path`, `Circle`, `Ellipse`, `Polyline`, `Polygon`, `Image`, `Text`, `Column`, `Row`, `Shape` | API 7 |

The SDK declaration confirms the attribute class inherits the **entire** universal-attribute surface:

```ts
declare class ShapeAttribute extends CommonMethod<ShapeAttribute> { /* ... */ }
```

Sources: [ts-drawing-components-shape.md (en)](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-drawing-components-shape.md) · [zh-cn](https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-drawing-components-shape.md) · [shape.d.ts (SDK)](https://raw.githubusercontent.com/openharmony/interface_sdk-js/master/api/@internal/component/ets/shape.d.ts)

### 1.2 Stroke / fill attributes — exact signatures, defaults, since-versions

All of these are declared **without superscript** in the docs, i.e. effective **since API 7** (module-level note: *"This component is supported since API version 7."*). Defaults are verbatim from the docs' description column.

```ts
viewPort(value: ViewportRect): ShapeAttribute          // API 7
fill(value: ResourceColor): ShapeAttribute             // API 7
fillOpacity(value: number | string | Resource): ShapeAttribute   // API 7
stroke(value: ResourceColor): ShapeAttribute           // API 7
strokeDashArray(value: Array<any>): ShapeAttribute     // API 7
strokeDashOffset(value: Length): ShapeAttribute        // API 7  (type widened to Length in API 20)
strokeLineCap(value: LineCapStyle): ShapeAttribute     // API 7
strokeLineJoin(value: LineJoinStyle): ShapeAttribute   // API 7
strokeMiterLimit(value: Length): ShapeAttribute        // API 7
strokeOpacity(value: number | string | Resource): ShapeAttribute // API 7
strokeWidth(value: Length): ShapeAttribute             // API 7
antiAlias(value: boolean): ShapeAttribute              // API 7
mesh(value: Array<any>, column: number, row: number): ShapeAttribute  // API 8
```

| Attribute | Default | Notes (verbatim / paraphrased from docs) |
|---|---|---|
| `viewPort` | `{}` → x/y/width/height each `0`, unit **vp** | `ViewportRect` interface formalised in **API 18**; its members `x/y/width/height` are each `7+`; the member type changed from `number \| string` to `Length` in **API 20** |
| `fill` | `Color.Black` | "Sets the color of the fill area." If both `fill` and universal `foregroundColor` are set, **whichever is set later wins** |
| `fillOpacity` | `1.0` | number range `[0.0, 1.0]`, clamped |
| `stroke` | `Color.Transparent` | **"If this attribute is not set, the default stroke opacity is 0, meaning no stroke is displayed."** |
| `strokeDashArray` | `[]` (solid line) | unit **vp**; odd-length arrays are duplicated to even length |
| `strokeDashOffset` | `0`, unit **vp** | "If set to `NaN` or `Infinity`, `strokeDashArray` has no effect." |
| `strokeLineCap` | `LineCapStyle.Butt` | |
| `strokeLineJoin` | `LineJoinStyle.Miter` | |
| `strokeMiterLimit` | `4` | only effective when `strokeLineJoin == LineJoinStyle.Miter`; `[0,1)` → `1.0`; `Infinity` → `stroke` has no effect |
| `strokeOpacity` | opacity set by `stroke` | `NaN` → `0.0`; `undefined`/`null`/`Infinity` → `1.0` |
| `strokeWidth` | `1`, unit **vp** | string type: percentages are **not** supported and are treated as **1 px** |
| `antiAlias` | `true` | `undefined`/`null` are treated as **`false`** (i.e. setting it to an invalid value turns AA *off*) |
| `mesh` | — | **"`mesh` takes effect only when a `pixelMap` object is passed to the shape"**; docs **recommend `drawing.Canvas.drawPixelMapMesh` (API 12)** instead |

Source: [ts-drawing-components-shape.md](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-drawing-components-shape.md)

### 1.3 Gradients on `Shape` — and **does the gradient hit the stroke or the fill?**

**Yes, `Shape` supports all three gradient attributes** — because they are *universal* attributes (`CommonMethod<T>`) and `ShapeAttribute extends CommonMethod<ShapeAttribute>`. There is no `Shape`-specific gradient API.

```ts
// API 7+ ; Optional<> overloads added in API 18
linearGradient(value: LinearGradientOptions): T
sweepGradient(value: SweepGradientOptions): T
radialGradient(value: RadialGradientOptions): T
```

**Exact option interfaces** (member since-versions in parentheses; interfaces renamed/formalised in API 18 but members kept their original `7+` tags):

```ts
interface LinearGradientOptions {          // API 18 (members 7+)
  angle?: number | string;                 // 7+  default 180  (0° = bottom→top, positive = clockwise)
  direction?: GradientDirection;           // 7+  default GradientDirection.Bottom; ignored if angle is set
  colors: Array<[ResourceColor, number]>;  // 7+  REQUIRED. default [] = no gradient
  repeating?: boolean;                     // 7+  default false
}

interface SweepGradientOptions {           // API 18 (members 7+)
  center: [Length, Length];                // 7+  REQUIRED (relative to component top-left)
  start?: number | string;                 // 7+  default 0, clamped to 0–360
  end?: number | string;                   // 7+  default 0, clamped to 0–360
  rotation?: number | string;              // 7+  default 0, clamped to 0–360
  colors: Array<[ResourceColor, number]>;  // 7+  default [] = no gradient
  metricsColors?: Array<[ColorMetrics, number]>; // 20+ overrides `colors`
  repeating?: boolean;                     // 7+  default false
}

interface RadialGradientOptions {          // API 18 (members 7+)
  center: [Length, Length];                // 7+  REQUIRED
  radius: Length;                          // 7+  REQUIRED, >= 0; undefined ⇒ system picks radius
  colors: Array<[ResourceColor, number]>;  // 7+  default [] = no gradient
  repeating?: boolean;                     // 7+  default false
}
```

**There is no `stops` parameter.** The colour stop position is the **second element of each `colors` tuple**:

```ts
colors: [[0xff0000, 0.0], [0x0000ff, 0.3], [0xffff00, 1.0]]
//        ^color       ^stop 0.0 … 1.0
```

Documented constraints on `colors`: range `[0, 1.0]`, values `< 0` → `0`, `> 1.0` → `1.0`; stop values should be **strictly ascending** — "If a later number is less than a previous one, it is treated as equal to the previous value." Invalid colours are silently skipped. Since **API 18**, each of the three attributes also has an `Optional<...>` overload that disables the gradient when passed `undefined`.

Also documented:

> "Color gradients are considered part of the component's content and are drawn above the background."
> "Color gradients do not support explicit width and height animations. When the width or height of a component is animated with a color gradient, the gradient will jump straight to the final size."

Source: [ts-universal-attributes-gradient-color.md (en)](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-gradient-color.md) · [zh-cn](https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-gradient-color.md)

#### STROKE vs FILL — the critical point

**What I could verify from authoritative sources:**

1. **There is no gradient-carrying stroke API.** The complete documented attribute set of `Shape` (and `Path`) contains `stroke(value: ResourceColor)` — a *colour only*. No gradient/`Shader`/`Brush` type appears anywhere in the stroke family. The same is true in the SDK declaration `shape.d.ts`: `stroke(value: ResourceColor): ShapeAttribute`.
2. **The three gradient attributes take no target parameter** (no `fill`/`stroke` selector). They set one gradient for the component's content. Doc language: gradients belong to "the component's content" (`颜色渐变属于组件内容，绘制在背景上方`).
3. **ArkUI engine source** (`ShapePaintProperty`, the paint property actually consumed by the shape renderer) declares the two paints as plain `Color` — there is no gradient-bearing fill or stroke slot:
   ```cpp
   ACE_DEFINE_PROPERTY_ITEM_WITHOUT_GROUP(Fill, Color, PROPERTY_UPDATE_RENDER);
   ACE_DEFINE_PROPERTY_ITEM_WITHOUT_GROUP(Stroke, Color, PROPERTY_UPDATE_RENDER);
   ```
   Source: [shape_paint_property.h (arkui_ace_engine)](https://raw.githubusercontent.com/openharmony/arkui_ace_engine/master/frameworks/core/components_ng/pattern/shape/shape_paint_property.h)

**Conclusion (high confidence): a declarative `linearGradient` / `radialGradient` / `sweepGradient` on a `Shape`/`Path` can only colour the *filled region*. There is no declarative way to give a `Shape`/`Path` *stroke* a gradient.** For an open path with `fill` transparent, the gradient is effectively invisible.

**Verified workarounds for a gradient stroke** (both since **API 12**):

*Canvas 2D* — `strokeStyle` accepts a `CanvasGradient` produced by `createLinearGradient` / `createRadialGradient`, i.e. Canvas does support gradient strokes (declarative `Shape` does not).

*ArkGraphics 2D `drawing` module* — a `Pen` (stroke paint) accepts a shader:

```ts
import { drawing } from '@kit.ArkGraphics2D';

const pen = new drawing.Pen();
let shaderEffect = drawing.ShaderEffect.createLinearGradient(
  { x: 100, y: 100 }, { x: 300, y: 300 },
  [0xFF00FF00, 0xFFFF0000], drawing.TileMode.REPEAT);
pen.setShaderEffect(shaderEffect);   // drawing.Pen.setShaderEffect — API 12
```

Source: [arkts-apis-graphics-drawing-Pen.md](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-Pen.md)

> See the **UNVERIFIED** section: I found no official *prose sentence* that says "the gradient does not apply to the stroke". The conclusion above is an inference from the complete API surface plus engine source, not a quoted doc statement.

---

## 2. `Path` component

### 2.1 Declaration

```ts
// API 7+ ; widget since API 9 ; atomic service since API 11
Path(options?: PathOptions)

interface PathOptions {           // API 18 (members 7+)
  width?: Length;                 // 7+  default: width required by content
  height?: Length;                // 7+  default: height required by content
  commands?: ResourceStr;         // 7+  default: empty string
}
```

```ts
commands(value: ResourceStr): PathAttribute   // API 7
```

**Unit gotcha (documented):** `commands` uses the unit **px**, *not* vp: *"The unit is px. For details about how to convert pixel units, see Pixel Units."* `PathOptions.width/height` default to **vp**. This is the single most common source of mis-scaled paths.

`Path` also inherits `CommonMethod<PathAttribute>` and therefore **all** universal attributes (gradients, `shadow`, `blur`, `blendMode`, …). Its own attribute set is the same stroke/fill family as `Shape` (`fill`, `fillOpacity`, `stroke`, `strokeDashArray` (`Array<any>`, default `[]`), `strokeDashOffset` (`number | string` on `Path` — no `Resource`), `strokeLineCap` (default `Butt`), `strokeLineJoin` (default `Miter`), `strokeMiterLimit` (default `4`), `strokeOpacity` (default `1`), `strokeWidth` (default `1` vp), `antiAlias` (default `true`)).

Source: [ts-drawing-components-path.md (en)](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-drawing-components-path.md)

### 2.2 Supported SVG path command letters

The docs state: *"The table below lists the supported SVG path commands."*

| Command | Name | Parameters |
|---|---|---|
| `M` | moveto | x, y |
| `L` | lineto | x, y |
| `H` | horizontal lineto | x |
| `V` | vertical lineto | y |
| `C` | curveto (cubic Bézier) | x1 y1 x2 y2 x y |
| `S` | smooth curveto | x2 y2 x y |
| `Q` | quadratic Bézier | x1 y1 x y |
| `T` | smooth quadratic Bézier | x y |
| `A` | elliptical arc | rx ry x-axis-rotation large-arc-flag sweep-flag x y |
| `Z` | closepath | none |

**All ten letters you asked about (M, L, C, Q, A, Z, H, V, S, T) are supported.** Only the **uppercase (absolute)** forms appear in the documented table — see UNVERIFIED for lowercase/relative forms.

### 2.3 Compilable example (from the official docs)

```ts
// xxx.ets
@Entry
@Component
struct PathExample {
  build() {
    Column({ space: 10 }) {
      // Straight line, 600 px long, 3 vp wide
      Path()
        .width('600px')
        .height('10px')
        .commands('M0 0 L600 0')
        .stroke(Color.Black)
        .strokeWidth(3)

      Flex({ justifyContent: FlexAlign.SpaceBetween }) {
        Path().width('210px').height('310px')
          .commands('M100 0 L200 240 L0 240 Z')      // triangle
          .fillOpacity(0).stroke(Color.Black).strokeWidth(3)
        Path().width('210px').height('310px')
          .commands('M0 0 H200 V200 H0 Z')           // H + V
          .fillOpacity(0).stroke(Color.Black).strokeWidth(3)
      }.width('95%')

      Flex({ justifyContent: FlexAlign.SpaceBetween }) {
        Path().width('250px').height('310px')
          .commands("M0 300 S100 0 240 300 Z")       // S
          .fillOpacity(0).stroke(Color.Black).strokeWidth(3)
        Path().width('210px').height('310px')
          .commands('M0 150 C0 100 140 0 200 150 L100 300 Z')  // C
          .fillOpacity(0).stroke(Color.Black).strokeWidth(3)
        Path().width('210px').height('310px')
          .commands('M0 100 A30 20 20 0 0 200 100 Z')          // A
          .fillOpacity(0).stroke(Color.Black).strokeWidth(3)
      }.width('95%')
    }.width('100%').margin({ top: 5 })
  }
}
```

`Path({ width, height })` accepts `number | string | Resource`; `commands` accepts `ResourceStr` (including `$r('app.string.…')`).

---

## 3. `shadow()` universal attribute

### 3.1 Overloads and since-versions

```ts
// API 7 (module-level: "The feature is supported since API version 7")
shadow(value: ShadowOptions | ShadowStyle): T

// API 18 — adds Optional<>; undefined ⇒ no shadow
shadow(options: Optional<ShadowOptions | ShadowStyle>): T
```

`ShadowStyle` itself is **API 10+**. In ArkTS widgets: supported since API 9, **but `ShadowStyle` is not supported in widgets**.

### 3.2 `ShadowOptions` (exact fields and since-versions)

```ts
interface ShadowOptions {
  radius: number | Resource;                 // REQUIRED. blur radius, unit px, >= 0
  type?: ShadowType;                         // API 10+   default ShadowType.COLOR
  color?: Color | string | Resource | ColoringStrategy;  // default black; ColoringStrategy since API 11
  offsetX?: number | Resource;               // default 0, unit px
  offsetY?: number | Resource;               // default 0, unit px
  fill?: boolean;                            // API 11+   default false
}

enum ShadowType { COLOR = 0, BLUR = 1 }      // ShadowType since API 10
```

**Correction to your assumption:** `ShadowOptions.type` is **since API 10** (not 11/12). `ShadowOptions.fill` is **since API 11** (correct in your guess). Documented for `fill`: *"Whether to fill the inside of the component with shadow. `true`: Fill the inside of the component with shadow. `false`: Do not fill… Default value: `false`. NOTE: This attribute does not take effect in `textShadow`."* `color` also accepts `ColoringStrategy` (the strings `'average'` / `'primary'`) since **API 11** — *not* usable in ArkTS widgets or `textShadow`.

`radius`/`offsetX`/`offsetY` are in **px**; to use vp, the docs point at `UIContext.vp2px` (API 12). If of `Resource` type, the resource value must be a number.

```ts
enum ShadowStyle {          // API 10+
  OUTER_DEFAULT_XS = 0, OUTER_DEFAULT_SM = 1, OUTER_DEFAULT_MD = 2,
  OUTER_DEFAULT_LG = 3, OUTER_FLOATING_SM = 4, OUTER_FLOATING_MD = 5
}
```

### 3.3 Does `shadow()` glow a `Shape`/`Path` **stroke**?

**What the docs establish:**
* `shadow()` is a *universal* attribute, so it is *available* on `Shape`/`Path` (both `ShapeAttribute` and `PathAttribute` extend `CommonMethod<T>`).
* `fill: true` (API 11+) is documented as "fill the inside of the component with shadow" — i.e. the shadow is derived from the component's **rendered silhouette**, not from a background box.
* **No official document states whether the generated shadow follows a stroked path's geometry.**

**Honest answer: NOT VERIFIED.** I found no official Huawei/OpenHarmony sentence that says "`shadow()` on a `Shape` renders from the stroke outline" *or* the opposite. Treat the `Shape().stroke(...).shadow({radius, offsetX:0, offsetY:0})` glow trick as **empirically-to-be-tested on device**, not as documented behaviour.

If you need a *documented* glow on a stroked curve, prefer the ArkGraphics 2D `drawing` module, where the effect is explicitly a pen filter (both **API 12**):

```ts
import { drawing } from '@kit.ArkGraphics2D';

// (a) verifiable outer glow on a stroke
let maskFilter = drawing.MaskFilter.createBlurMaskFilter(drawing.BlurType.OUTER, 10);
pen.setMaskFilter(maskFilter);        // drawing.Pen.setMaskFilter — API 12

// (b) verifiable blur/glow via image filter chain
let imgFilter = drawing.ImageFilter.createBlurImageFilter(5, 10, drawing.TileMode.CLAMP);
pen.setImageFilter(imgFilter);        // drawing.Pen.setImageFilter — API 12
```

The official `setMaskFilter` example is literally a red glowing pen: `pen.setColor({alpha:255, red:255, green:0, blue:0}); pen.setMaskFilter(drawing.MaskFilter.createBlurMaskFilter(drawing.BlurType.OUTER, 10));`
Sources: [Pen](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-Pen.md) · [ImageFilter](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-ImageFilter.md)

### 3.4 Does `shadow()` need a background?

Not documented. `fill: true` implies the shadow is computed from the component's own drawn content (that is the documented purpose of `fill`). Nothing in the docs restricts `shadow()` to components with a background. **No official statement** either way — see UNVERIFIED.

### 3.5 Documented performance caveats

* **No documented performance/offscreen statement specific to `shadow()`.** I searched the whole `ts-universal-attributes-image-effect.md` (en + zh-cn) and `ts-universal-attributes-background.md`; there is no "shadow forces offscreen rendering" sentence.
* The **documented** offscreen-rendering mechanisms nearby are:
  * `blendMode(..., BlendApplyType.OFFSCREEN)` — "creates an offscreen canvas of the size of the current component… may cause issues with screen capture for APIs such as `linearGradientBlur`, `backgroundEffect`, `brightness`, and `blur`."
  * `renderGroup(true)` (API 10+) — subtree is "first rendered on an offscreen canvas and then composited with the parent component… the system caches the rendering result, improving performance. However, if components within the render group are frequently updated, cache invalidation may lead to performance degradation."
  * `sphericalEffect` (API 12) — "the component is frozen, and its content is drawn to the transparent offscreen buffer."
* Related, useful for many-shadow scenes: `useShadowBatching(value: boolean): T` — **API 11+** (Optional overload API 18): "Sets whether to render child node shadows at the same layer, enabling shadow overlap within the same layer."
* The only official example that uses `shadow({ radius: >0, offsetX: 0, offsetY: 0 })` is the `useShadowBatching` demo (Example 6 of the image-effect doc). It is a *shadow* demo — **`shadow()` is never documented as an outer-glow mechanism.** Using it that way is a community technique, not a documented feature.
* `renderGroup(true)` (API 10+) is the attribute that *does* force offscreen render + cache, and it has a documented **negative** case when children animate every frame (frame-drop 77% → 100%, `FlushFrame` 3 ms → 15 ms): `zh-cn/application-dev/performance/reasonable-using-renderGroup.md`. Relevant when composing multi-layer glow subtrees per frame.

---

## 4. `blur()` universal attribute

```ts
// module-level since API 7
blur(value: number, options?: BlurOptions): T               // options since API 11
blur(blurRadius: Optional<number>, options?: BlurOptions): T // API 18
blur(blurRadius: Optional<number>, options?: BlurOptions,
     sysOptions?: SystemAdaptiveOptions): T                  // API 19
```

| Parameter | Type | Since | Meaning |
|---|---|---|---|
| `value` / `blurRadius` | `number` (opt. `Optional<number>`) | 7 (opt. 18) | blur radius; larger = blurrier; `0` = no blur. `undefined` (18+) = keep previous value |
| `options` | `BlurOptions` | **11** | grayscale parameters |
| `sysOptions` | `SystemAdaptiveOptions` | **19** | default `{ disableSystemAdaptation: false }` |

```ts
interface BlurOptions {          // API 11+
  grayscale: [number, number];   // REQUIRED. each in [0, 127]
}
```

Documented semantics of `grayscale`: *"The first parameter indicates the brightness of the black color, and the second parameter indicates the darkness of the white color."* Example given: `(20,20)` maps RGB `[0,0,0]` → `[20,20,20]` and `[255,255,255]` → `[235,235,235]`; colour pixels are unchanged. Default `grayscale: [0, 0]`.

**What it blurs:** *"Applies a foreground blur effect to the component"* / zh-cn: *"为组件添加内容模糊效果"* — i.e. it blurs **the component's own rendered content (including any children)**. Nothing in the docs excludes drawing components. Therefore, on a `Shape`/`Path`, `blur()` blurs the rendered fill+stroke. **There is no Shape/Path-specific caveat documented.**

**Performance caveat (documented, verbatim):**

> "**backgroundBlurStyle**, **blur**, and **backdropBlur** perform real-time rendering per frame, resulting in high performance overhead. When both the blur content and blur radius remain unchanged, it is recommended that you use the static blur API [blur](…/js-apis-effectKit.md#blur). For best practices, see [Image Blurring Optimization – When to Use](https://developer.huawei.com/consumer/en/doc/best-practices/bpta-fuzzy-scene-performance-optimization#section4945532519)."

So `blur()` is explicitly named as a per-frame, high-overhead API. For a static glow, bake it (effectKit) instead.

Reinforced in the dedicated guide: [ui/arkts-blur-effect.md](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/ui/arkts-blur-effect.md) — *"The preceding APIs are real-time blurring APIs that perform rendering on a frame-by-frame basis, which incurs significant performance overhead. When both the blur content and blur radius remain unchanged, it is recommended that you use the static blur API `blur`."* (applies to `backdropBlur`, `blur`, `backgroundBlurStyle`, `foregroundBlurStyle`, `motionBlur`). Measured best-practice data: dynamic blur ≈ 6.113 ms / 108 fps vs static blur ≈ 3.357 ms / 119.9 fps (≈45% less render time) — `zh-cn/application-dev/performance/fuzzy_scene_performance_optimization.md`.

Sources: [ts-universal-attributes-image-effect.md](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-image-effect.md) · [ts-universal-attributes-background.md](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-background.md) · [zh-cn image-effect](https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-image-effect.md)

---

## 5. `foregroundBlurStyle()` and `backgroundBlurStyle()`

```ts
// module-level since API 10
foregroundBlurStyle(value: BlurStyle, options?: ForegroundBlurStyleOptions): T
foregroundBlurStyle(style: Optional<BlurStyle>, options?: ForegroundBlurStyleOptions): T            // API 18
foregroundBlurStyle(style: Optional<BlurStyle>, options?: ForegroundBlurStyleOptions,
                    sysOptions?: SystemAdaptiveOptions): T                                          // API 19

// since API 9  (marked backgroundBlurStyle<sup>9+</sup>)
backgroundBlurStyle(value: BlurStyle, options?: BackgroundBlurStyleOptions): T
backgroundBlurStyle(style: Optional<BlurStyle>, options?: BackgroundBlurStyleOptions): T            // API 18
backgroundBlurStyle(style: Optional<BlurStyle>, options?: BackgroundBlurStyleOptions,
                    sysOptions?: SystemAdaptiveOptions): T                                          // API 19
```

### `BlurStyle` enum (module: `ts-universal-attributes-background.md`)

| Value | Since | | Value | Since |
|---|---|---|---|---|
| `Thin` | 9 | | `COMPONENT_ULTRA_THIN` = 8 | **11** |
| `Regular` | 9 | | `COMPONENT_THIN` = 9 | **11** |
| `Thick` | 9 | | `COMPONENT_REGULAR` = 10 | **11** |
| `BACKGROUND_THIN` = 3 | **10** | | `COMPONENT_THICK` = 11 | **11** |
| `BACKGROUND_REGULAR` = 4 | **10** | | `COMPONENT_ULTRA_THICK` = 12 | **11** |
| `BACKGROUND_THICK` = 5 | **10** | | `NONE` = 7 | **10** |
| `BACKGROUND_ULTRA_THICK` = 6 | **10** | | | |

### Option interfaces

```ts
interface BlurStyleOptions {                       // base class
  colorMode?: ThemeColorMode;                      // default ThemeColorMode.SYSTEM
  adaptiveColor?: AdaptiveColor;                   // default AdaptiveColor.DEFAULT
  blurOptions?: BlurOptions;                       // API 11+   default { grayscale: [0,0] }
  scale?: number;                                  // API 12+   default 1.0, range [0.0, 1.0]
}                                                  //           1.0 = highest blur, 0.0 = lowest

interface ForegroundBlurStyleOptions extends BlurStyleOptions {}   // no extra fields

interface BackgroundBlurStyleOptions extends BlurStyleOptions {    // API 10+
  policy?: BlurStyleActivePolicy;                  // API 14+   default ALWAYS_ACTIVE
  inactiveColor?: ResourceColor;                   // API 14+   used with policy
}

enum ThemeColorMode { SYSTEM = 0, LIGHT = 1, DARK = 2 }
enum AdaptiveColor { DEFAULT = 0, AVERAGE = 1 }    // AVERAGE = use average colour of the pick area as mask
enum BlurStyleActivePolicy {                        // API 14+
  FOLLOWS_WINDOW_ACTIVE_STATE = 0, ALWAYS_ACTIVE = 1, ALWAYS_INACTIVE = 2
}
```

Notes: `backgroundBlurStyle`'s `options` parameter **cannot be used in ArkTS widgets**. `AdaptiveColor.AVERAGE` "can be more time-consuming". Do not combine `inactiveColor` with a separate `backgroundColor`.

### Do they work on arbitrary components, including `Shape`?

Both are **universal attributes** (`CommonMethod<T>`), so they are *available* on any component including `Shape`/`Path`. **But their semantics require content behind the component:**

* `backgroundBlurStyle` = a *background material* — it blurs **what is behind the component inside its bounds**. The official example places the blurred `Row` on top of a `Column` with `backgroundImage(...)`. With nothing behind it, there is nothing to blur.
* `foregroundBlurStyle` = a *foreground material* applied to the component's own content. The official example blurs an `Image`'s own content (`Image($r('app.media.bg')).foregroundBlurStyle(BlurStyle.Thin, {…})`, captioned "apply content blur to an image using **foregroundBlurStyle**").

**Not verified:** no doc sentence confirms/denies that `foregroundBlurStyle` on a `Shape` produces a glow around a stroke. Since it is a *material* (blur + mask colour + saturation/brightness), it blurs rather than adds light — it is the wrong tool for an additive glow.

`foregroundBlurStyle` also carries an explicit performance warning (API 19 section):

> "**foregroundBlurStyle** is a real-time blurring API that performs rendering frame by frame, which incurs significant performance overhead. When both the blur content and blur radius remain unchanged, it is recommended that you use the static blur API [blur](…/js-apis-effectKit.md#blur)."

Sources: [ts-universal-attributes-foreground-blur-style.md](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-foreground-blur-style.md) · [ts-universal-attributes-background.md](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-background.md)

---

## 6. `visualEffect()`, `VisualEffect`, and the `Filter` class

### 6.1 The four visual-effect attributes (module since **API 12**)

```ts
// ts-universal-attributes-filter-effect.md — "The initial APIs of this module are supported since API version 12."
visualEffect(effect: VisualEffect): T          // API 12
backgroundFilter(filter: Filter): T            // API 12
foregroundFilter(filter: Filter): T            // API 12
compositingFilter(filter: Filter): T           // API 12

type Filter = Filter;              // = uiEffect.Filter        (apis-arkgraphics2d/js-apis-uiEffect.md#filter)
type VisualEffect = VisualEffect;  // = uiEffect.VisualEffect  (apis-arkgraphics2d/js-apis-uiEffect.md#visualeffect)
```

All four can be called inside `attributeModifier` since API 20. Module: `SystemCapability.ArkUI.ArkUI.Full`; atomic service API since API 12.

Module import for the underlying classes:

```ts
import { uiEffect } from '@kit.ArkGraphics2D';
```

### 6.2 `VisualEffect` — what actually exists (**important correction**)

Your list (`backgroundColorBlur`, `backgroundBlur`, `foregroundColorBlur`, `foregroundBlur`, `borderRadius`) **does not match the official SDK**. I verified against both the current `master` and the API-12-era `OpenHarmony-5.0.0-Release` tag of `@ohos.graphics.uiEffect.d.ts`.

**API 12 (`OpenHarmony-5.0.0-Release`) — the entire `VisualEffect` interface:**

```ts
interface VisualEffect {
  backgroundColorBlender(blender: BrightnessBlender): VisualEffect;   // @since 12, @systemapi
}
```

**Current `master` — the entire `VisualEffect` interface:**

```ts
interface VisualEffect {
  backgroundColorBlender(blender: BrightnessBlender): VisualEffect;                       // 12, @systemapi
  borderLight(lightPosition: common2D.Point3d, lightColor: common2D.Color,
              lightIntensity: double, borderWidth: double): VisualEffect;                 // 20, @systemapi
  colorGradient(colors: Array<Color>, positions: Array<common2D.Point>,
                strengths: Array<double>, alphaMask?: Mask): VisualEffect;                // 20, @systemapi
  liquidMaterial(param: LiquidMaterialEffectParam, useEffectMask: Mask,
                 distortMask?: Mask, brightnessParam?: BrightnessParam): VisualEffect;    // 22, @systemapi
  distortionCollapse(distortionParam: DistortionParam): VisualEffect;                     // 26.0.0, @systemapi
}
```

**Every `VisualEffect` method is `@systemapi`** (plus `@systemapi` on `createBrightnessBlender`). For a normal third-party HarmonyOS app, `visualEffect()` therefore has **no usable `VisualEffect` payload** — you cannot call any of these. (`uiEffect.createEffect()` itself is public since API 12 and form-supported since API 24, but its result exposes only system APIs.)

Sources: [master `@ohos.graphics.uiEffect.d.ts`](https://raw.githubusercontent.com/openharmony/interface_sdk-js/master/api/@ohos.graphics.uiEffect.d.ts) · [API-12 tag `@ohos.graphics.uiEffect.d.ts`](https://raw.githubusercontent.com/openharmony/interface_sdk-js/OpenHarmony-5.0.0-Release/api/@ohos.graphics.uiEffect.d.ts) · [ts-universal-attributes-filter-effect.md](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-filter-effect.md)

### 6.3 `uiEffect.Filter` — public methods

```ts
import { uiEffect } from '@kit.ArkGraphics2D';

let filter: uiEffect.Filter = uiEffect.createFilter();   // API 12
filter.blur(10);                                         // API 12, PUBLIC
```

| Method | Signature | Since | Access |
|---|---|---|---|
| `blur` | `blur(blurRadius: double): Filter` | 12 | **public** (`SystemCapability.Graphics.Drawing`) |
| `pixelStretch` | `pixelStretch(stretchSizes: Array<double>, tileMode: TileMode): Filter` | 12 | systemapi |
| `waterRipple` | `waterRipple(progress, waveCount, x, y, rippleMode): Filter` | 12 | systemapi |
| `flyInFlyOutEffect` | `flyInFlyOutEffect(degree: double, flyMode: FlyMode): Filter` | 12 | systemapi |
| `distort` | `distort(distortionK: double): Filter` | 13 | systemapi |
| `radiusGradientBlur` | `radiusGradientBlur(radius, gradientParam: LinearGradientBlurOptions): Filter` | 19 | systemapi |
| `bezierWarp` / `contentLight` / `colorGradient` / `edgeLight` / `displacementDistort` / `maskDispersion` / `variableRadiusBlur` / `directionLight` / `maskTransition` | (various) | 20 | systemapi |
| `hdrBrightnessRatio(ratio: double): Filter` | | 20 (`@systemapi`) → **24 (`@publicapi`, permission `ohos.permission.HDR_BRIGHTNESS`)** | public from 24 |
| `heatDistortion` / `blurBubblesRise` / `haloBloom` / `spinBlur` | `haloBloom(tintColor: Color, bloomFactor: double, glowExposure: double): Filter` | 26.0.0 | systemapi |

Note `haloBloom(...)` — a literal **bloom/glow** filter — exists, but is `@systemapi` (API 26.0.0).

**Answer to "can `VisualEffect` create a coloured outer glow?"** For third-party apps, **no** — the only glow-capable members (`borderLight`, `colorGradient`, `liquidMaterial`, and `Filter.haloBloom`) are system APIs. See §3.3 for the public alternatives.

### 6.4 `filter.createBlur` / `createDisplacementMap` / `combine` / `createShader` — do not exist

* **There is no `filter` namespace exported from `@kit.ArkUI`.** I enumerated the full export list of `@kit.ArkUI.d.ts`: it exports `BackgroundBlur`, `ContentBlur`, `ForegroundBlur` (node-level blurs from `@ohos.arkui.node`) and a `Filter` — but that `Filter` is `@ohos.arkui.advanced.Filter` (`Filter`, `FilterParams`, `FilterResult`, `FilterType`), a **search/filter UI component**, not a graphics filter.
* **There are no `createBlur` / `createDisplacementMap` / `combine` / `createShader` functions** in `@ohos.graphics.uiEffect` (neither API 12 nor master). `uiEffect.createFilter()` is the only factory.
* The real, similarly-named APIs live in the **`drawing`** module (`import { drawing } from '@kit.ArkGraphics2D'`):

```ts
// Class ImageFilter — initial APIs of this class since API 12
static createBlurImageFilter(sigmaX: number, sigmaY: number, tileMode: TileMode,
                             imageFilter?: ImageFilter | null): ImageFilter      // API 12
static createFromColorFilter(colorFilter: ColorFilter,
                             imageFilter?: ImageFilter | null): ImageFilter      // API 12
static createFromImage(pixelmap, srcRect?, dstRect?): ImageFilter                 // API 20
static createBlendImageFilter(mode: BlendMode, background: ImageFilter,
                              foreground: ImageFilter): ImageFilter               // API 20
static createComposeImageFilter(cOuter: ImageFilter, cInner: ImageFilter): ImageFilter  // API 20  ← the "combine"
static createOffsetImageFilter(dx: number, dy: number, input?: ImageFilter | null): ImageFilter // API 20
static createFromShaderEffect(shader: ShaderEffect): ImageFilter                  // API 20  ← the "createShader"
```

There is **no `createDisplacementMap`** in `ImageFilter`. Displacement-map style effects exist only as `uiEffect` system APIs (`Filter.displacementDistort`, `Filter.maskDispersion`, `Mask.createPixelMapMask`, all API 20 `@systemapi`).

Sources: [@kit.ArkUI.d.ts](https://raw.githubusercontent.com/openharmony/interface_sdk-js/master/kits/@kit.ArkUI.d.ts) · [arkts-apis-graphics-drawing-ImageFilter.md](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/arkts-apis-graphics-drawing-ImageFilter.md) · [js-apis-uiEffect.md](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/js-apis-uiEffect.md)

### 6.5 Can `Filter` be used with background/foreground blur?

Yes — but through the **`*Filter`** attributes, not a `*Blur` attribute. There is no `backgroundBlur(filter)` / `foregroundBlur(filter)`. The pairing is:

```ts
backgroundFilter(filter)   // blurs/distors what is BEHIND the component
foregroundFilter(filter)   // filters the component's own content
compositingFilter(filter)  // filters the composite
```

Official example (verbatim structure):

```ts
import { uiEffect } from '@kit.ArkGraphics2D';

@Entry
@Component
struct FilterEffectExample {
  @State filterTest1: uiEffect.Filter = uiEffect.createFilter().blur(10);
  @State filterTest2: uiEffect.Filter = uiEffect.createFilter().blur(10);
  @State filterTest3: uiEffect.Filter = uiEffect.createFilter().blur(10);

  build() {
    Column({ space: 15 }) {
      Text('Foreground filter')
        .width(100).height(100)
        .backgroundColor('#ADD8E6')
        .backgroundImage($r("app.media.app_icon"))
        .backgroundImageSize({ width: 80, height: 80 })
        .foregroundFilter(this.filterTest1)

      Text('Background filter')
        .width(100).height(100)
        .backgroundColor('#ADD8E6')
        .backgroundImage($r("app.media.app_icon"))
        .backgroundImageSize({ width: 80, height: 80 })
        .backgroundFilter(this.filterTest2)

      Text('Compositing filter')
        .width(100).height(100)
        .backgroundColor('#ADD8E6')
        .backgroundImage($r("app.media.app_icon"))
        .backgroundImageSize({ width: 80, height: 80 })
        .compositingFilter(this.filterTest3)
    }.height('100%').width('100%')
  }
}
```

Source: [ts-universal-attributes-filter-effect.md](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-filter-effect.md)

---

## 7. `@ohos.effectKit` / `@kit.ArkGraphics2D`

### 7.1 Import and module boundary

```ts
import { effectKit } from "@kit.ArkGraphics2D";
```

The module doc draws the boundary **explicitly**:

> "The **effectKit** module processes images (such as PixelMap, PNG, and JPEG) **offline** to obtain visual effects. The **uiEffect** module connects to the rendering service in real time and process the screen frame buffer to obtain dynamic visual effects."

The SDK `.d.ts` repeats it:

> "This module is used for offline processing of `image.PixelMap` to obtain visual effects, while uiEffect (UI Effect Service) connects to the rendering service in real time to process screen frame buffers for dynamic visual effects."

### 7.2 Public API surface

```ts
createEffect(source: image.PixelMap): Filter                              // API 9
createColorPicker(source: image.PixelMap): Promise<ColorPicker>          // API 9
createColorPicker(source: image.PixelMap, region: Array<number>): Promise<ColorPicker>  // API 10
createColorPicker(source, callback: AsyncCallback<ColorPicker>): void    // API 9
createColorPicker(source, region, callback): void                        // API 10
```

`Filter` methods (all are `SystemCapability.Multimedia.Image.Core`, all take/return the chain head):

| Method | Since |
|---|---|
| `blur(radius: number): Filter` | **9** |
| `blur(radius: number, tileMode: TileMode): Filter` | **14** |
| `brightness(bright: number): Filter` (range `[0,1]`, `0` = unchanged) | **9** |
| `grayscale(): Filter` | **9** |
| `invert(): Filter` | **12** |
| `setColorMatrix(colorMatrix: Array<number>): Filter` | **12** |
| `getPixelMap(): image.PixelMap` | 9, **deprecated 11** → use `getEffectPixelMap` |
| `getEffectPixelMap(): Promise<image.PixelMap>` | **11** |
| `getEffectPixelMap(useCpuRender: boolean): Promise<image.PixelMap>` | **20** |
| `ellipticalGradientBlur(...)` | 23, `@systemapi` |

```ts
enum TileMode { CLAMP = 0, REPEAT = 1, MIRROR = 2, DECAL = 3 }   // API 14
```

Documented `TileMode` caveat: *"Under CPU rendering, the shader tile mode supports only DECAL."*

`ColorPicker` methods: `getMainColor()` **9**, `getMainColorSync()` **9**, `getLargestProportionColor()` **10**, `getHighestSaturationColor()` **10**, `getAverageColor()` **10**, `isBlackOrWhiteOrGrayColor(color: number)` **10**, `getTopProportionColors(colorCount: number)` **12**.

`Color` = `{ red, green, blue, alpha }`, each `[0x0, 0xFF]`.

**Doc/SDK discrepancy on `setColorMatrix`:** the prose docs say *"A 5 x 4 matrix can be created"* while the SDK `.d.ts` says *"A 4x5 matrix… The array length must be 20. The first four columns correspond to the transformation coefficients of the R, G, B, and A channels, and the fifth column is the constant offset value… If the array length is not 20, null is returned."* The SDK wording (length 20, 4 rows × 5 columns) is the actionable one.

### 7.3 Does effectKit work on ArkUI components?

**No.** Every entry point takes `image.PixelMap`. There is **no component-level API** in `effectKit`. Consequences:

* To apply an effectKit filter to a component you must first obtain a `PixelMap` of it — e.g. `UIContext.getComponentSnapshot()` / `componentSnapshot` (`@kit.ArkUI`), or decode/`ImageBitmap`/`OffscreenCanvasRenderingContext2D.getPixelMap` — process it, then render the resulting `PixelMap` with `Image(...)` or `Shape(pixelMap)`.
* The component-level counterpart is `uiEffect` (`backgroundFilter` / `foregroundFilter` / `compositingFilter` / `visualEffect`), which applies a filter **live** to a component (§6).
* Practical pattern for a *static* neon glow: render the glow layer once, blur it with `effectKit`, then animate only opacity/scale of the resulting `Image` — avoids the documented per-frame blur cost.

Official widget/atomic-service capability for these APIs is API 12.

Source: [js-apis-effectKit.md (en)](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkgraphics2d/js-apis-effectKit.md) · [@ohos.effectKit.d.ts](https://raw.githubusercontent.com/openharmony/interface_sdk-js/master/api/@ohos.effectKit.d.ts)

---

## 8. `blendMode()` — additive / blend-mode compositing

**Yes, it exists**, as a universal attribute documented in `ts-universal-attributes-image-effect.md`.

### 8.1 Signature and since-versions

```ts
// API 11+   (module heading: "blendMode<sup>11+</sup>")
blendMode(value: BlendMode, type?: BlendApplyType): T

// API 18+ — `mode` supports undefined
blendMode(mode: Optional<BlendMode>, type?: BlendApplyType): T
```

Widget capability since API 11; atomic service since API 12. System capability `SystemCapability.ArkUI.ArkUI.Full`.

Documented semantics: *"Defines how the component's content (including the content of it child components) is blended with the existing content on the canvas (possibly offscreen canvas) below."*

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `value`/`mode` | `BlendMode` | `BlendMode.NONE` | **"When `BlendMode.NONE` is used, the blend effect is `BlendMode.SRC_OVER` by default, and `BlendApplyType` does not take effect."** `undefined` (18+) reverts to no offscreen blending |
| `type` | `BlendApplyType` | `BlendApplyType.FAST` | see below |

```ts
enum BlendApplyType {   // API 11+
  FAST = 0,       // "The content of the view is blended in sequence on the target image." (no offscreen)
  OFFSCREEN = 1   // component + children drawn to an offscreen canvas, then blended with the canvas below
}
```

**Documented `OFFSCREEN` caveat (verbatim):**

> "`BlendApplyType.OFFSCREEN`: An offscreen canvas of the size of the current component is created. The content of the current component (including child components) is then drawn onto the offscreen canvas, and blended with the existing content on the canvas below using the specified blend mode. This approach may cause issues with screen capture for APIs such as `linearGradientBlur`, `backgroundEffect`, `brightness`, and `blur`."

### 8.2 `BlendMode` enum — all values (whole enum is **API 11+**)

| Value | # | Formula / meaning |
|---|---|---|
| `NONE` | 0 | top image superimposed on bottom, no blending |
| `CLEAR` | 1 | target pixels erased to fully transparent |
| `SRC` | 2 | `r = s` (source only) |
| `DST` | 3 | `r = d` (target only) |
| `SRC_OVER` | 4 | `r = s + (1 - sa) * d` |
| `DST_OVER` | 5 | `r = d + (1 - da) * s` |
| `SRC_IN` | 6 | `r = s * da` |
| `DST_IN` | 7 | `r = d * sa` |
| `SRC_OUT` | 8 | `r = s * (1 - da)` |
| `DST_OUT` | 9 | `r = d * (1 - sa)` |
| `SRC_ATOP` | 10 | `r = s * da + d * (1 - sa)` |
| `DST_ATOP` | 11 | `r = d * sa + s * (1 - da)` |
| `XOR` | 12 | `r = s * (1 - da) + d * (1 - sa)` |
| **`PLUS`** | **13** | **`r = min(s + d, 1)` — true additive / "add" blend** |
| `MODULATE` | 14 | `r = s * d` |
| **`SCREEN`** | **15** | **`r = s + d - s * d`** |
| `OVERLAY` | 16 | MULTIPLY or SCREEN depending on target |
| `DARKEN` | 17 | `rc = s + d - max(s * da, d * sa), ra = kSrcOver` |
| **`LIGHTEN`** | **18** | `rc = s + d - min(s * da, d * sa), ra = kSrcOver` |
| `COLOR_DODGE` | 19 | target lightened to reflect source |
| `COLOR_BURN` | 20 | target darkened to reflect source |
| `HARD_LIGHT` | 21 | MULTIPLY or SCREEN depending on source |
| `SOFT_LIGHT` | 22 | LIGHTEN or DARKEN depending on source |
| `DIFFERENCE` | 23 | `rc = s + d - 2 * min(s * da, d * sa)` |
| `EXCLUSION` | 24 | `rc = s + d - two(s * d)` (sic) — like DIFFERENCE, lower contrast |
| `MULTIPLY` | 25 | `r = s * (1 - da) + d * (1 - sa) + s * d` |
| `HUE` | 26 | luminance+saturation of source, hue of target |
| `SATURATION` | 27 | luminance+hue of target, saturation of source |
| `COLOR` | 28 | saturation+hue of source, luminance of target |
| `LUMINOSITY` | 29 | saturation+hue of target, luminance of source |

Notation from the doc: *"`s` indicates the source pixel, `d` the target pixel, `sa` the opacity of the source pixel, `da` the opacity of the target pixel, `r` the pixel after blending, and `ra` the opacity of the pixel after blending."*

> **Documentation defect to be aware of:** the description column for `LIGHTEN` (18) reads *"The darker of the pixels (source and target) is used"* — that is the DARKEN description, copy-pasted incorrectly. The formula `rc = s + d - min(s * da, d * sa)` is the correct LIGHTEN behaviour. Do not rely on the prose for 17/18.

### 8.3 Practical notes for additive light

* `BlendMode.PLUS` is the only pure additive mode; `SCREEN` is the "lighten without clipping" mode; `LIGHTEN` is a max-like mode.
* The blend target is **what is already drawn on the canvas below the component**, so stacking N translucent glow layers inside one container and applying `blendMode(BlendMode.PLUS, BlendApplyType.OFFSCREEN)` to the **container** accumulates them as a single additive layer. With `FAST`, children are "blended in sequence on the target image" and the group is not flattened first.
* `blendMode` is on `CommonMethod<T>`, so it can be applied to a `Shape`/`Path`/`Stack`/`Row` alike.
* `BlendMode.NONE` silently degrades to `SRC_OVER` and ignores `type`.
* If you keep `OFFSCREEN` on, remember the documented screen-capture interference with `blur`, `brightness`, `backgroundEffect`, `linearGradientBlur`. Also documented nearby: `pixelRound` may be needed to avoid hairline seams when two components sharing a `blendMode` edge fall on fractional pixel coordinates.

Official additive example (verbatim from the docs, `BlendMode.OVERLAY` variant):

```ts
Row() {
  Circle().width(200).height(200).fill(Color.Green).position({ x: 50, y: 50 })
  Circle().width(200).height(200).fill(Color.Blue).position({ x: 150, y: 50 })
}
.blendMode(BlendMode.PLUS, BlendApplyType.OFFSCREEN)   // ← swap OVERLAY → PLUS for additive
.alignItems(VerticalAlign.Center)
.height(300).width('100%')
```

Source: [ts-universal-attributes-image-effect.md](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-image-effect.md) (heading `blendMode<sup>11+</sup>`, `BlendApplyType<sup>11+</sup>`, `BlendMode<sup>11+</sup>`)

---

## 9. Official sample code for neon / glow / light-trail / particle effects

**Bottom line: there is no official Huawei/OpenHarmony sample that is *presented as* a neon / glow / light-trail demo, and no official doc frames `shadow()` as a glow mechanism.** `shadow()` with `radius > 0` and `offsetX == offsetY == 0` does appear in official examples, but as a *shadow* demo (the `useShadowBatching` example), not as a glow recipe. The building blocks below are official; the neon composition is yours.

### 9.1 Official: `Particle` component (the real declarative particle system) — **since API 10**

This is the one genuinely first-class declarative particle API in ArkUI (verified first-hand in the reference below).

* Reference: [ts-particle-animation.md](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-particle-animation.md)
* Guide (zh-cn): [arkts-particle-animation.md](https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/ui/arkts-particle-animation.md)

Doc note, verbatim: *"This component is supported since API version 10. Updates will be marked with a superscript to indicate their earliest API version."* Atomic service since **API 11**. *"If the screen is turned off and then turned on again, or the application is switched to the background and then brought back to the foreground, the particle animation will automatically pause."*

```ts
Particle(particles: Particles<PARTICLE, COLOR_UPDATER, OPACITY_UPDATER,
                              SCALE_UPDATER, ACC_SPEED_UPDATER,
                              ACC_ANGLE_UPDATER, SPIN_UPDATER>): ParticleAttribute

interface ParticleOptions<...> {
  emitter: EmitterOptions<PARTICLE>;
  color?: ParticleColorPropertyOptions<COLOR_UPDATER>;   // default { range: [Color.White, Color.White] }
  opacity?: ParticlePropertyOptions<number, OPACITY_UPDATER>;  // default { range: [1.0, 1.0] }
  scale?: ParticlePropertyOptions<number, SCALE_UPDATER>;      // default { range: [1.0, 1.0] }
  velocity?: VelocityOptions;                                  // default { speed: [0,0], angle: [0,0] }
  acceleration?: AccelerationOptions<ACC_SPEED_UPDATER, ACC_ANGLE_UPDATER>;
  spin?: ParticlePropertyOptions<number, SPIN_UPDATER>;
}

interface EmitterOptions<PARTICLE extends ParticleType> {
  particle: EmitterParticleOptions<PARTICLE>;   // type: POINT | IMAGE; count; lifetime (default 1000 ms); lifetimeRange
  emitRate?: number;                            // default 5 emits/sec
  shape?: ParticleEmitterShape;                 // RECTANGLE (default) | CIRCLE | ELLIPSE | ANNULUS (20+)
  position?: ParticleTuple<Dimension, Dimension>;  // default [0.0, 0.0]
  size?: ParticleTuple<Dimension, Dimension>;      // default ['100%','100%']
  annulusRegion?: ParticleAnnulusRegion;           // API 20+
}
```

Attributes (all `SystemCapability.ArkUI.ArkUI.Full`):

| Attribute | Since | Notes |
|---|---|---|
| `emitter(value: Array<EmitterProperty>)` | **12** | update emitter parameters at runtime |
| `disturbanceFields(fields: Array<DisturbanceFieldOptions>)` | **12** | turbulence / force fields |
| `rippleFields(fields: Array<RippleFieldOptions> \| undefined)` | **22** | wave-field forces |
| `velocityFields(fields: Array<VelocityFieldOptions> \| undefined)` | **22** | additive velocity fields |

Other documented details: particle types `POINT = 'point'` / `IMAGE = 'image'` (image `src` supports local and online sources, **SVG not supported**); `color.range` + `distributionType` (`DistributionType.UNIFORM` default, `RANDOM`/normal, **API 12**); per-property `updater.type` of `ParticleUpdater.NONE | RANDOM | CURVE` with `ParticlePropertyAnimation { from, to, startMillis, endMillis, curve }`. Documented perf guard: *"The `emitRate` value can significantly impact performance when it exceeds 5000; you are advised to set it to be less than 5000."* Also: *"If you do not want the animation to keep playing, you are advised not to set the lifetime to –1, which may greatly affect the performance."*

**Official sample code for particles** (linked from the reference's own examples, in the OpenHarmony sample repo):

* `applications_app_samples` → `code/DocsSample/ArkUISample/Animation/entry/src/main/ets/pages/particle/template3/Index.ets` (disturbance field)
* `…/particle/template4/Index.ets` (adjusting emitter position)
* `…/particle/template5/Index.ets` (annulus emitter)
* `…/particle/template6/Index.ets` (updating the annulus emitter)
* Repo path pattern: `https://gitcode.com/openharmony/applications_app_samples/blob/master/code/DocsSample/ArkUISample/Animation/entry/src/main/ets/pages/particle/…`

These are the closest thing to **official sample code for a "particle effect"** that I could find. Example 2 of the reference (image particles + point particles with curve-driven opacity/scale/acceleration/spin) is directly reusable as a spark/light-mote emitter.

### 9.2 Official: additive compositing (the light-accumulation primitive)

`blendMode(BlendMode.PLUS, BlendApplyType.OFFSCREEN)` — see §8. This is the only documented declarative additive path. The official example uses `BlendMode.OVERLAY` on a `Row` of two `Circle`s; substituting `PLUS` is a one-token change.

### 9.3 Official: Canvas `globalCompositeOperation = 'lighter'` + `shadowBlur`

The Canvas 2D API supports the classic neon recipe. **The Canvas module is supported since API version 8** (widget since 9, atomic service since 11). Verified first-hand in [ts-canvasrenderingcontext2d.md](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-canvasrenderingcontext2d.md):

| Member | Type | Default | Unit / notes | Since |
|---|---|---|---|---|
| `globalCompositeOperation` | `string` | `'source-over'` | **Supported values: `'source-over'`, `'source-atop'`, `'source-in'`, `'source-out'`, `'destination-over'`, `'destination-atop'`, `'destination-in'`, `'destination-out'`, `'lighter'`, `'copy'`, `'xor'`.** `'lighter'` is documented as "Displays both the new and existing drawing." | **API 8** |
| `shadowBlur` | `number` | `0.0` | unit **px**; "A larger value produces a greater blur effect. The value is of float type and must be greater than or equal to 0." negative/`NaN`/`Infinity` → default | **API 8** |
| `shadowColor` | `string` | `'#00000000'` (transparent black) | string colour format | **API 8** |
| `shadowOffsetX` | `number` | `0.0` | default unit **vp** | **API 8** |
| `shadowOffsetY` | `number` | `0.0` | default unit **vp** | **API 8** |
| `strokeStyle` | `string \| number (10+) \| CanvasGradient \| CanvasPattern` | `'#000000'` | **"When the type is `CanvasGradient`, this attribute indicates a gradient object, which is created via the `createLinearGradient` API."** | **API 8** |
| `fillStyle` | `string \| number (10+) \| CanvasGradient \| CanvasPattern` | `'#000000'` | same | **API 8** |

**This is the decisive contrast with declarative `Shape`:** `ctx.strokeStyle = ctx.createLinearGradient(...)` is documented and legal, i.e. **Canvas supports gradient strokes; declarative `Shape`/`Path` do not.**

Minimum viable neon stroke (all members API 8+):

```ts
private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

// inside Canvas(...).onReady(() => { ... })
this.ctx.beginPath();
this.ctx.moveTo(20, 120);
this.ctx.bezierCurveTo(120, 0, 220, 240, 320, 120);

// gradient stroke
const g = this.ctx.createLinearGradient(20, 120, 320, 120);
g.addColorStop(0.0, '#00E5FF');
g.addColorStop(1.0, '#FF00E5');
this.ctx.strokeStyle = g;
this.ctx.lineWidth = 6;
this.ctx.lineCap = 'round';
this.ctx.lineJoin = 'round';

// additive glow: draw a wide, blurred, 'lighter' halo first, then the crisp core
this.ctx.globalCompositeOperation = 'lighter';
this.ctx.shadowBlur = 30;              // px
this.ctx.shadowColor = '#00E5FF';
this.ctx.stroke();                     // halo pass
this.ctx.shadowBlur = 0;
this.ctx.stroke();                     // crisp core pass
```

Also documented and worth knowing for a light-trail animation loop: *"the commands are stored in the associated `Canvas` component's command queue. These commands are only executed when the current frame enters the rendering phase and the associated `Canvas` component is visible. Therefore, when the `Canvas` component is invisible (for example, off-screen or hidden), avoid frequent drawing calls to prevent command queue buildup and excessive memory usage."* And: *"When the width or height of the `Canvas` component exceeds 8000 px, rendering via the CPU causes significant performance degradation."*

Fade-the-trail technique: paint a translucent full-canvas rect (`fillStyle = 'rgba(0,0,0,0.15)'`) each frame instead of `clearRect`, with `globalCompositeOperation` back at `'source-over'` for that fill — the standard, and fully supported by the members above.

### 9.4 Official: `renderGroup` offscreen caching — and its documented failure mode

`renderGroup(true)` (API 10+) renders the subtree offscreen and caches the result. The official performance guide documents a **negative** case: when children animate every frame, the cache is invalidated and performance degrades measurably (reported frame-drop 77% → 100%, `FlushFrame` 3 ms → 15 ms). Source: `zh-cn/application-dev/performance/reasonable-using-renderGroup.md`.

Relevance to glow work: do **not** wrap a per-frame-animated glow subtree in `renderGroup(true)` unless the content is static; and remember that `blendMode(..., OFFSCREEN)` already forces an offscreen canvas.

### 9.5 Official performance data for blur (best-practice doc)

* [ui/arkts-blur-effect.md](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/ui/arkts-blur-effect.md) — *"The preceding APIs are real-time blurring APIs that perform rendering on a frame-by-frame basis, which incurs significant performance overhead. When both the blur content and blur radius remain unchanged, it is recommended that you use the static blur API `blur`."* Applies to `backdropBlur`, `blur`, `backgroundBlurStyle`, `foregroundBlurStyle`, `motionBlur`.
* The same best practice is mirrored in-repo as `zh-cn/application-dev/performance/fuzzy_scene_performance_optimization.md` with numbers: dynamic blur transition ≈ 6.113 ms / 108 fps vs static blur ≈ 3.357 ms / 119.9 fps (≈45% less render time).

### 9.6 Verdict for a neon / glow / light-trail implementation

| Need | Documented route | Caveat |
|---|---|---|
| Glowing **stroked curve** | `drawing.Pen.setMaskFilter(drawing.MaskFilter.createBlurMaskFilter(drawing.BlurType.OUTER, r))` in a `RenderNode.draw()` (API 12) | imperative, not declarative |
| Glowing **stroke with gradient** | `drawing.Pen.setShaderEffect(...)` + `setMaskFilter(...)` (API 12); or Canvas `createLinearGradient` + `shadowBlur` + `globalCompositeOperation='lighter'` | not possible with declarative `Shape` |
| Additive accumulation of light layers | `blendMode(BlendMode.PLUS, BlendApplyType.OFFSCREEN)` on the container (API 11) | breaks `blur`/`backgroundEffect`/`brightness`/`linearGradientBlur` screen capture in that subtree |
| Particles / sparks / trails | `Particle` component (API 12) | reference + guide listed above |
| Cheap static glow | Pre-render with `effectKit` (PixelMap), display as `Image`, animate opacity/scale only | PixelMap-only API |

**No official neon/glow/light-trail sample exists.** Everything above is composed from documented primitives; treat any "official" glow pattern you see elsewhere as community code.

---

## 10. UNVERIFIED / COULD NOT CONFIRM

Listed explicitly; **do not treat these as facts.**

1. **Gradient-on-stroke prohibition has no prose source.** No official Huawei/OpenHarmony doc sentence states "gradients do not apply to a `Shape`/`Path` stroke" (or the reverse). My §1.3 conclusion rests on (a) the complete documented attribute surface containing only `stroke(value: ResourceColor)`, (b) `ShapeAttribute extends CommonMethod<ShapeAttribute>`, and (c) ArkUI engine source `ShapePaintProperty` declaring `Fill`/`Stroke` as plain `Color`. It is **not** a quoted doc statement. Recommend a one-shot on-device test before relying on it.
2. **`shadow()` on a `Shape`/`Path` stroke.** No official document says whether the shadow silhouette is taken from the stroked path geometry, nor whether a background is required. The `fill` option (API 11+) implies silhouette-based shadow generation, but this is an inference.
3. **`shadow()` performance / offscreen rendering.** No documented performance caveat or "forces offscreen rendering" statement exists for `shadow()` in the en or zh-cn image-effect docs. The offscreen statements I did find concern `BlendApplyType.OFFSCREEN`, `renderGroup`, `sphericalEffect`, and `distortionCollapse` — not `shadow`.
4. **Lowercase / relative SVG path commands (`m`, `l`, `c`, `q`, `a`, `z`, `h`, `v`, `s`, `t`)** in `Path.commands`. The official "SVG Path Syntax" table lists only the uppercase (absolute) forms. I could not verify relative forms are supported.
5. **`VisualEffect` in API versions between 12 and 20.** I verified the interface only at API 12 (`OpenHarmony-5.0.0-Release`) and at current `master`. I did **not** enumerate every release tag, so I cannot state with certainty that no intermediate release ever exposed a public `backgroundBlur`/`foregroundBlur`/`borderRadius` on `VisualEffect`. What is certain is that **neither the API-12 SDK nor the current SDK contains those methods**.
6. **`effectKit` on ArkUI components.** Conclusion "PixelMap-only, no component-level API" is based on the module description and the complete list of entry points in both the prose doc and the `.d.ts`. I did not find any component-level overload — but absence of evidence in the sources I fetched is not a formal proof.
7. **`setColorMatrix` matrix shape.** Docs (§ "setColorMatrix") say "5 x 4"; the SDK `.d.ts` says 4×5 with array length 20. I could not determine which the runtime enforces beyond the documented "array length must be 20 / otherwise null is returned".
8. **`BlendMode.LIGHTEN` (18) description text is self-contradictory** (reads as the DARKEN description). The formula is authoritative; the prose is not. Not independently confirmed against engine source.
9. **`Path.strokeDashOffset` accepts `number | string`** while `Shape.strokeDashOffset` is documented as `Length` — this asymmetry is what the docs say, but I did not cross-check the `path.d.ts` SDK declaration.
10. **Huawei `developer.huawei.com` HTML pages** were not fetched directly (they are JS-rendered); all doc claims above come from the OpenHarmony markdown mirror, which the task statement identifies as the same content. Version-specific Huawei pages (e.g. `-V13`, `-V14` suffixes) may differ.
11. **Canvas §9.3 is now first-hand verified** against `ts-canvasrenderingcontext2d.md` (values, defaults, units and the API-8 module version all come from that page). Two residual gaps: (a) I confirmed `createLinearGradient` exists only via the `strokeStyle`/`fillStyle` table row that names it — I did not open its own section, nor `ts-components-canvas-canvasgradient.md`; (b) **`createConicGradient` is NOT mentioned anywhere in `ts-canvasrenderingcontext2d.md`** and I therefore removed it from the table. A sub-agent reported it as `@since 10, stage-model only` from `canvas.d.ts`; treat that as unverified.
12. **`Particle` §9.1 is now first-hand verified** against `ts-particle-animation.md` — including the correction that the component is **API 10** (an earlier sub-agent note said API 12; the doc note says API 10). I read the reference page's declaration, attributes, `ParticleOptions`/`EmitterOptions`/`ParticleColorPropertyOptions` and examples. I did **not** open `zh-cn/application-dev/ui/arkts-particle-animation.md` (the guide), so any guide-only claims should be re-checked. The `applications_app_samples` example paths were read from the reference page's own example links, not fetched.
13. **Performance numbers in §4 / §9.4 / §9.5** (6.113 ms vs 3.357 ms; 77% → 100% frame-drop; 3 ms → 15 ms `FlushFrame`) were taken from the in-repo best-practice markdowns via the sub-agent. They are device- and scenario-specific measurements quoted from official docs, not guarantees.
