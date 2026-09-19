# Canvas 发光线条动画特效 → HarmonyOS NEXT

把 `~/Downloads/canvas发光线条动画特效/`（WebGL fragment shader）的"双色发光曲线"特效
移植到 HarmonyOS NEXT 的完整调研 + 可编译工程。

**先读 [`REPORT.md`](REPORT.md)** —— 那是调研正文。本文件只讲怎么跑。

---

## 快速结论

用纯 ArkTS 就能做，不需要写 C++：

```
DrawingRenderingContext (API 12)
  └─ ctx.canvas : drawing.Canvas          ← 直接画在组件自己的 Skia surface 上
       ├─ Path.quadTo(...)                ← 复刻 shader 里的贝塞尔链
       ├─ Pen.setMaskFilter(BlurType.SOLID, sigma)   ← 三条宽模糊带重建 pow(R/d, 0.9) 的长尾辉光
       ├─ Pen.setBlendMode(BlendMode.PLUS)           ← 加色叠加，对应 shader 的 col +=
       └─ Canvas.attachPen → drawPath → detachPen
displaySync (API 11)                      ← 逐帧时钟（ArkTS 没有 requestAnimationFrame）
```

---

## 0. 克隆之后先做这一步

`GlowLemniscate/build-profile.json5` **没有进版本库**（见 `.gitignore`）：DevEco Studio 会把签名配置
写进这个文件，里面是加密后的 `keyPassword` / `storePassword` 以及指向本机 `~/.ohos/config`
密钥库的**绝对路径** —— 既是凭据、又和机器绑定，没法通过 git 共享。

```bash
cp GlowLemniscate/build-profile.example.json5 GlowLemniscate/build-profile.json5
```

然后用 DevEco Studio 打开工程，`File → Project Structure → Signing Configs` 勾选自动签名即可。
不配签名也能编译，只是产物是未签名 HAP，装不到设备上。

## 1. 编译

```bash
cd GlowLemniscate

export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
export HVIGOR_USER_HOME=$PWD/../.hvigor-home   # 把 hvigor 缓存留在工作区内，避免写 ~/.hvigor

/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw --no-daemon assembleHap
```

预期：`BUILD SUCCESSFUL`。产物在 `entry/build/default/outputs/default/`（未配签名，HAP 未签名属正常）。

## 2. 安装到设备

```bash
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
$HDC list targets                                  # 本机当前为空，需要接真机或起模拟器
```

签名后才能安装：用 DevEco Studio 打开 `GlowLemniscate/`，
`File → Project Structure → Signing Configs` 勾选自动签名，然后 Run。

> ⚠️ **DevEco 预览器不支持 XComponent，也不支持调用 C++ 库**。本工程是纯 ArkTS，
> 但 `DrawingRenderingContext` 的实际渲染表现仍建议以真机为准。

## 3. 在浏览器里预览效果（不需要设备）

`preview/glow-twin.html` 是 ArkTS 渲染器的孪生体：同样的常量、同样的坐标映射、同样的贝塞尔链，
只是用 Canvas 2D 的 `'lighter'` 代替 `BlendMode.PLUS`（两者底层都是 Skia）。

```bash
open "preview/glow-twin.html"                        # 实时动画
open "preview/glow-twin.html?t=2.5&w=900&h=700"      # 定格在 shader time = 2.5，与原版逐帧对比
open "preview/glow-twin.html?n=22"                   # 看环形模式的 banding 问题
open "preview/glow-twin.html?spike=1"                # 复现原版的退化 Bezier 尖刺
```

看横竖屏取景差异（`devH` = 真机高度，让小画布忠实复现手机的取景比例）：

```bash
# 竖屏 · 原版取景 —— 图形溢出 1.87 倍，只能看到中间一段
open "preview/glow-twin.html?w=630&h=1360&devH=2720&fit=0&t=2.5"
# 竖屏 · SizeMode.FIT —— 完整可见
open "preview/glow-twin.html?w=630&h=1360&devH=2720&fit=1&t=2.5"
# 横屏 —— 天然完整，图形更大
open "preview/glow-twin.html?w=1360&h=630&devH=1260&fit=1&t=2.5"
```

对比原版（时间冻结副本，`?t=` 同样可用）：

```bash
open "preview/original/index.html?t=2.5"
```

页面左上角 HUD 会显示 `render = x.xx ms` / `fps` / `figure = xx% of viewport width`，可直接用来估算法向绘制的成本与取景是否被裁。

## 4. 验证几何正确性

`tools/verify-geometry.mjs` 把原 GLSL 的 `sdBezier` / `getSegment` 逐行转写成 JS 作为参考实现，
再与移植侧的贝塞尔链在 160 万个采样点上比对：

```bash
node tools/verify-geometry.mjs
```

预期输出 `PASS`，且 `WITH the degenerate i=0 segment` 一行是 `mismatching: 0` / `max: 0.000e+0`
——即移植的链与原 shader 逐点零误差。不需要设备，纯 Node。

## 5. 横竖屏

已配置为 **`"orientation": "auto_rotation"`**（`entry/src/main/module.json5`），
竖屏 / 横屏 / 横屏反向 / 竖屏反向 四种朝向都支持，旋转时窗口自动重建、画布自动重测。

**为什么必须横屏看？** 这个 shader 的取景只取决于视口**高度**（像素）：

```
图形半宽 / 屏幕半宽 = 2 × 0.000015 × 22.906 × H = 6.8719e-4 × H
```

只有 `H < 1455 px` 才装得下。手机竖屏 `H = 2720` → **溢出 1.87 倍**，只能看到中间一段；
横屏 `H = 1260` → 0.87 倍，完整可见。

工程里同时加了 `SizeMode.FIT` 钳制，所以竖屏和高分屏也不会被裁（只缩不放，
在本来就装得下的横屏窗口里与原版取景完全一致）。

| 需求 | 改法 |
|---|---|
| 保持横竖屏自由旋转（当前） | `module.json5` → `"orientation": "auto_rotation"` |
| **强制横屏**（无视系统旋转锁定） | → `"orientation": "landscape"` |
| 横屏两种朝向，跟随系统旋转锁定 | → `"orientation": "auto_rotation_landscape"` |
| 回到原版取景（竖屏会被裁） | `Index.ets` → `this.renderer.setSizeMode(SizeMode.SHADER)` |
| 关掉全屏沉浸 | `EntryAbility.ets` → `IMMERSIVE = false` |

取景对比图：`preview/frames/orientation.png`。

## 6. 长列表 · 滚动锚定 Demo

首页右上角「列表 Demo」按钮进入 `pages/ListPage`（独立路由）。

**滚动效果是通用组件，和业务无关，全部可配置** —— `entry/src/main/ets/scroll/AnchoredPaging.ets`。
它不持有数据、不认识你的类型、不发起请求；只在你该加载的时候发信号：

```ts
private paging = new AnchoredPaging({
  prefetchRows: 2,       // 距末尾几行要下一页
  pullThresholdVp: 80,   // 触顶后下拉多少 vp，松手才算请求
  pullSteps: 10,         // 指示器进度格数
  anchor: { toleranceVp: 1.0, maxCorrections: 40, stallLimit: 3 }
});

this.paging.onRequestOlder = () => { this.loadOlder(); };   // 你原有的逻辑
this.paging.onRequestNewer = () => { this.loadNewer(); };

this.paging.insertAnchored(page.length, () => {             // 包住「改数据」这一步
  this.items = page.concat(this.items);                     // 数组是你的
});
```

接线只有六个滚动回调（`onScrollIndex` / `onScrollStart` / `onScrollStop` /
`onReachStart` / `onScrollFrameBegin` + 行上的 `onAreaChange`），**没有任何手势**。

| 属于效果的参数 | 属于你的业务 |
|---|---|
| `prefetchRows`、`pullThresholdVp`、`pullSteps`、`anchor.*` | `pageSize`、数据源、加载状态位、空态/错误态 |

**判据：「滚动该怎么反应」是效果的；「数据从哪来、一次要多少」是你的。**

`ListPage.ets` 现在只是演示宿主，只剩「行长什么样 / 数据从哪来 / 一页多少条」。
接入方式、机制、真机踩坑见 **[`docs/LIST-SCROLL-ANCHOR.md`](docs/LIST-SCROLL-ANCHOR.md)**。

## 7. 代码结构

| 文件 | 说明 |
|---|---|
| `entry/src/main/ets/glow/GlowCurve.ets` | shader 几何的纯函数移植。无 ArkUI 依赖，常量与 GLSL 一一对应，逐行注释标了出处 |
| `entry/src/main/ets/glow/GlowRenderer.ets` | `drawing` API 渲染器。两种辉光模式：`BLUR`（默认，宽模糊带）/ `RINGS`（距离场环形） |
| `entry/src/main/ets/pages/Index.ets` | 首页：`Canvas(DrawingRenderingContext)` + `displaySync` 主循环，右上角有进入列表 Demo 的按钮 |
| `entry/src/main/ets/pages/ListPage.ets` | 长列表路由页：**只是演示宿主**，只含业务（行样式 / 数据源 / 页大小） |
| `entry/src/main/ets/scroll/AnchoredPaging.ets` | **通用滚动效果**：业务无关、全部可配置。分页触发 + 位置保持 |
| `entry/src/main/ets/scroll/AnchorKeeper.ets` | 底层锚定原语（被 `AnchoredPaging` 使用），阈值经 `AnchorOptions` 注入 |
| `entry/src/main/ets/model/FeedItem.ets` | 列表数据模型，含变高条目与"慢速渲染"模拟 |

想换辉光模式：

```ts
// Index.ets
this.renderer.setMode(GlowMode.RINGS);   // 或 GlowMode.BLUR（默认）
```

想复现原版那个退化 Bezier 尖刺：`GlowRenderer.ets` 里 `INCLUDE_SPIKE = true`。

## 8. 调参速查

| 想要 | 改哪里 |
|---|---|
| 图形更大/更小 | `GlowCurve.ets` → `SHAPE_SCALE`（0.000015） |
| 竖屏/高分屏留白更多 | `GlowCurve.ets` → `FIT_MARGIN`（0.90，占视口的比例） |
| 辉光更亮/更宽 | `GlowRenderer.ets` → `BLUR_PASSES` 的 `alpha` / `sigmaFactor`；半径基准 `GLOW_RADIUS`（0.02，画布宽度的比例）。**改 `sigma` 时必须保持 `sigma ≥ 相邻带宽间距`**，否则会出现同心壳 |
| 芯线更粗 | `GlowRenderer.ets` → `CORE_WIDTH_FACTOR` / `CORE_HALO_WIDTH_FACTOR`（画布宽度的比例，对应 shader 的 `smoothstep(0.003, 0.001, dist)`；**不能用固定像素值**） |
| 白线"发光感"强弱 | `GlowRenderer.ets` → `TONE_LIFT_ALPHA`（0.55）/ `TONE_LIFT_WIDTH_FACTOR`（0.70R）—— 补偿 shader 色调映射的软限幅，见 REPORT.md §4.5。调大 = 白线更粗更亮更"过曝" |
| 颜色 | `GlowCurve.ets` → `TRAILS`（对应 shader 里的 `vec3(0.7,0.3,0.9)` / `vec3(0.3,0.5,0.9)`） |
| 动画更快/更慢 | `GlowCurve.ets` → `SPEED`（-0.7）/ `TIME_STEP`（0.015） |
| 帧率 | `Index.ets` → `setExpectedFrameRateRange({expected, min, max})` |
| 横竖屏策略 | `module.json5` → `"orientation"`；详见 §5 |
| 取景方式 | `Index.ets` → `setSizeMode(SizeMode.FIT / SizeMode.SHADER)` |

## 9. 深入材料

`research/` 下有约 20 万字的核实报告，全部标注了官方来源，并对每条结论区分了
"官方文档确认 / 推断 / 未能确认"：

- `drawing-module-api-research.md` —— `@ohos.graphics.drawing` 逐 API 核实（含 since 版本）
- `neon-glow-pure-arkts.md` —— 纯 ArkTS 发光方案审计，含被否决方案与原因
- `xcomponent-opengl-research.md` —— XComponent + OpenGL ES 全流程、EGL 骨架、崩溃陷阱、官方 sample 索引
- `arkui-visual-effects-audit.md` —— 声明式视觉效果（blur / shadow / effectKit / Particle）能力审计
- `raw/` —— 103 份官方文档原文缓存
