# Rendering custom OpenGL ES in HarmonyOS NEXT (API 12–24, ArkTS/Stage model)

**Scope:** how to render custom OpenGL ES content into a HarmonyOS NEXT application using `XComponent` + NDK/NAPI.
**Method:** all facts below are taken from the upstream **OpenHarmony `docs`** repository on Gitee (which is the
source that Huawei's `developer.huawei.com/consumer/cn/doc/harmonyos-guides/...` pages are generated from) and from
the official **`openharmony/applications_app_samples`** repository. Verified raw-markdown URLs are given for every claim.

> **Reading the citations.** `developer.huawei.com` doc pages are a JavaScript SPA: fetching them with `curl`
> returns only the page title. The Gitee markdown files are the actual source text and are what I verified.
> Where a Huawei URL is given, it is the equivalent generated page (slug confirmed by web search), but the
> *content* claim is backed by the Gitee file.

---

## 0. Executive summary / recommended architecture

| Decision | Recommendation | Why |
|---|---|---|
| Component | `XComponent({ type: XComponentType.SURFACE, controller })` | `SURFACE` gives you a dedicated buffer queue you own; `TEXTURE` composites into the ArkUI render pass (higher power, GPU composition). |
| Lifecycle API | **`OH_ArkUI_SurfaceHolder` (API 19+)** if you can require API 19; otherwise `OH_NativeXComponent` (API 8+) | Huawei explicitly recommends migrating away from `OH_NativeXComponent` — it is lifetime-unsafe and has a poorer event API. |
| Render loop | **`OH_NativeXComponent_RegisterOnFrameCallback` / `OH_ArkUI_XComponent_RegisterOnFrameCallback`** for the simple case; **`OH_NativeVSync` + your own render thread** for maximum control | Huawei ships a whole guide (`displaysync-xcomponent`) for the former; the `NdkNativeImage` sample demonstrates the latter. |
| Threading | Surface lifecycle callbacks arrive on the **UI main thread**. Keep them cheap. Do heavy GL work on your own thread and hand the `OHNativeWindow*` over. | Documented warning: "Callback回调函数运行于UI主线程，故涉及UI线程的耗时操作不应运行于回调函数中". |
| WebGL from ArkTS | **Not possible.** ArkTS `Canvas` is 2D-only. WebGL exists only inside the `Web` component (ArkWeb). | See §8. |

---

## 1. ArkTS side: declaring `XComponent` with `type: XComponentType.SURFACE`

### 1.1 The three constructor overloads

Source: [`zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-basic-components-xcomponent.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-basic-components-xcomponent.md)
· Huawei equivalent: <https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-xcomponent>

**API 12+ (current, recommended) — `XComponentOptions`:**

```typescript
XComponent(options: XComponentOptions)
```

```typescript
interface XComponentOptions {
  type: XComponentType;                 // required
  controller: XComponentController;     // required
  imageAIOptions?: ImageAIOptions;      // optional (AI analysis)
}
```

**API 10+ (legacy, still works, "不再演进" / no longer evolving from API 12) — `id`/`libraryname` form:**

```typescript
XComponent(value: {id: string, type: XComponentType, libraryname?: string, controller?: XComponentController})
```

| Param | Type | Req | Notes (verbatim from doc) |
|---|---|---|---|
| `id` | `string` | yes | 组件的唯一标识，支持最大的字符串长度128 — unique component id, max 128 chars |
| `type` | `XComponentType` | yes | component type |
| `libraryname` | `string` | no | 用Native层编译输出动态库名称（对应的动态库不支持跨模块加载），仅类型为SURFACE或TEXTURE时有效 — native `.so` name; **does not support cross-module loading**; only valid for SURFACE/TEXTURE |
| `controller` | `XComponentController` | no | 给组件绑定一个控制器…仅类型为SURFACE或TEXTURE时有效 |

**API 19+ — `NativeXComponentParameters` (NDK-only, no controller, no id/libraryname):**

```typescript
XComponent(params: NativeXComponentParameters)
interface NativeXComponentParameters {
  type: XComponentType;
  imageAIOptions?: ImageAIOptions;
}
```
> 通过这种构造参数创建的XComponent，可以将其对应的 `FrameNode` 对象传递至Native侧，使用NDK接口进行Surface生命周期的相关设置和添加事件监听。
> (With this form you pass the FrameNode to native and use NDK interfaces for surface lifecycle + events.)

### 1.2 `XComponentType` enum (API 10+)

Source: [`ts-appendix-enums.md#xcomponenttype10`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-appendix-enums.md)

| Name | Meaning |
|---|---|
| `SURFACE` | 用于EGL/OpenGLES和媒体数据写入，单独展示开发者定制的绘制内容到屏幕上。背景色设置为黑色时走显示子系统（DSS）。 |
| `TEXTURE` | 用于EGL/OpenGLES和媒体数据写入，开发者定制的绘制内容将与XComponent组件的内容合成后展示到屏幕上。…走GPU合成，相比surface可能走显示子系统（DSS）功耗更高。 |
| `COMPONENT` | **deprecated since API 12** |
| `NODE` | **deprecated since API 20** (use `ContentSlot`) |

> **Rule of thumb (from the enum doc):** `SURFACE` = your content is shown standalone (may go through DSS = lower power);
> `TEXTURE` = your content is composited with ArkUI content in the same frame (GPU composition = higher power).
> Both accept EGL/OpenGL ES and media data.

### 1.3 Getting the controller and the surface id

```typescript
@Entry
@Component
struct Index {
  // 1. create a controller (or subclass it, §1.4)
  myXComponentController: XComponentController = new XComponentController();

  build() {
    Column() {
      // 2. bind it
      XComponent({
        type: XComponentType.SURFACE,
        controller: this.myXComponentController
      })
        .onLoad(() => {
          // 3. read the surface id
          let surfaceId: string = this.myXComponentController.getXComponentSurfaceId();
          console.info("XComponent SurfaceId: " + surfaceId);
        })
    }
  }
}
```

`getXComponentSurfaceId(): string` — **API 9+**
> 获取XComponent对应Surface的ID，仅XComponent类型为SURFACE("surface")或TEXTURE时有效。

Returns the surface ID as a **string**. In practice you pass it to native as a `BigInt` (see §1.5), or assign it to a
media object such as `AVPlayer.surfaceId`.

> **Timing caveat (documented):** 使用自定义组件节点创建XComponent组件时，因为onLoad回调触发时机早于onSurfaceCreated，
> 所以在onLoad回调中调用getXComponentSurfaceId获取surfaceId会失败，建议在onSurfaceCreated回调中获取。
> → *When the XComponent is created via a custom component node (`typeNode.createNode`), `onLoad` fires **before**
> `onSurfaceCreated`, so `getXComponentSurfaceId()` fails inside `onLoad`. Read it in `onSurfaceCreated` instead.*

### 1.4 Registering `onLoad` / `onDestroy` and the lifecycle callbacks

Two orthogonal mechanisms exist. **They are mutually exclusive when `libraryname` is set** — see the warning below.

**(a) Component-level events** (always available for SURFACE/TEXTURE):

```typescript
XComponent({ type: XComponentType.SURFACE, controller: this.controller })
  .onLoad((xComponentContext?: object) => {   // API 12+; typed OnNativeLoadCallback from API 18
    // "插件加载完成时回调事件" — fires when the plugin (.so) has finished loading
    this.xComponentContext = xComponentContext as XComponentContext;
  })
  .onDestroy(() => {                          // VoidCallback
    console.info('onDestroy');                // "插件卸载完成时回调事件"
  })
  .id('xcomponent')
```

- `onLoad(callback: OnNativeLoadCallback)` where `type OnNativeLoadCallback = (event?: object) => void` (API 18+).
  The `event` object is the XComponent instance's `context`; **the methods hung on it are defined by you in native code**.
  This is exactly how samples expose native functions back to ArkTS.
- `onDestroy(event: VoidCallback)`.

**(b) Controller lifecycle callbacks** (override `XComponentController`):

```typescript
class MyXComponentController extends XComponentController {
  onSurfaceCreated(surfaceId: string): void {
    console.info(`onSurfaceCreated surfaceId: ${surfaceId}`);
    nativeRender.SetSurfaceId(BigInt(surfaceId));
  }
  onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    console.info(`onSurfaceChanged surfaceId: ${surfaceId}, rect: ${JSON.stringify(rect)}}`);
    nativeRender.ChangeSurface(BigInt(surfaceId), rect.surfaceWidth, rect.surfaceHeight);
  }
  onSurfaceDestroyed(surfaceId: string): void {
    console.info(`onSurfaceDestroyed surfaceId: ${surfaceId}`);
    nativeRender.DestroySurface(BigInt(surfaceId));
  }
}
```
(source: [`napi-xcomponent-guidelines.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/ui/napi-xcomponent-guidelines.md) §XComponent的开发范式, and the
[`ArkTSXComponent` sample](https://gitcode.com/openharmony/applications_app_samples/blob/master/code/BasicFeature/Native/ArkTSXComponent/entry/src/main/ets/pages/Index.ets))

- `onSurfaceCreated(surfaceId: string): void` — API 12+
- `onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void` — API 12+
- `onSurfaceDestroyed(surfaceId: string): void` — API 12+
- `SurfaceRect = { offsetX, offsetY, surfaceWidth, surfaceHeight }` — API 12+

> ⚠️ **CRITICAL, easily-missed caveat.** All three controller callbacks carry this note in the reference doc:
> **仅当XComponent组件未设置libraryname参数时，会进行该回调。**
> *"This callback is only invoked when the XComponent component does **not** set the `libraryname` parameter."*
> So you must choose: **either** `libraryname` + native `OH_NativeXComponent_Callback`,
> **or** no `libraryname` + ArkTS `XComponentController` callbacks. Setting both silently disables the ArkTS side.

Related: 当配置libraryname参数时，点击事件、触摸事件、挂载卸载事件、按键事件、焦点事件、鼠标事件仅响应C-API侧事件接口。
→ *With `libraryname` set, click/touch/attach-detach/key/focus/mouse events are handled **only** by the C-API side.*

### 1.5 Full recommended ArkTS page (API 12+, controller-driven, controller-derived EGL context in native)

This is the pattern used by the official `ArkTSXComponent` sample — native owns the `OHNativeWindow` obtained from
`OH_NativeXComponent_Callback`; ArkTS only forwards `surfaceId` + size.

```typescript
import nativeRender from 'libnativerender.so';

class MyXComponentController extends XComponentController {
  onSurfaceCreated(surfaceId: string): void {
    nativeRender.SetSurfaceId(BigInt(surfaceId));
  }
  onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    nativeRender.ChangeSurface(BigInt(surfaceId), rect.surfaceWidth, rect.surfaceHeight);
  }
  onSurfaceDestroyed(surfaceId: string): void {
    nativeRender.DestroySurface(BigInt(surfaceId));
  }
}

@Entry
@Component
struct Index {
  @State currentStatus: string = "index";
  xComponentController: XComponentController = new MyXComponentController();

  build() {
    Column({ space: 10 }) {
      XComponent({
        type: XComponentType.SURFACE,
        controller: this.xComponentController
      })
      Text(this.currentStatus).fontSize('24fp')
    }
    .onClick(() => {
      let surfaceId = this.xComponentController.getXComponentSurfaceId();
      nativeRender.ChangeColor(BigInt(surfaceId));
    })
    .width('100%').height('100%')
  }
}
```
Source: [`ArkTSXComponent/entry/src/main/ets/pages/Index.ets`](https://gitcode.com/openharmony/applications_app_samples/blob/master/code/BasicFeature/Native/ArkTSXComponent/entry/src/main/ets/pages/Index.ets)

### 1.6 Full ArkTS page using the NDK / `OH_ArkUI_SurfaceHolder` route (API 19+)

```typescript
import native from 'libnativerender.so';
import { FrameNode, NodeController, typeNode, UIContext } from '@kit.ArkUI';

@Component
export struct SurfaceHolderDeclarative {
  @State currentStatus: string = 'init';
  private xcNode: FrameNode | null = null;

  build() {
    NavDestination() {
      Column({ space: 10 }) {
        XComponent({ type: XComponentType.SURFACE })   // note: no id, no libraryname
          .id('XComponentSurfaceHolder')
          .onAttach(() => {
            this.xcNode = this.getUIContext().getAttachedFrameNodeById('XComponentSurfaceHolder');
            if (!this.xcNode) { return; }
            native.bindNode('XComponentSurfaceHolder', this.xcNode); // cross-language: hand FrameNode to native
          })
          .onDetach(() => {
            native.unbindNode('XComponentSurfaceHolder');
            this.xcNode = null;
          })
      }
    }
  }
}
```
Source: [`napi-xcomponent-guidelines.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/ui/napi-xcomponent-guidelines.md) · sample:
[`SurfaceHolderDeclarative.ets`](https://gitcode.com/openharmony/applications_app_samples/blob/master/code/BasicFeature/Native/NativeXComponent/entry/src/main/ets/pages/SurfaceHolderDeclarative.ets)

---

## 2. Native (C/C++) side: headers, callback struct, registration

### 2.1 Header / library map (all verified)

| Header | Library (CMake `find_library` name / soname) | Since |
|---|---|---|
| `<ace/xcomponent/native_interface_xcomponent.h>` | `libace_ndk.z.so` (`ace_ndk.z`) — *this is the ArkUI NDK lib, not the NAPI lib* | API 8 |
| `<native_window/external_window.h>` (+ `<native_window/buffer_handle.h>`, `<native_window/graphic_error_code.h>`) | `libnative_window.so` | API 8 |
| `<native_buffer/native_buffer.h>`, `<native_buffer/buffer_common.h>` | `libnative_buffer.so` | API 9 (common types moved to `buffer_common.h` at API 12) |
| `<native_vsync/native_vsync.h>` | `libnative_vsync.so` | API 9 |
| `<EGL/egl.h>`, `<EGL/eglext.h>`, `<EGL/eglplatform.h>` | `EGL` | — |
| `<GLES3/gl3.h>` | `GLESv3` | — |
| `<hilog/log.h>` | `hilog_ndk.z` | — |
| `<napi/native_api.h>` | `ace_napi.z` (soname `libace_napi.z.so`) | — |

Sources: [`capi-native-interface-xcomponent-h.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-arkui/capi-native-interface-xcomponent-h.md)
(引用文件：`<ace/xcomponent/native_interface_xcomponent.h>`，库：`libace_ndk.z.so`) ·
[`capi-external-window-h.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-arkgraphics2d/capi-external-window-h.md) ·
[`capi-oh-nativebuffer.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-arkgraphics2d/capi-oh-nativebuffer.md) ·
[`capi-nativevsync.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-arkgraphics2d/capi-nativevsync.md) ·
[`native-window-guidelines.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/graphics/native-window-guidelines.md)

> Note: `NativeWindow` / `OHNativeWindow` is declared in **`native_interface_xcomponent.h`** as
> `typedef struct NativeWindow OHNativeWindow` (listed under the OH_NativeXComponent module, since API 19 for that
> typedef), while the *functions* on it live in `<native_window/external_window.h>`.

### 2.2 `OH_NativeXComponent_Callback`

Source: [`capi-oh-nativexcomponent-native-xcomponent-oh-nativexcomponent-callback.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-arkui/capi-oh-nativexcomponent-native-xcomponent-oh-nativexcomponent-callback.md)
· Huawei: <https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ent-native-xcomponent-oh-nativexcomponent-callback>

```c
typedef struct OH_NativeXComponent_Callback {
    void (*OnSurfaceCreated)(OH_NativeXComponent* component, void* window);
    void (*OnSurfaceChanged)(OH_NativeXComponent* component, void* window);
    void (*OnSurfaceDestroyed)(OH_NativeXComponent* component, void* window);
    void (*DispatchTouchEvent)(OH_NativeXComponent* component, void* window);
} OH_NativeXComponent_Callback;
```

| Member | 描述 | Since |
|---|---|---|
| `OnSurfaceCreated` | 创建Surface时调用。 | API 8 |
| `OnSurfaceChanged` | 当Surface改变时调用。 | API 8 |
| `OnSurfaceDestroyed` | 当Surface被销毁时调用。 | API 8 |
| `DispatchTouchEvent` | 当触摸事件被触发时调用。 | API 8 |

For all four, `void* window` = **表示NativeWindow句柄** ("the NativeWindow handle"). The `OnSurfaceCreated` doc adds a
crucial ownership note:

> 通过XComponent生命周期获取的NativeWindow本身由系统侧持有了一次引用计数，并会在OnSurfaceDestroyed回调触发之后将引用计数减一，
> 引用计数归零后NativeWindow将被释放。
>
> *"The NativeWindow obtained through the XComponent lifecycle is itself reference-counted once by the system, and the
> count is decremented after `OnSurfaceDestroyed` fires; when it reaches zero the NativeWindow is freed."*

→ **Do not cache the `window` pointer past `OnSurfaceDestroyed`.**

### 2.3 Obtaining the `OH_NativeXComponent*` instance

Required only for the legacy `id`+`libraryname` route. The framework calls your module's `Init` and passes the
`OH_NativeXComponent` on `exports` under a magic property name.

```c
#define OH_NATIVE_XCOMPONENT_OBJ ("__NATIVE_XCOMPONENT_OBJ__")   // macro from the header
#define OH_XCOMPONENT_ID_LEN_MAX 128                              // const uint32_t, API 8
```

```cpp
napi_value exportInstance = nullptr;
OH_NativeXComponent *nativeXComponent = nullptr;
char idStr[OH_XCOMPONENT_ID_LEN_MAX + 1] = {'\0'};
uint64_t idSize = OH_XCOMPONENT_ID_LEN_MAX + 1;

// OH_NATIVE_XCOMPONENT_OBJ / OH_XCOMPONENT_ID_LEN_MAX come from
// <ace/xcomponent/native_interface_xcomponent.h>
if (napi_get_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ, &exportInstance) != napi_ok) {
    return;                                        // property missing
}
if (napi_unwrap(env, exportInstance, reinterpret_cast<void **>(&nativeXComponent)) != napi_ok) {
    return;                                        // unwrap failed
}
if (OH_NativeXComponent_GetXComponentId(nativeXComponent, idStr, &idSize)
        != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
    return;
}
std::string id(idStr);                             // matches the ArkTS `id:` string
```
Source: [`napi-xcomponent-guidelines.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/ui/napi-xcomponent-guidelines.md) (`PluginManager::Export`) ·
[`native-window-guidelines.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/graphics/native-window-guidelines.md)

### 2.4 Registering the callback

```c
int32_t OH_NativeXComponent_RegisterCallback(OH_NativeXComponent* component,
                                              OH_NativeXComponent_Callback* callback);
```
Returns `OH_NATIVEXCOMPONENT_RESULT_SUCCESS` or `OH_NATIVEXCOMPONENT_RESULT_BAD_PARAMETER`. **Since API 8.**

```cpp
void OnSurfaceCreatedCB(OH_NativeXComponent* component, void* window) {
    OHNativeWindow* nativeWindow = static_cast<OHNativeWindow*>(window);   // <-- the cast you need
    // ... egl setup ...
}
void OnSurfaceChangedCB(OH_NativeXComponent* component, void* window)  { /* ... */ }
void OnSurfaceDestroyedCB(OH_NativeXComponent* component, void* window){ /* ... */ }
void DispatchTouchEventCB(OH_NativeXComponent* component, void* window){ /* ... */ }

// registration
OH_NativeXComponent_Callback renderCallback_;
renderCallback_.OnSurfaceCreated   = OnSurfaceCreatedCB;
renderCallback_.OnSurfaceChanged   = OnSurfaceChangedCB;
renderCallback_.OnSurfaceDestroyed = OnSurfaceDestroyedCB;
renderCallback_.DispatchTouchEvent = DispatchTouchEventCB;
OH_NativeXComponent_RegisterCallback(nativeXComponent, &renderCallback_);
```
Source: [`native-window-guidelines.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/graphics/native-window-guidelines.md),
[`napi-xcomponent-guidelines.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/ui/napi-xcomponent-guidelines.md)

### 2.5 Other useful `OH_NativeXComponent_*` functions

| Signature | 描述 | Since |
|---|---|---|
| `int32_t OH_NativeXComponent_GetXComponentId(OH_NativeXComponent* component, char* id, uint64_t* size)` | 获取ArkUI XComponent的id | 8 |
| `int32_t OH_NativeXComponent_GetXComponentSize(OH_NativeXComponent* component, const void* window, uint64_t* width, uint64_t* height)` | 获取ArkUI XComponent持有的Surface的大小。**单位：vp** | 8 |
| `int32_t OH_NativeXComponent_GetXComponentOffset(OH_NativeXComponent* component, const void* window, double* x, double* y)` | 获取Surface相对其父组件左顶点的偏移量 | 8 |
| `int32_t OH_NativeXComponent_GetTouchEvent(OH_NativeXComponent* component, const void* window, OH_NativeXComponent_TouchEvent* touchEvent)` | 获取调度的触摸事件 | 8 |
| `int32_t OH_NativeXComponent_GetMouseEvent(...)` | 鼠标事件 | 9 |
| `int32_t OH_NativeXComponent_RegisterMouseEventCallback(...)` | 注册鼠标事件回调 | 9 |
| `int32_t OH_NativeXComponent_RegisterFocusEventCallback(...)` / `..._RegisterKeyEventCallback(...)` / `..._RegisterBlurEventCallback(...)` | 焦点/按键/失焦 | 9/10 |
| `int32_t OH_NativeXComponent_RegisterOnFrameCallback(OH_NativeXComponent* component, void (*callback)(OH_NativeXComponent* component, uint64_t timestamp, uint64_t targetTimestamp))` | 注册显示更新回调，并使能每帧回调此函数 | **11** |
| `int32_t OH_NativeXComponent_UnregisterOnFrameCallback(OH_NativeXComponent* component)` | 取消注册 | 11 |
| `int32_t OH_NativeXComponent_SetExpectedFrameRateRange(OH_NativeXComponent* component, OH_NativeXComponent_ExpectedRateRange* range)` | 设置帧期望的帧率范围 | 11 |

> ⚠️ `GetXComponentSize` returns width/height in **vp**, not pixels. Multiply by the display density (or use the
> `OH_ArkUI_SurfaceCallback_SetSurfaceChangedEvent` width/height, also vp) before calling `glViewport`.

### 2.6 The modern alternative: `OH_ArkUI_SurfaceHolder` (API 19+)

Huawei documents the migration explicitly and gives two reasons to prefer it
([`napi-xcomponent-guidelines.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/ui/napi-xcomponent-guidelines.md) §OH_NativeXComponent向OH_ArkUI_SurfaceHolder的迁移):

> - OH_NativeXComponent实例生命周期与XComponent组件强相关，开发者如果在XComponent组件销毁后仍然操作该对象将可能出现稳定性问题，造成应用的崩溃。
>   *The OH_NativeXComponent instance's lifetime is tightly coupled to the component; operating on it after the component
>   is destroyed can cause stability problems and app crashes.*
> - OH_NativeXComponent提供的交互事件接口不够丰富，只提供基础的触摸、鼠标、键盘交互接口，开发者若想识别长按、拖拽等高级手势需要自己写识别逻辑。
>   *…only basic touch/mouse/keyboard; advanced gestures (long-press, drag) require hand-written recognition.*

```cpp
// Bind native callbacks to an ArkTS-created XComponent's FrameNode
napi_value PluginManager::BindNode(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string nodeId = value2String(env, args[0]);

    ArkUI_NodeHandle handle;
    OH_ArkUI_GetNodeHandleFromNapiValue(env, args[1], &handle);        // FrameNode -> ArkUI_NodeHandle
    OH_ArkUI_SurfaceHolder *holder = OH_ArkUI_SurfaceHolder_Create(handle);

    auto callback = OH_ArkUI_SurfaceCallback_Create();
    auto render = new EGLRender();
    OH_ArkUI_SurfaceHolder_SetUserData(holder, render);                                  // park your renderer
    OH_ArkUI_SurfaceCallback_SetSurfaceCreatedEvent(callback, OnSurfaceCreatedNative);
    OH_ArkUI_SurfaceCallback_SetSurfaceChangedEvent(callback, OnSurfaceChangedNative);
    OH_ArkUI_SurfaceCallback_SetSurfaceDestroyedEvent(callback, OnSurfaceDestroyedNative);
    OH_ArkUI_SurfaceCallback_SetSurfaceShowEvent(callback, OnSurfaceShowNative);         // API 20
    OH_ArkUI_SurfaceCallback_SetSurfaceHideEvent(callback, OnSurfaceHideNative);         // API 20
    OH_ArkUI_XComponent_RegisterOnFrameCallback(handle, OnFrameCallbackNative);          // per-frame tick
    OH_ArkUI_SurfaceHolder_AddSurfaceCallback(holder, callback);
    return nullptr;
}
```

Callback signatures (all API 19+ except where noted):

```c
void (*onSurfaceCreated)  (OH_ArkUI_SurfaceHolder* surfaceHolder);
void (*onSurfaceChanged)  (OH_ArkUI_SurfaceHolder* surfaceHolder, uint64_t width, uint64_t height); // vp
void (*onSurfaceDestroyed)(OH_ArkUI_SurfaceHolder* surfaceHolder);
void (*onSurfaceShow)     (OH_ArkUI_SurfaceHolder* surfaceHolder);
void (*onSurfaceHide)     (OH_ArkUI_SurfaceHolder* surfaceHolder);
void (*onFrame)           (ArkUI_NodeHandle node, uint64_t timestamp, uint64_t targetTimestamp);   // API 20
```

Getting the window from the holder (replaces the `void* window` callback parameter):

```c
OHNativeWindow* OH_ArkUI_XComponent_GetNativeWindow(OH_ArkUI_SurfaceHolder* surfaceHolder);   // API 19
```

Other holder APIs: `OH_ArkUI_SurfaceHolder_Create/Dispose/SetUserData/GetUserData/AddSurfaceCallback/RemoveSurfaceCallback`,
`OH_ArkUI_SurfaceCallback_Create/Dispose`, `OH_ArkUI_XComponent_SetAutoInitialize/Initialize/Finalize/IsInitialized`,
`OH_ArkUI_XComponent_SetExpectedFrameRateRange/SetNeedSoftKeyboard`,
`OH_ArkUI_XComponent_RegisterOnFrameCallback/UnregisterOnFrameCallback` (API 20).

> `OH_ArkUI_XComponent_SetAutoInitialize(node, bool)`: *"如果autoInitialize值是true，OnSurfaceCreated回调会在挂树时被触发，
> OnSurfaceDestroyed回调会在下树时被触发。autoInitialize默认值是true。"*

`OH_ArkUI_SurfaceHolder` is **API 19**; the typedef `OH_ArkUI_SurfaceHolder` itself is documented as 起始版本 19.

---

## 3. EGL setup — complete working native module

This is the **official, complete** example from
[`napi-xcomponent-guidelines.md` §在Native侧使用NativeWindow进行渲染绘制](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/ui/napi-xcomponent-guidelines.md),
matching the [`NativeXComponentSample`](https://gitcode.com/openharmony/applications_app_samples/tree/master/code/DocsSample/ArkUISample/NativeXComponentSample) sample.
It uses the API 19 `OH_ArkUI_SurfaceHolder` route; §3.6 shows the older `OH_NativeXComponent_Callback` variant.

### 3.1 `EGLConst.h`

```c
// EGLConst.h
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>

const unsigned int LOG_PRINT_DOMAIN = 0xFF00;
const GLuint  PROGRAM_ERROR  = 0;
const GLint   POSITION_ERROR = -1;
const int     DEFAULT_X_POSITION = 0;
const int     DEFAULT_Y_POSITION = 0;
const GLfloat GL_RED_DEFAULT = 0.0, GL_GREEN_DEFAULT = 0.0, GL_BLUE_DEFAULT = 0.0, GL_ALPHA_DEFAULT = 1.0;
const GLint   POINTER_SIZE = 2;
const GLsizei TRIANGLE_FAN_SIZE = 4;
const float   FIFTY_PERCENT = 0.5;
const char    POSITION_NAME[] = "a_position";

const EGLint ATTRIB_LIST[] = {
    EGL_SURFACE_TYPE,    EGL_WINDOW_BIT,
    EGL_RED_SIZE,        8,
    EGL_GREEN_SIZE,      8,
    EGL_BLUE_SIZE,       8,
    EGL_ALPHA_SIZE,      8,
    EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
    EGL_NONE};

const EGLint CONTEXT_ATTRIBS[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};

const char VERTEX_SHADER[] =
    "#version 300 es\n"
    "layout(location = 0) in vec4 a_position;\n"
    "layout(location = 1) in vec4 a_color;   \n"
    "out vec4 v_color;                       \n"
    "void main()                             \n"
    "{                                       \n"
    "   gl_Position = a_position;            \n"
    "   v_color = a_color;                   \n"
    "}                                       \n";

const char FRAGMENT_SHADER[] =
    "#version 300 es\n"
    "precision mediump float;                  \n"
    "in vec4 v_color;                          \n"
    "out vec4 fragColor;                       \n"
    "void main()                               \n"
    "{                                         \n"
    "   fragColor = v_color;                   \n"
    "}                                         \n";
```

### 3.2 `EGLRender.h`

```c
// EGLRender.h
#include "EGLConst.h"
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <EGL/eglplatform.h>
#include <GLES3/gl3.h>
#include <string>

class EGLRender {
public:
    bool SetUpEGLContext(void *window);
    void SetEGLWindowSize(int width, int height);
    void DrawStar(bool drawColor);
    void DestroySurface();

    std::string xcomponentId;
    EGLNativeWindowType eglWindow_;

    EGLDisplay eglDisplay_ = EGL_NO_DISPLAY;
    EGLConfig  eglConfig_  = EGL_NO_CONFIG_KHR;
    EGLSurface eglSurface_ = EGL_NO_SURFACE;
    EGLContext eglContext_ = EGL_NO_CONTEXT;
    GLuint     program_;
    int        width_  = 0;
    int        height_ = 0;

private:
    GLint PrepareDraw();
    bool  ExecuteDraw(GLint position, const GLfloat *color, const GLfloat shapeVertices[]);
};
```

### 3.3 `EGLRender::SetUpEGLContext` — the whole EGL dance

```cpp
bool EGLRender::SetUpEGLContext(void *window)
{
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_PRINT_DOMAIN, "EGLRender", "EglContextInit execute");
    eglWindow_ = (EGLNativeWindowType)(window);          // <-- void* window IS the OHNativeWindow*

    // 1) display
    eglDisplay_ = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (eglDisplay_ == EGL_NO_DISPLAY) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_PRINT_DOMAIN, "EGLRender", "eglGetDisplay: unable to get EGL display");
        return false;
    }

    // 2) initialize
    EGLint majorVersion;
    EGLint minorVersion;
    if (!eglInitialize(eglDisplay_, &majorVersion, &minorVersion)) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_PRINT_DOMAIN, "EGLRender",
                     "eglInitialize: unable to get initialize EGL display");
        return false;
    }

    // 3) choose config
    const EGLint maxConfigSize = 1;
    EGLint numConfigs;
    if (!eglChooseConfig(eglDisplay_, ATTRIB_LIST, &eglConfig_, maxConfigSize, &numConfigs)) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_PRINT_DOMAIN, "EGLRender", "eglChooseConfig: unable to choose configs");
        return false;
    }

    // 4) create window surface  (note: native window passed straight through)
    eglSurface_ = eglCreateWindowSurface(eglDisplay_, eglConfig_, eglWindow_, NULL);
    if (eglSurface_ == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_PRINT_DOMAIN, "EGLRender",
                     "eglCreateWindowSurface: unable to create surface");
        return false;
    }

    // 5) create context
    eglContext_ = eglCreateContext(eglDisplay_, eglConfig_, EGL_NO_CONTEXT, CONTEXT_ATTRIBS);

    // 6) make current
    if (!eglMakeCurrent(eglDisplay_, eglSurface_, eglSurface_, eglContext_)) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_PRINT_DOMAIN, "EGLRender", "eglMakeCurrent failed");
        return false;
    }

    // 7) build program
    program_ = CreateProgram(VERTEX_SHADER, FRAGMENT_SHADER);
    if (program_ == PROGRAM_ERROR) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_PRINT_DOMAIN, "EGLRender", "CreateProgram: unable to create program");
        return false;
    }
    return true;
}
```

Draw + present:

```cpp
GLint EGLRender::PrepareDraw()
{
    if ((eglDisplay_ == nullptr) || (eglSurface_ == nullptr) || (eglContext_ == nullptr) ||
        (!eglMakeCurrent(eglDisplay_, eglSurface_, eglSurface_, eglContext_))) {
        return POSITION_ERROR;
    }
    glViewport(DEFAULT_X_POSITION, DEFAULT_Y_POSITION, width_, height_);
    glClearColor(GL_RED_DEFAULT, GL_GREEN_DEFAULT, GL_BLUE_DEFAULT, GL_ALPHA_DEFAULT);
    glClear(GL_COLOR_BUFFER_BIT);
    glUseProgram(program_);
    return glGetAttribLocation(program_, POSITION_NAME);
}

void EGLRender::DrawStar(bool drawColor)
{
    GLint position = PrepareDraw();
    if (position == POSITION_ERROR) { return; }
    /* ... build shapeVertices ... */
    ExecuteDraw(position, color, shapeVertices);

    glFlush();
    glFinish();
    if (!eglSwapBuffers(eglDisplay_, eglSurface_)) {          // <-- present
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_PRINT_DOMAIN, "EGLRender", "Draw FinishDraw failed");
        return;
    }
}

void EGLRender::SetEGLWindowSize(int width, int height) { width_ = width; height_ = height; }

void EGLRender::DestroySurface()
{
    if ((eglDisplay_ == nullptr) || (eglSurface_ == nullptr) || (!eglDestroySurface(eglDisplay_, eglSurface_))) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0xff00, "EGLRender", "Release eglDestroySurface failed");
    }
    if ((eglDisplay_ == nullptr) || (eglContext_ == nullptr) || (!eglDestroyContext(eglDisplay_, eglContext_))) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0xff00, "EGLRender", "Release eglDestroySurface failed");
    }
    if ((eglDisplay_ == nullptr) || (!eglTerminate(eglDisplay_))) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0xff00, "EGLRender", "Release eglDestroySurface failed");
    }
    eglDisplay_ = EGL_NO_DISPLAY;
    eglSurface_ = EGL_NO_SURFACE;
    eglContext_ = EGL_NO_CONTEXT;
}
```

> **Note on `eglChooseConfig`**: the official sample passes `maxConfigSize = 1` and a single `EGLConfig*` — this is
> slightly unusual (the EGL spec expects an array), but it is what the shipped sample does and it works because the
> driver writes `numConfigs` and at most 1 config.

### 3.4 Wiring the callbacks

```cpp
void OnSurfaceCreatedNative(OH_ArkUI_SurfaceHolder *holder)
{
    auto window = OH_ArkUI_XComponent_GetNativeWindow(holder);      // get native window
    auto render = reinterpret_cast<EGLRender*>(OH_ArkUI_SurfaceHolder_GetUserData(holder));
    render->SetUpEGLContext(window);                                // init EGL
}

void OnSurfaceChangedNative(OH_ArkUI_SurfaceHolder *holder, uint64_t width, uint64_t height)
{
    EGLRender* render = reinterpret_cast<EGLRender*>(OH_ArkUI_SurfaceHolder_GetUserData(holder));
    render->SetEGLWindowSize(width, height);                        // resize draw area
    render->DrawStar(true);                                         // draw
}

void OnSurfaceDestroyedNative(OH_ArkUI_SurfaceHolder *holder)
{
    EGLRender* render = reinterpret_cast<EGLRender*>(OH_ArkUI_SurfaceHolder_GetUserData(holder));
    render->DestroySurface();                                       // tear EGL down
}

void OnFrameCallbackNative(ArkUI_NodeHandle node, uint64_t timestamp, uint64_t targetTimestamp)
{
    /* per-frame tick; runs on UI thread — keep it short */
}
```

### 3.5 NAPI module registration skeleton

```cpp
// napi_init.cpp
#include <hilog/log.h>
#include "common/common.h"
#include "manager/plugin_manager.h"

namespace NativeXComponentSample {
EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    if ((env == nullptr) || (exports == nullptr)) { return nullptr; }

    napi_property_descriptor desc[] = {
        {"bindNode",         nullptr, PluginManager::BindNode,         nullptr, nullptr, nullptr, napi_default, nullptr},
        {"unbindNode",       nullptr, PluginManager::UnbindNode,       nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setFrameRate",     nullptr, PluginManager::SetFrameRate,     nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setNeedSoftKeyboard", nullptr, PluginManager::SetNeedSoftKeyboard, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    if (napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc) != napi_ok) {
        return nullptr;
    }
    PluginManager::GetInstance()->Export(env, exports);   // legacy route: unwrap OH_NativeXComponent here
    return exports;
}
EXTERN_C_END

static napi_module nativerenderModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "nativerender",   // MUST equal the XComponent `libraryname` value
    .nm_priv = ((void*)0),
    .reserved = { 0 }
};

extern "C" __attribute__((constructor)) void RegisterModule(void)
{
    napi_module_register(&nativerenderModule);
}
} // namespace NativeXComponentSample
```

> The guide states verbatim: `.nm_modname = "nativerender", // 指定模块名称，对于XComponent相关开发，这个名称必须和ArkTS侧XComponent中libraryname的值保持一致`
> — **the `nm_modname` must match the ArkTS `libraryname`.**

### 3.6 The classic `OH_NativeXComponent_Callback` variant

From the older `ArkTSXComponent` (API 12) sample, where EGL init happens directly in `OnSurfaceCreatedCB`:

```cpp
void PluginRender::InitNativeWindow(OHNativeWindow *window) {
    eglCore_->EglContextInit(window);      // window is already OHNativeWindow*
}
void PluginRender::UpdateNativeWindowSize(int width, int height) {
    eglCore_->UpdateSize(width, height);
}
```
Source: [`ArkTSXComponent/.../render/plugin_render.cpp`](https://gitcode.com/openharmony/applications_app_samples/blob/master/code/BasicFeature/Native/ArkTSXComponent/entry/src/main/cpp/render/plugin_render.cpp)

And how the surface size is obtained there (the `surfaceId` is a `BigInt` on the ArkTS side):

```cpp
// OnSurfaceChanged: OH_NativeXComponent_GetXComponentSize(component, window, &width, &height)
// then UpdateNativeWindowSize(width, height)
```

---

## 4. Build configuration

### 4.1 `entry/build-profile.json5`

```json5
{
  "apiType": "stageMode",
  "buildOption": {
    "externalNativeOptions": {
      "path": "./src/main/cpp/CMakeLists.txt",
      "arguments": "",
      "cppFlags": "",
      "abiFilters": ["arm64-v8a", "armeabi-v7a", "x86_64"]
    }
  },
  "buildOptionSet": [
    {
      "name": "release",
      "nativeLib": { "debugSymbol": { "strip": true, "exclude": [] } }
    }
  ],
  "targets": [
    { "name": "default" },
    { "name": "ohosTest" }
  ]
}
```
Source: [`ArkTSXComponent/entry/build-profile.json5`](https://gitcode.com/openharmony/applications_app_samples/blob/master/code/BasicFeature/Native/ArkTSXComponent/entry/build-profile.json5)

`externalNativeOptions` keys: `path` (CMakeLists path, relative), `arguments`, `cppFlags`, `abiFilters`.
The older `NdkOpenGL` sample omits `abiFilters` entirely — it is optional.

> `x86_64` is required for the **emulator**; `arm64-v8a` for real devices. Add `armeabi-v7a` only if you need 32-bit.

### 4.2 `CMakeLists.txt` (official, from the guide)

```cmake
cmake_minimum_required(VERSION 3.5.0)
project(LCNXComponent2)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/render
                    ${NATIVERENDER_ROOT_PATH}/manager)

add_library(nativerender SHARED
            render/EGLRender.cpp
            manager/plugin_manager.cpp
            napi_init.cpp)

find_library(EGL-lib      EGL)          # -> libEGL.so
find_library(GLES-lib     GLESv3)       # -> libGLESv3.so
find_library(hilog-lib    hilog_ndk.z)  # -> libhilog_ndk.z.so
find_library(libace-lib   ace_ndk.z)    # -> libace_ndk.z.so   (XComponent/ArkUI NDK)
find_library(libnapi-lib  ace_napi.z)   # -> libace_napi.z.so  (NAPI)
find_library(libuv-lib    uv)           # -> libuv.so

target_link_libraries(nativerender PUBLIC
    ${EGL-lib} ${GLES-lib} ${hilog-lib} ${libace-lib} ${libnapi-lib} ${libuv-lib}
    libnative_window.so)
```

`ArkTSXComponent`'s CMakeLists is identical plus `add_definitions(-DOHOS_PLATFORM)`.

Link what you actually need:

| You use | Link |
|---|---|
| EGL | `EGL` |
| OpenGL ES 3.x | `GLESv3` (for ES 2.0 only, `GLESv2`) |
| `OH_LOG_Print` | `hilog_ndk.z` |
| `OH_NativeXComponent_*`, `OH_ArkUI_*`, `ArkUI_NativeNodeAPI_1` | **`libace_ndk.z.so`** (CMake name `ace_ndk.z`) |
| `napi_*` | **`libace_napi.z.so`** (CMake name `ace_napi.z`) |
| `OH_NativeWindow_*`, `OHNativeWindow` functions | `libnative_window.so` |
| `OH_NativeBuffer_*` | `libnative_buffer.so` |
| `OH_NativeVSync_*` | `libnative_vsync.so` |
| `napi_threadsafe_function` / libuv | `uv` |

> ⚠️ Two distinct NAPI-ish libraries: **`libace_napi.z.so`** = NAPI runtime; **`libace_ndk.z.so`** = ArkUI NDK
> (XComponent + native node API). The official guide's example links **both**. `libnapi.so` is not the right name here.

### 4.3 `module.json5`

**No XComponent-specific configuration is required.** Both official samples' `module.json5` files contain only the
standard `module`/`abilities`/`pages`/`skills` blocks — no permission, no metadata, no native-library declaration.
The `.so` produced by CMake is packaged automatically.

Source: [`NdkOpenGL/entry/src/main/module.json5`](https://gitcode.com/openharmony/applications_app_samples/blob/master/code/BasicFeature/Native/NdkOpenGL/entry/src/main/module.json5) ·
[`ArkTSXComponent/entry/src/main/module.json5`](https://gitcode.com/openharmony/applications_app_samples/blob/master/code/BasicFeature/Native/ArkTSXComponent/entry/src/main/module.json5)

### 4.4 TypeScript declarations for the native module

`entry/src/main/cpp/types/libnativerender/Index.d.ts` + an `oh-package.json5` next to it:

```typescript
// Index.d.ts
export const SetSurfaceId: (id: bigint) => void;
export const ChangeSurface: (id: bigint, width: number, height: number) => void;
export const DestroySurface: (id: bigint) => void;
export const ChangeColor: (id: bigint) => void;
export const DrawPattern: (id: bigint) => void;
```
Source: [`ArkTSXComponent/.../types/libnativerender/Index.d.ts`](https://gitcode.com/openharmony/applications_app_samples/blob/master/code/BasicFeature/Native/ArkTSXComponent/entry/src/main/cpp/types/libnativerender/Index.d.ts)

Imported as `import nativeRender from 'libnativerender.so';`.

---

## 5. Newer `XComponentController` APIs (API 12 → 22)

Full list from [`ts-basic-components-xcomponent.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-basic-components-xcomponent.md):

| API | Since | Notes |
|---|---|---|
| `constructor()` | — | `new XComponentController()` |
| `getXComponentSurfaceId(): string` | 9 | surface ID string |
| `setXComponentSurfaceSize(value: {surfaceWidth, surfaceHeight}): void` | 9, **deprecated 12** | use `setXComponentSurfaceRect` |
| `getXComponentContext(): Object` | — | same object as `onLoad`'s first arg |
| `setXComponentSurfaceRect(rect: SurfaceRect): void` | **12** | width/height + offset relative to component top-left |
| `getXComponentSurfaceRect(): SurfaceRect` | **12** | |
| `onSurfaceCreated(surfaceId)` / `onSurfaceChanged(surfaceId, rect)` / `onSurfaceDestroyed(surfaceId)` | **12** | **only when `libraryname` is unset** |
| `startImageAnalyzer(config)` / `stopImageAnalyzer()` | 12 | with `enableAnalyzer(true)` |
| `setXComponentSurfaceRotation(rotationOptions)` / `getXComponentSurfaceRotation()` | 12 | |
| `lockCanvas()` / `unlockCanvasAndPost(canvas)` | **20** | draw with an ArkTS `Canvas` onto the XComponent surface |
| `setXComponentSurfaceConfig(config)` | **22** | e.g. treat surface as non-opaque when rendering |

Component attributes: `enableAnalyzer(boolean)` (12+), `enableSecure(boolean)` (13+), `hdrBrightness(number)` (20+),
`hdrBrightness(number, type?: HdrType)` (24+, with `HdrType { DEFAULT=0, AIHDR=1, EDR=2 }`).

> **API 20 addition worth knowing:** `lockCanvas()` / `unlockCanvasAndPost()` let you draw into the XComponent's
> surface with the **ArkTS 2D Canvas API** — no native code required. Example 3 in the reference doc
> ("使用画布对象在XComponent上绘制内容") demonstrates this. This is 2D drawing only, **not** WebGL.

---

## 6. Driving the render loop

Four documented approaches. Huawei's own guidance picks the frame-callback route.

### 6.1 `OH_NativeXComponent_RegisterOnFrameCallback` / `OH_ArkUI_XComponent_RegisterOnFrameCallback` — **officially recommended**

Huawei has a dedicated guide for this: [`displaysync-xcomponent.md` — 请求自绘制内容绘制帧率](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/graphics/displaysync-xcomponent.md)
(Huawei: `.../harmonyos-guides/displaysync-xcomponent`).

> 对于基于XComponent进行Native开发的业务，可以请求独立的绘制帧率进行内容开发，如游戏、自绘制UI框架对接等场景。
> *For XComponent-based native development you can request an independent render frame rate — e.g. games, custom UI frameworks.*

```c
int32_t OH_NativeXComponent_SetExpectedFrameRateRange(OH_NativeXComponent *component,
                                                      OH_NativeXComponent_ExpectedRateRange *range);
int32_t OH_NativeXComponent_RegisterOnFrameCallback(OH_NativeXComponent *component,
                                                    OH_NativeXComponent_OnFrameCallback *callback);
int32_t OH_NativeXComponent_UnregisterOnFrameCallback(OH_NativeXComponent *component);
```

```cpp
static void TestCallback(OH_NativeXComponent *component, uint64_t timestamp, uint64_t targetTimestamp)
{
    // timestamp: 当前帧到达的时间（单位：纳秒）
    // targetTimestamp: 下一帧预期到达的时间（单位：纳秒）
    int32_t xSize = OH_NativeXComponent_GetXComponentSize(component, nativeWindow, &width, &height);
    if ((xSize == OH_NATIVEXCOMPONENT_RESULT_SUCCESS) && (render != nullptr)) {
        render->Prepare();
        render->Create();
        // ... draw ...
    }
}
OH_NativeXComponent_RegisterOnFrameCallback(nativeXComponent, TestCallback);

OH_NativeXComponent_ExpectedRateRange range = {.min = min, .max = max, .expected = expected};
OH_NativeXComponent_SetExpectedFrameRateRange(component, &range);
```

**Documented caveats (verbatim):**
> - Callback回调函数运行于UI主线程，故涉及UI线程的耗时操作不应运行于回调函数中，以免影响性能。
>   → *The callback runs on the **UI main thread**, so do not run UI-thread-blocking work inside it.*
> - 实例在调用OH_NativeXComponent_RegisterOnFrameCallback后，在不需要进行帧率控制时，应进行OH_NativeXComponent_UnregisterOnFrameCallback操作，避免内存泄漏及性能功耗影响。
>   → *Always unregister when you no longer need frame control, to avoid leaks and power drain.*
> - API version 18之前…如果没有取消注册，在XComponent实例存在期间，能一直收到期望回调。
> - 从API version 18开始…如果没有取消注册，只在XComponent上树期间，能收到期望回调。
>   → *Behaviour change at API 18: callbacks are only delivered while the XComponent is attached to the tree.*

The API 19+ equivalent is `OH_ArkUI_XComponent_RegisterOnFrameCallback(ArkUI_NodeHandle node, void (*callback)(ArkUI_NodeHandle node, uint64_t timestamp, uint64_t targetTimestamp))` plus `OH_ArkUI_XComponent_SetExpectedFrameRateRange(node, OH_NativeXComponent_ExpectedRateRange range)`.

### 6.2 `OH_NativeVSync` + your own `std::thread` — maximum control

Guide: [`native-vsync-guidelines.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/graphics/native-vsync-guidelines.md)
(`#include <native_vsync/native_vsync.h>`, link `libnative_vsync.so`).

```cpp
void RenderEngine::OnVsync(long long timestamp, void *data)
{
    // NOTE: "回调的处理在vsync初始化时创建的线程内"
    //       — runs on the thread created by OH_NativeVSync_Create, NOT the UI thread
    auto renderEngine = reinterpret_cast<RenderEngine *>(data);
    if (renderEngine == nullptr) { return; }
    renderEngine->vSyncCnt_++;
    renderEngine->wakeUpCond_.notify_one();
}

// create
const char* demoName = "NativeImageSample";
nativeVsync_ = OH_NativeVSync_Create(demoName, strlen(demoName));

// request the next frame (re-arm every frame)
wakeUpCond_.wait(lock, [this]() { return wakeUp_ || vSyncCnt_ > 0; });
wakeUp_ = false;
if (vSyncCnt_ > 0) {
    vSyncCnt_--;
    (void)OH_NativeVSync_RequestFrame(nativeVsync_, &RenderEngine::OnVsync, this);
    OH_NativeVSync_GetPeriod(nativeVsync_, &period);
}

// destroy
OH_NativeVSync_Destroy(nativeVsync_);
nativeVsync_ = nullptr;
```

The `.so`-level render-thread skeleton, from
[`NdkNativeImage/.../render/render_engine.cpp`](https://gitcode.com/openharmony/applications_app_samples/blob/master/code/BasicFeature/Native/NdkNativeImage/entry/src/main/cpp/render/render_engine.cpp):

```cpp
void RenderEngine::Start()
{
    if (running_) { return; }
    running_ = true;
    thread_ = std::thread([this]() {
        if (!imageRender_->InitEGL(reinterpret_cast<EGLNativeWindowType>(window_), width_, height_)) { return; }
        if (!InitNativeVsync()) { return; }
        if (!CreateNativeImage()) { return; }
        if (!StartNativeRenderThread()) { return; }
        MainLoop();
        CleanupResources();
    });
}

void RenderEngine::MainLoop()
{
    threadId_ = std::this_thread::get_id();
    while (running_) {
        WaitForNewFrame();                 // blocked on a condvar signalled by OnVsync
        if (!isPaused_) {
            ExecuteRenderTasks();
            UpdateSurfaceImage();          // -> eglSwapBuffers path
        }
    }
}

void RenderEngine::Stop()
{
    if (!running_) { return; }
    running_ = false;
    if (thread_.joinable()) { thread_.join(); }   // join BEFORE destroying EGL resources
    CleanupResources();
}
```

This is the pattern to use when you want **GL work off the UI thread**. Note `Stop()` joins the thread before
`CleanupResources()` destroys the EGL objects — that ordering matters.

### 6.2b `OH_DisplaySoloist` — the **officially designated off-UI-thread** render loop

Guide: [`displaysoloist-native-guidelines.md` — NativeDisplaySoloist开发指导](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/graphics/displaysoloist-native-guidelines.md)

> 如果开发者想在独立线程中实现帧率控制的Native侧业务，可以通过DisplaySoloist来实现，如游戏、自绘制UI框架对接等场景。
> 开发者可以选择多个DisplaySoloist实例共享一个线程，也可以选择每个DisplaySoloist实例独占一个线程。
> *If you want frame-rate-controlled native work on an **independent thread**, use DisplaySoloist — e.g. games, custom UI frameworks. Multiple instances may share a thread, or each may have its own.*

```c
OH_DisplaySoloist* OH_DisplaySoloist_Create(bool useExclusiveThread);
void OH_DisplaySoloist_Destroy(OH_DisplaySoloist *displaySoloist);
int32_t OH_DisplaySoloist_Start(OH_DisplaySoloist *displaySoloist,
                                OH_DisplaySoloist_FrameCallback callback, void *data);
int32_t OH_DisplaySoloist_Stop(OH_DisplaySoloist *displaySoloist);
int32_t OH_DisplaySoloist_SetExpectedFrameRateRange(OH_DisplaySoloist* displaySoloist,
                                                    DisplaySoloist_ExpectedRateRange* range);
```

Header `#include <native_display_soloist/native_display_soloist.h>`, link `libnative_display_soloist.so`.

```cpp
static std::unordered_map<std::string, OH_DisplaySoloist *> g_displaySync;

void ExecuteDisplaySoloist(std::string id, DisplaySoloist_ExpectedRateRange range,
                           bool useExclusiveThread, OH_NativeXComponent *nativeXComponent)
{
    OH_DisplaySoloist *nativeDisplaySoloist = nullptr;
    if (g_displaySync.find(id) == g_displaySync.end()) {
        g_displaySync[id] = OH_DisplaySoloist_Create(useExclusiveThread);   // true = dedicated thread
    }
    nativeDisplaySoloist = g_displaySync[id];
    OH_DisplaySoloist_SetExpectedFrameRateRange(nativeDisplaySoloist, &range);
    OH_DisplaySoloist_Start(nativeDisplaySoloist, TestCallback, nativeXComponent);
}
```
> 如果使用OH_DisplaySoloist_Create创建DisplaySoloist实例时传入的参数useExclusiveThread为true，则OH_DisplaySoloist_FrameCallback以独占线程方式执行，否则以共享线程方式执行。
> Always pair with `OH_DisplaySoloist_Stop` + `OH_DisplaySoloist_Destroy` on page navigation to avoid leaks.

**This is the answer to "should I use my own thread".** Huawei's own
[`displaysync-overview.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/graphics/displaysync-overview.md)
enumerates exactly four frame-rate entry points and assigns them to scenarios:

| Mechanism | Scenario (verbatim) |
|---|---|
| `expectedFrameRateRange` (animation attribute) | 通过配置属性动画/显示动画的帧率属性参数，用于动画的绘制 |
| `displaySync` (ArkTS `@ohos.graphics.displaySync`) | 通过申请一个独立的绘制帧率，用于UI的绘制 |
| **`OH_NativeXComponent_SetExpectedFrameRateRange`** | 通过XComponent在Native侧申请独立的绘制帧率，**用于游戏等自绘制内容的绘制** |
| **`DisplaySoloist`** (NativeVsync) | 通过NativeVsync在Native侧申请独立的绘制帧率，**用于非UI线程的绘制** |

> 开发者设置的期望帧率值不能代表最终实际效果，会受限于系统功耗性能约束和屏幕刷新率硬件能力限制。
> *Requested frame rates are not guaranteed — they are bounded by power/performance policy and the panel's capabilities.*

### 6.3 Plain `std::thread` + `eglSwapBuffers` with no pacing

Works but you must implement your own pacing (sleep, frame budget from `OH_NativeVSync_GetPeriod`, or a condvar).
Without it you will burn power and fight the composer. Prefer `OH_DisplaySoloist` instead of hand-rolling this.

### 6.4 Driving from ArkTS

Two sub-options:
- **`@ohos.graphics.displaySync`** (ArkTS) — documented for ArkTS-side UI/animation drawing, not for native GL.
- **`setInterval` / `AnimatorResult` / `animator`** calling a NAPI function each tick — simplest to write, but every
  frame crosses the ArkTS↔native boundary and runs on the UI thread. Acceptable for low frame rates; not for games.

### 6.5 Verdict

| Scenario | Use | Thread |
|---|---|---|
| Simple per-frame draw, moderate cost, you don't mind the UI thread | **`OH_NativeXComponent_RegisterOnFrameCallback`** | UI main thread (documented) |
| Heavy GL, want a dedicated render thread with system frame pacing | **`OH_DisplaySoloist`** (`useExclusiveThread = true`) | **its own thread** |
| Fine-grained control, you already have a loop | **`OH_NativeVSync` + `std::thread`** (the `NdkNativeImage` pattern) | your thread |
| You already have a game loop / engine | Your own thread; still call `OH_NativeXComponent_SetExpectedFrameRateRange` to declare your target rate | your thread |

**Recommendation:** for a game/renderer, `OH_DisplaySoloist` (dedicated thread) is the officially-designated mechanism;
for a light self-drawing UI, `RegisterOnFrameCallback` is simpler. Both are shown in official samples
(`DisplaySoloist` / `DisplaySync`). Note that `OH_DisplaySoloist_*`, `OH_NativeVSync_*` and `RegisterOnFrameCallback`
are the *only* documented way to get VSync-aligned pacing; a bare `while(true) { draw; swap; }` thread is not.

---

## 7. Limitations and caveats

*(Section completed from the companion research pass; each item sourced.)*

### 7.1 `libraryname` semantics — **does it auto-load the `.so`? Yes.**

- **Definition (official, EN + ZH).** `libraryname` = *"Name of the dynamic library compiled and output by the native
  layer (the corresponding dynamic library does not support cross-module loading). This parameter is effective only
  when type is SURFACE or TEXTURE."*
  ZH: **用Native层编译输出动态库名称（对应的动态库不支持跨模块加载），仅类型为SURFACE或TEXTURE时有效。**
- **The framework loads it; you do not `dlopen` it yourself.** `onLoad` is documented as
  **"插件加载完成时回调事件" / "Triggered when the plugin is loaded."** — i.e. ArkUI has loaded the library named by
  `libraryname` and called your NAPI module's `Init`. There is no `dlopen`/`napi_module_register` call in any official
  sample's ArkTS code; the only registration is the `__attribute__((constructor)) RegisterModule()` in C++.
  The guide states the constructor *"由系统自动调用"* ("is called automatically by the system").
  → **Effectively yes: setting `libraryname` makes ArkUI load the `.so` and `onLoad` signals that it finished.**
- **The name must match `nm_modname`.** The guide annotates this verbatim:
  `.nm_modname = "nativerender", // 指定模块名称，对于XComponent相关开发，这个名称必须和ArkTS侧XComponent中libraryname的值保持一致`
  → The `.so` basename (`libnativerender.so`), the `nm_modname` (`"nativerender"`), and the ArkTS
  `libraryname: 'nativerender'` must all agree.
- **No cross-module loading.** *"对应的动态库不支持跨模块加载"* — the library must be built into and packaged with the
  **same HAP/module** that declares the `XComponent`. You cannot point `libraryname` at another module's `.so`.
- **Setting `libraryname` changes event routing.** Documented:
  > 当配置libraryname参数时，点击事件、触摸事件、挂载卸载事件、按键事件、焦点事件、鼠标事件仅响应C-API侧事件接口。
  > *With `libraryname` set, click / touch / show-hide / key / focus / mouse events respond **only** to the C-API event interfaces.*

  (EN: *"When the `libraryname` parameter is set, … only respond to event APIs on the C API side."*)
- **Setting `libraryname` disables the ArkTS controller lifecycle callbacks.** Each of `onSurfaceCreated`,
  `onSurfaceChanged`, `onSurfaceDestroyed` carries: **仅当XComponent组件未设置libraryname参数时，会进行该回调。**
  / *"The callback is triggered only when the `libraryname` parameter is not set for the `XComponent`."*

> **Practical rule.** Pick **one** wiring:
> **(A)** `{id, type: SURFACE, libraryname}` + native `OH_NativeXComponent_Callback` — ArkTS controller lifecycle
> callbacks are dead and ArkTS input events are dead.
> **(B)** `{type: SURFACE, controller}` with **no** `libraryname` + `XComponentController` callbacks — ArkTS events work,
> but you must feed `surfaceId` to native yourself (e.g. `native.SetSurfaceId(BigInt(surfaceId))`).
> The official `ArkTSXComponent` sample (API 12) uses **(B)**; `NdkOpenGL` (API 10) and the `DisplaySync`/`NativeWindow`
> guides use **(A)**.

### 7.2 Thread-safety: what must happen on the UI thread

**Documented facts:**

1. **`OH_NativeXComponent_RegisterOnFrameCallback` callbacks run on the UI main thread.** Verbatim from
   [`displaysync-xcomponent.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/graphics/displaysync-xcomponent.md):
   > Callback回调函数运行于UI主线程，故涉及UI线程的耗时操作不应运行于回调函数中，以免影响性能。
   > *The callback runs on the UI main thread, so do not run UI-thread-blocking work in it.*

2. **`OH_NativeVSync_FrameCallback` runs on the thread created by `OH_NativeVSync_Create`, not the UI thread.**
   Verbatim from [`native-vsync-guidelines.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/graphics/native-vsync-guidelines.md):
   > OH_NativeVSync_FrameCallback (long long timestamp, void \*data) | 回调函数的形式…**回调的处理在vsync初始化时创建的线程内**。
   > *…the callback is processed on the thread created when VSync was initialized.*

3. **`OH_DisplaySoloist` frame callbacks run on a dedicated/shared thread outside the UI thread**, chosen by the
   `useExclusiveThread` argument — this is the entire point of the API
   ([`displaysoloist-native-guidelines.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/graphics/displaysoloist-native-guidelines.md)):
   > 如果开发者想在独立线程中实现帧率控制的Native侧业务，可以通过DisplaySoloist来实现

4. **ArkUI NDK node operations are UI-thread-bound when the node is *Attached*.** From
   [`ndk-build-on-multi-thread.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/ui/ndk-build-on-multi-thread.md):
   > 在非UI线程调用函数操作Attached节点时，接口返回错误码 ARKUI_ERROR_CODE_NODE_ON_INVALID_THREAD。
   > *Calling these functions on a non-UI thread against an Attached node returns `ARKUI_ERROR_CODE_NODE_ON_INVALID_THREAD`.*

   Note the API 22 change: UI components may now be **created** and have attributes set from any thread, but
   > 必须在UI线程中，把UI组件挂载到UI主树上。
   > *…you must still mount the UI component onto the main UI tree on the UI thread.*

   So: creating an `ArkUI_NodeHandle` for an XComponent from a worker thread is permitted from **API 22+**; the
   `OH_ArkUI_SurfaceHolder_*` / `OH_ArkUI_SurfaceCallback_*` calls that bind it are subject to the Attached-node rule.

5. **Generic ArkUI rule:** [`ndk-build-ui-overview.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/ui/ndk-build-ui-overview.md) —
   *"需要保证相关UI接口调用在应用主线程上调用"* (*"UI interface calls must be made on the application main thread"*).

6. **NAPI from a non-JS thread** (from [`napi-guidelines.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/napi/napi-guidelines.md)
   and [`napi-faq-about-stability.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/napi/napi-faq-about-stability.md)):
   - **`napi_env` is strongly bound to its ArkTS thread** — *"napi_env和ArkTS线程是强绑定的"*. You may not use a
     captured `napi_env` from your render thread.
   - Use **`napi_create_threadsafe_function`**; *"线程安全函数回调的执行仅在创建线程安全函数的ArkTS线程中执行"*
     (the callback executes only on the ArkTS thread that created it) — so it safely marshals back to the UI thread.
   - *"不推荐使用`uv_queue_work`…请使用`napi_threadsafe_function`系列接口"* — prefer threadsafe functions over
     `uv_queue_work`.
   - In an `async_work` `execute_cb`, *"不能使用入参env构造napi_value"* — you cannot build `napi_value`s with the
     passed-in `env`.
   - `napi_load_module` — *"禁止在非主线程当中使用"* (forbidden off the main thread).

**Practical rules:**

| Operation | Thread |
|---|---|
| `OnSurfaceCreated/Changed/Destroyed`, `DispatchTouchEvent` | UI main thread (treat as such; keep short) |
| `RegisterOnFrameCallback` body | UI main thread — **documented** |
| `OH_DisplaySoloist` / `OH_NativeVSync` callback body | dedicated thread — **this is where GL work belongs** |
| `eglMakeCurrent`, GL calls, `eglSwapBuffers` | whatever thread owns the context — **do it all on one thread** |
| `ArkUI_NativeNodeAPI_1` on an Attached node, `OH_ArkUI_SurfaceHolder_*` | UI main thread |
| NAPI calls into ArkTS from a render thread | `napi_create_threadsafe_function` / `napi_call_threadsafe_function`; a raw `napi_env` is **not** valid off its ArkTS thread |

> **What is *not* documented (be aware when you rely on it).** The docs never explicitly state the thread on which
> `OnSurfaceCreated` / `OnSurfaceChanged` / `OnSurfaceDestroyed` / `DispatchTouchEvent` are invoked. The only explicit
> statement is for the *per-frame* callback (*"Callback回调函数运行于UI主线程"*); the rest is covered by the generic
> "UI interfaces must be called on the main thread" rule. In practice all official samples treat them as UI-thread,
> and developer measurements on the Huawei forum report identical thread IDs (UI thread). **Design for UI-thread, but
> do not build a correctness dependency on it without verifying on your target device.**
>
> Likewise, **`OH_ArkUI_SurfaceHolder` / `OH_ArkUI_SurfaceCallback` carry no documented thread restriction at all** in
> `capi-native-interface-xcomponent-h.md` — the API 19 docs are silent on threading.

> ⚠️ **EGL contexts are not thread-safe and are current-to-one-thread.** Create the context, make it current, draw,
> and swap on the *same* thread. If you create the context in `OnSurfaceCreated` (UI thread) but draw on a render
> thread, you must either (a) create a second context on the render thread sharing objects, or (b) use
> `eglMakeCurrent` on the render thread only and never touch GL from the UI thread. The official samples that use a
> render thread (`NdkNativeImage`) do all of `InitEGL` → draw → swap inside the spawned thread.
>
> Note: **no HarmonyOS doc blesses calling `eglSwapBuffers` off the UI thread** — every doc occurrence of
> `eglSwapBuffers` is in UI-thread sample code. The *architecture* (render thread) is officially supported
> (`OH_DisplaySoloist`, "drawing of non-UI threads"), and `native-common-mistakes.md` prescribes the handoff protocol
> (§7.4), but the GL call itself is not explicitly addressed.

### 7.3 Lifetime rules — two documented use-after-free patterns

Huawei maintains an official crash-analysis page,
[`ui/arkts-stability-crash-issues.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/ui/arkts-stability-crash-issues.md),
covering **exactly these two** XComponent UAF bugs.

**(1) The `OH_NativeXComponent` object is freed by the system — stop using it after `onSurfaceDestroy`.**
> `OH_NativeXComponent`使用裸指针管理。应用侧持有其裸指针。如果在其生命周期结束后仍然调用相关接口，会导致Use-After-Free问题。
> 系统通过`onSurfaceDestroy`回调通知应用`OH_NativeXComponent`已销毁。**应用必须确保在`onSurfaceDestroy`回调执行完毕后不再调用`OH_NativeXComponent`相关接口。**
>
> *"`OH_NativeXComponent` is managed via a raw pointer… after its lifetime ends, calling related APIs causes a
> use-after-free. The system signals destruction via the `onSurfaceDestroy` callback; **the app must not call any
> `OH_NativeXComponent` API after `onSurfaceDestroy` completes.**"*

Crash signature: stack shows `libace_ndk.z.so(OH_NativeXComponent::GetXComponentId(...))` (or similar
`OH_NativeXComponent::XXX`) with the next frame in your own `.so`.

**(2) The `OH_NativeXComponent_Callback` struct is stored as a raw pointer — it must outlive the component.**
> 应用通过`OH_NativeXComponent_RegisterCallback`接口注册的`OH_NativeXComponent_Callback`回调函数对象**以裸指针形式保存在`XComponentPattern`对象中**。这些回调的生命周期由应用控制。如果应用提前销毁了`OH_NativeXComponent_Callback`回调函数对象，将导致裸指针指向非法内存，引发Use-After-Free问题。
> `onSurfaceDestroy`回调是`XComponentPattern`销毁时调用的**最后一个回调**…因此，应用必须确保在`onSurfaceDestroy`回调执行前，这些回调是有效的。

Crash signature: last frame is one of `XComponentPattern::OnSurfaceCreated / OnSurfaceChanged / OnSurfaceDestroyed /
DispatchTouchEvent`, and `#00`'s `pc` is a bogus address whose low bits match the fault address — i.e. a bad function
pointer jump.

> ⚠️ **Practical consequence:** never pass a **stack-local or short-lived** `OH_NativeXComponent_Callback` to
> `OH_NativeXComponent_RegisterCallback`. Make it a member of an object that lives until `OnSurfaceDestroyed` has
> returned (the official samples use a `renderCallback_` member). Likewise, do not `delete` your renderer from a
> teardown path that can run *before* `OnSurfaceDestroyed`.

### 7.4 Teardown — the authoritative version

Source: [`graphics/native-common-mistakes.md` — 图形缓冲区常见稳定性问题](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/graphics/native-common-mistakes.md)
§NativeWindow生命周期问题. This is the doc to cite for crash triage.

**The refcount rule (restated with the failure mode):**
> 从XComponent组件获取的NativeWindow，抛向子线程使用，XComponent组件销毁时将NativeWindow引用计数减一，若减为0析构后，子线程仍在使用会导致崩溃。
> *"A NativeWindow obtained from an XComponent and thrown to a worker thread: when the XComponent is destroyed the
> count is decremented, and if it reaches 0 the object is destructed while the worker thread is still using it → crash."*

**Two officially prescribed fixes — pick one:**

**Fix A — take your own reference before handing it to a thread:**
```cpp
void OnSurfaceCreatedCB(OH_NativeXComponent* component, void* window)
{
    uint64_t width = 0, height = 0;
    OH_NativeXComponent_GetXComponentSize(component, window, &width, &height);
    OHNativeWindow* nativewindow_ = static_cast<OHNativeWindow*>(window);

    // 抛任务前将nativeWindow引用计数加一
    OH_NativeWindow_NativeObjectReference(nativewindow_);
    NativeRender::GetInstance()->SetNativeWindow(nativewindow_, width, height);
}

void OnSurfaceDestroyedCB(OH_NativeXComponent* component, void* window)
{
    // 通知子线程停止，因为前面有对引用计数加一，OnSurfaceDestroyedCB结束时不会释放
    // 当子线程使用完毕后执行 OH_NativeWindow_NativeObjectUnreference(nativewindow_) 对引用计数减一
    NativeRender::GetInstance()->Release();
}
```

**Fix B — stop and join the render thread inside the callback:**
```cpp
void OnSurfaceDestroyedCB(OH_NativeXComponent* component, void* window)
{
    NativeRender::GetInstance()->Release();
    // 通知子线程停止后等待子线程任务结束再结束OnSurfaceDestroyedCB
    renderThread.join();
}
```

**Do NOT call `OH_NativeWindow_DestroyNativeWindow()` on a window you got from the XComponent lifecycle.** The doc's
counter-example:
```cpp
// 错误：未对nativewindow_引用计数加一的情况下调用DestroyNativeWindow会使nativewindow_提前释放，导致崩溃
OH_NativeWindow_DestroyNativeWindow(nativewindow_);
```
> *"Calling `DestroyNativeWindow` without having incremented the reference count causes the NativeWindow to be released
> prematurely, leading to a crash."*

**Crash signatures to grep for** (all in `libsurface.z.so`):
```
libsurface.z.so(OH_NativeWindow_DestroyNativeWindow())
libsurface.z.so(OH_NativeWindow_NativeWindowHandleOpt)
libsurface.z.so(OH_NativeWindow_NativeObjectUnreference())
```
Also: after any destroy, immediately null your pointers (`image_ = nullptr; nativewindow_ = nullptr;`) to avoid
wild-pointer reuse.

**Full teardown order:**

1. Stop the render thread and either take a reference (Fix A) or `join()` it (Fix B) — **inside
   `OnSurfaceDestroyed`**.
2. `eglDestroySurface(eglDisplay_, eglSurface_)`
3. `eglDestroyContext(eglDisplay_, eglContext_)`
4. `eglTerminate(eglDisplay_)`
5. Reset handles to `EGL_NO_DISPLAY` / `EGL_NO_SURFACE` / `EGL_NO_CONTEXT`
6. Drop your `OHNativeWindow*` reference (`OH_NativeWindow_NativeObjectUnreference` if you took one); never
   `OH_NativeWindow_DestroyNativeWindow` on it.
7. Do not touch `OH_NativeXComponent*` after this callback returns.

For the API 19 `OH_ArkUI_SurfaceHolder` route, the sample's `UnbindNode` shows:

```cpp
OH_ArkUI_XComponent_UnregisterOnFrameCallback(node);   // if registered
OH_ArkUI_AccessibilityProvider_Dispose(provider_);     // if created
OH_ArkUI_SurfaceHolder_RemoveSurfaceCallback(holder, callback);
OH_ArkUI_SurfaceCallback_Dispose(callback);
delete render;                                          // your user data
OH_ArkUI_SurfaceHolder_Dispose(holder);
nodeAPI->disposeNode(node);
```

> **A second, community-reported crash cause** (not in official docs — marked uncertain): caching render instances
> keyed by the static ArkTS `id` across Surface lifecycles. The `id` is constant across surface recreation, so a stale
> instance can be reused after teardown. The `ArkTSXComponent` sample sidesteps this by keying on the `surfaceId`
> instead, and by making release synchronous rather than posting it asynchronously.

### 7.5 DevEco Studio Previewer — **officially unsupported. Confirmed twice.**

**Evidence 1 — the XComponent component reference itself.** Top of the Examples section
([`ts-basic-components-xcomponent.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-basic-components-xcomponent.md), line 726):

> ## 示例
> **示例效果请以真机运行为准，当前DevEco Studio预览器不支持。**
> *"Example results should be verified on a real device; the current DevEco Studio Previewer does not support [them]."*

That note heads **all** XComponent examples, which include the native render-function implementations.

**Evidence 2 — the DevEco Studio "界面预览" (UI Previewer) guide's limitation list**, which is explicit:

> - **"Richtext、Web、Video、XComponent组件不支持预览。"**
>   *"Richtext, Web, Video and XComponent components do not support preview."*
> - **"不支持调用C++库的预览。"**
>   *"Previewing that calls C++ libraries is not supported."*
> - "预览器功能依赖于电脑显卡的OpenGL版本，OpenGL版本要求为3.2及以上。"
>   *"The Previewer depends on your PC's GPU OpenGL version; OpenGL 3.2+ is required."*
> - "预览时将不会运行Ability生命周期。" / "部分API不支持预览，如Ability、App、MultiMedia等模块。"

Official page: <https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/ide-previewer-arkts-js-V5> ·
debug constraint page: <https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-previewer-debug#section24576302190>

**Evidence 3 — Huawei staff reply on the official forum** confirms the omission is deliberate:

> 在预览器的使用约束中说明了"不支持c++调试"，且在预览器中有明确提示，所以在OpenGL ES的API文档中不会明确指出预览器不支持。
> *"The Previewer's usage constraints state 'C++ debugging is not supported' and the Previewer shows a clear prompt, so
> the OpenGL ES API docs do not explicitly call out that the Previewer does not support it."*

**Conclusion:** XComponent custom EGL/OpenGL ES rendering **cannot** be previewed in DevEco Studio. Develop and verify
on the **emulator (`x86_64` ABI)** or a **real device (`arm64-v8a`)**. This is also why `abiFilters` in
§4.1 matters.

> **Note on doc provenance:** the OpenHarmony upstream file
> [`ui-ide-previewer.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/ui/ui-ide-previewer.md)
> contains **no** such limitation list (only a generic "preview is for reference; real device prevails"). The
> limitation list lives only in the **DevEco Studio (closed-source) guide**. Quote it from there, not from OpenHarmony.

**Two practical nuances:**

- **The Previewer API whitelist excludes XComponent but includes `Canvas` / `OffscreenCanvas`.** So pure-ArkTS 2D
  drawing *is* previewable — the ArkTS `Canvas` route is your only previewable graphics path. Design your iteration
  loop around that: prototype visuals on `Canvas`, then port to XComponent + GL for production performance.
- *(Community-reported, not official)* The Previewer **does load your `.so` once and then caches it** — editing a
  `.cpp` may appear to have no effect until you delete the `.preview` directory. Reports of `EGL_NO_DISPLAY` in the
  Previewer are consistent with this.
  Source: [DevEcoStudio的Previewer不支持so的更新？](https://developer.huawei.com/consumer/cn/forum/topic/0208155991450620200).
- I found **no** official statement that XComponent renders *black* in the Previewer — only that it is unsupported.
  Don't assert the specific failure mode.

### 7.6 Other documented constraints

- **Transparency/composition:** 当开发者传输的绘制内容包含透明元素时，Surface区域的显示效果会与下方内容进行合成展示。
  If your content has alpha, it is composited with what's beneath; a fully transparent surface over a black
  `XComponent` background shows as black.
- **`SURFACE` attribute restrictions:** API ≤17 does not support dynamic attribute setting, custom drawing, background
  (except `backgroundColor`), image effects (except `shadow`), `maskShape`, `foregroundEffect`. API 18+ expands/changes
  the unsupported list (`background`, `foregroundColor`, `animation`, `gesture`, `clip`, `geometryTransition`,
  `bindPopup`, …). `renderFit` defaults to `RenderFit.RESIZE_FILL` for TEXTURE and SURFACE; for SURFACE before API 18
  only `RESIZE_FILL` was allowed.
- **`enableSecure` / `hdrBrightness`** do not work on XComponents created via the ArkUI NDK interfaces, and only apply
  to `SURFACE`.
- **`enableAnalyzer`** cannot be combined with `overlay` (the `CustomBuilder` in `overlay` stops working).
- **`GetXComponentSize` returns vp**, not px.
- **`setXComponentSurfaceRect`** can move/resize the surface independently of the component.

---

## 8. WebGL from ArkTS? — **No. Confirmed.**

**Your belief is correct: the ArkTS `Canvas` is 2D-only, and there is no WebGL/WebGL2 context available directly in ArkTS.**
WebGL in HarmonyOS exists **only inside the `Web` component (ArkWeb)**. For real GL from ArkTS you must use
`XComponent` + native EGL/GLES (this document), or embed a `Web` component running a WebGL page.

### 8.1 ArkTS `Canvas` is 2D-only — evidence

The ArkUI ArkTS graphics API surface contains exactly two rendering-context types:

| Type | Doc | Description |
|---|---|---|
| `CanvasRenderingContext2D` | [`ts-canvasrenderingcontext2d.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-canvasrenderingcontext2d.md) | "CanvasRenderingContext2D对象与Canvas组件绑定后，可在Canvas组件上绘制，绘制对象可以是形状、文本、图片等。" |
| `OffscreenCanvasRenderingContext2D` | [`ts-offscreencanvasrenderingcontext2d.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-offscreencanvasrenderingcontext2d.md) | "…离屏绘制使用**CPU**进行绘制，绘制速度较慢…" |

There is **no** `WebGLRenderingContext`, `WebGL2RenderingContext`, or `CanvasRenderingContextWebGL` type anywhere in the
ArkUI ArkTS reference. I grepped the ArkUI `arkui-ts` reference directory for `webgl` (case-insensitive): **zero hits**
in the Canvas documents and zero WebGL context types.

The ArkTS 2D canvas is also **CPU-drawn** for offscreen work — the doc says so explicitly — which further rules out a
GPU-API interpretation.

> There *is* an API 20 `XComponentController.lockCanvas()` / `unlockCanvasAndPost(canvas)` pair that lets you draw onto
> an XComponent surface with the ArkTS **2D** `Canvas` API — but that is still 2D only, not WebGL.

The only "3D-ish" ArkTS option is **ArkGraphics 3D** — `@ohos.graphics.scene`, **available since API 12**
(`SystemCapability.ArkUi.Graphics3D`). Per
[`js-apis-scene.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-arkgraphics3d/js-apis-scene.md)
it provides:

| Module | What it gives you |
|---|---|
| `Scene` | glTF model loading, scene element + resource creation |
| `SceneNode` | tree-structured 3D scene; manipulate node properties / hierarchy |
| `SceneType` | vectors, quaternions, etc. |
| `SceneResources` | 材质、图片、**着色器** (materials, images, shaders) as *resources* |
| `ScenePostProcessSettings` | tone mapping and other post-processing |

**This is a declarative scene-graph API, not a programmable GL pipeline.** You describe a scene (load a glTF, set
materials/shader resources, move nodes) rather than issuing `glDrawArrays`/`glUseProgram` yourself. It is *not* a
substitute for EGL/GLES when you need arbitrary GLSL, custom render passes, or frame-exact control. **For raw shader
control, use XComponent + EGL.** *(Confirmed from the API reference above; I did not stress-test its practical limits.)*

### 8.2 WebGL lives in the `Web` component (ArkWeb)

**Direct documentary confirmation** — `SecurityParams.disableWebGL`
([`arkts-apis-webview-SecurityParams.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-arkweb/arkts-apis-webview-SecurityParams.md)):

> **disableWebGL** | boolean | 是否禁用WebGL。true表示禁用，false表示不禁用。**默认值：false**。
> **WebGL允许JavaScript直接调用GPU驱动进行渲染**，攻击者可能利用底层驱动漏洞实现沙箱逃逸或远程代码执行…
> 禁用后无法进行3D渲染，部分2D画布退回到CPU渲染，可能帧率下降。

Gloss: *"Whether to disable WebGL. Default `false` (i.e. enabled). **WebGL lets JavaScript call the GPU driver
directly for rendering**; … after disabling, 3D rendering is impossible and some 2D canvases fall back to CPU
rendering, possibly with reduced frame rate."*

Key implications:
- WebGL is **on by default** in ArkWeb (`disableWebGL` defaults to `false`) — no extra flag needed to use it.
- It is a **Web-engine (Chromium/ArkWeb) capability**, not an ArkUI/ArkTS one.
- The toggle lives on `webview.WebviewController.enableAdvancedSecurityMode({...})`, and (docs note) **must be called
  before `initializeWebEngine()`** or it has no effect.

Usage shape:

```typescript
import { webview } from '@kit.ArkWeb';

@Entry
@Component
struct WebGLPage {
  controller: webview.WebviewController = new webview.WebviewController();

  build() {
    Web({ src: $rawfile('webgl_demo.html'), controller: this.controller })
      .javaScriptAccess(true)      // required for the page's JS (and thus WebGL) to run
      .onControllerAttached(() => {
        // page is loaded; its <canvas>.getContext('webgl2') works
      })
  }
}
```

### 8.3 Is there a way to hand an XComponent Surface to the `Web` component?

**No documented mechanism.** I found no API that binds an XComponent `surfaceId`/`OHNativeWindow` to a `Web`
component's rendering target in the OpenHarmony docs. The two are separate rendering paths: ArkWeb renders on its own,
and there is a documented "同层渲染" (same-layer rendering) feature for **system components embedded inside a Web page**
(as described generically in [`web-component-overview.md`](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/web/web-component-overview.md)),
but that is the reverse direction (native component inside web content), not "WebGL into my XComponent". *(Marked as
"not found in docs" rather than "explicitly prohibited".)*

### 8.4 Decision table

| You want | Use |
|---|---|
| Custom GLSL shaders, full GPU control, 3D, game loop | **`XComponent` (SURFACE) + native EGL/GLES** — this document |
| WebGL/three.js/Babylon.js code you already have, or a WebGL page | **`Web` component** loading HTML with `getContext('webgl2')` |
| 2D shapes/text/images | ArkTS `Canvas` + `CanvasRenderingContext2D` (CPU/2D) |
| 2D drawing onto an XComponent surface without native code | `XComponentController.lockCanvas()` / `unlockCanvasAndPost()` (API 20+, 2D only) |
| High-level 3D scene, no custom shaders | ArkGraphics 3D / `@ohos.graphics.scene` |

---

## 9. Official OpenHarmony sample applications

**Yes.** The repository is **`openharmony/applications_app_samples`**:
<https://gitee.com/openharmony/applications_app_samples> (mirror: <https://gitcode.com/openharmony/applications_app_samples>)

| Sample | Path | API | What it shows |
|---|---|---|---|
| **NdkOpenGL** — "OpenGL三棱椎" (OpenGL tetrahedron) | [`code/BasicFeature/Native/NdkOpenGL`](https://gitcode.com/openharmony/applications_app_samples/tree/master/code/BasicFeature/Native/NdkOpenGL) | 10 | **The canonical XComponent + OpenGL ES 3.0 sample.** Draws a rotating 3D tetrahedron, touch-drag to rotate. Uses `OH_NativeXComponent_Callback` + `OH_NativeXComponent_GetXComponentId` + `EGLNativeWindowType`. ⚠️ Its own README says its XComponent API usage **已停止演进** (no longer evolving) and points at `ArkTSXComponent`. |
| **ArkTSXComponent** | [`code/BasicFeature/Native/ArkTSXComponent`](https://gitcode.com/openharmony/applications_app_samples/tree/master/code/BasicFeature/Native/ArkTSXComponent) | 12 | **The currently-recommended XComponent + EGL/GLES sample.** Controller-driven (`XComponentController.onSurfaceCreated/Changed/Destroyed`), `BigInt(surfaceId)` passed to native, draw a star + change colour. CMakeLists links `EGL GLESv3 hilog_ndk.z ace_ndk.z ace_napi.z uv libnative_window.so`. |
| **XComponent3D** | [`code/BasicFeature/Native/XComponent3D`](https://gitcode.com/openharmony/applications_app_samples/tree/master/code/BasicFeature/Native/XComponent3D) | 10 | 3D rendering on XComponent. |
| **NdkXComponent** | [`code/BasicFeature/Native/NdkXComponent`](https://gitcode.com/openharmony/applications_app_samples/tree/master/code/BasicFeature/Native/NdkXComponent) | — | XComponent created driver-side via NDK. |
| **NdkVulkan** | [`code/BasicFeature/Native/NdkVulkan`](https://gitcode.com/openharmony/applications_app_samples/tree/master/code/BasicFeature/Native/NdkVulkan) | — | Vulkan on XComponent (alternative to GLES). |
| **NativeXComponentSample** | [`code/DocsSample/ArkUISample/NativeXComponentSample`](https://gitcode.com/openharmony/applications_app_samples/tree/master/code/DocsSample/ArkUISample/NativeXComponentSample) | **19** | **The API 19 `OH_ArkUI_SurfaceHolder` reference implementation** backing §3 of this report. Also covers accessibility, variable frame rate, soft keyboard. |
| **NativeXComponent** | [`code/BasicFeature/Native/NativeXComponent`](https://gitcode.com/openharmony/applications_app_samples/tree/master/code/BasicFeature/Native/NativeXComponent) | 19 | All five XComponent development paradigms (declarative + controller, declarative + SurfaceHolder, typeNode + controller, typeNode + SurfaceHolder, pure NDK + SurfaceHolder). |
| **DisplaySync** | [`code/DocsSample/ArkGraphics2D/DisplaySync`](https://gitcode.com/openharmony/applications_app_samples/tree/master/code/DocsSample/ArkGraphics2D/DisplaySync) | 14 | `OH_NativeXComponent_RegisterOnFrameCallback` + `SetExpectedFrameRateRange` — two XComponents at 30 and 120 fps. |
| **NdkNativeImage** | [`code/BasicFeature/Native/NdkNativeImage`](https://gitcode.com/openharmony/applications_app_samples/tree/master/code/BasicFeature/Native/NdkNativeImage) | 12 | `OH_NativeVSync` + dedicated `std::thread` render loop + `MainLoop()`. The reference for §6.2. |
| **VideoPlayer** | [`code/DocsSample/ArkUISample/VideoPlayer`](https://gitcode.com/openharmony/applications_app_samples/tree/master/code/DocsSample/ArkUISample/VideoPlayer) | — | Feeding `surfaceId` to `AVPlayer` (the "render on ArkTS side" path). |

**Sparse checkout of just the OpenGL sample:**

```bash
git init
git config core.sparsecheckout true
echo code/BasicFeature/Native/NdkOpenGL/ > .git/info/sparse-checkout
git remote add origin https://gitee.com/openharmony/applications_app_samples.git
git pull origin master
```
(verbatim from the sample's README)

**Huawei Codelab** (official, guided): 基于XComponent组件实现图像绘制功能 —
<https://developer.huawei.com/consumer/cn/codelabsPortal/carddetails/tutorials_NEXT-Xcomponent>

---

## Appendix A — Verified source files

All downloaded to `research/raw/` in this workspace:

| Local file | Upstream |
|---|---|
| `napi-xcomponent-guidelines.md` | `zh-cn/application-dev/ui/napi-xcomponent-guidelines.md` |
| `ts-basic-components-xcomponent.md` | `zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-basic-components-xcomponent.md` |
| `capi-native-interface-xcomponent-h.md` | `zh-cn/application-dev/reference/apis-arkui/capi-native-interface-xcomponent-h.md` |
| `capi-oh-nativexcomponent-native-xcomponent-oh-nativexcomponent-callback.md` | ditto, struct page |
| `native-window-guidelines.md` / `native-buffer-guidelines.md` / `native-vsync-guidelines.md` | `zh-cn/application-dev/graphics/…` |
| `displaysync-xcomponent.md` | `zh-cn/application-dev/graphics/displaysync-xcomponent.md` |
| `native-common-mistakes.md` | `zh-cn/application-dev/graphics/native-common-mistakes.md` — **crash triage + refcount protocol** |
| `arkts-stability-crash-issues.md` (in `ohdocs/`) | `zh-cn/application-dev/ui/arkts-stability-crash-issues.md` — **the two XComponent UAF patterns** |
| `displaysoloist-native-guidelines.md` | `zh-cn/application-dev/graphics/displaysoloist-native-guidelines.md` |
| `ndk-embed-render-components.md`, `ndk-accessibility-xcomponent.md` | `zh-cn/application-dev/ui/…` |
| `sample/NdkOpenGL_*`, `sample/ArkTS_*` | `code/BasicFeature/Native/{NdkOpenGL,ArkTSXComponent}/…` |

### Huawei URL equivalents

| Topic | Huawei URL |
|---|---|
| 自定义渲染 (XComponent) guide | `https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/napi-xcomponent-guidelines` |
| XComponent component reference | `https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-xcomponent` |
| `OH_NativeXComponent_Callback` | `https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ent-native-xcomponent-oh-nativexcomponent-callback` |
| NativeVSync guide | `https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/native-vsync-guidelines` |
| 请求自绘制内容绘制帧率 | `https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/displaysync-xcomponent` |
| NativeWindow guide | `https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/native-window-guidelines` |
| OpenGL ES capability overview | `https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/opengles` |

---

## Appendix B — Confidence ledger (what is certain vs. not)

### ✅ Confirmed by official documentation (verbatim quotes above)

| Claim | Source |
|---|---|
| `XComponentOptions` / API 10 legacy / API 19 NDK constructor signatures | `ts-basic-components-xcomponent.md` |
| `XComponentType.SURFACE` / `TEXTURE` semantics; COMPONENT deprecated 12, NODE deprecated 20 | `ts-appendix-enums.md#xcomponenttype10` |
| `getXComponentSurfaceId(): string`, API 9+ | `ts-basic-components-xcomponent.md` |
| `onLoad` / `onDestroy` semantics and `OnNativeLoadCallback` type | ditto |
| Controller callbacks only fire **without** `libraryname` | ditto (×3) |
| Events route to C-API only **with** `libraryname` | ditto |
| `getXComponentSurfaceId` invalid in `onLoad` for custom-node XComponents | ditto |
| `OH_NativeXComponent_Callback` members + signatures | `capi-oh-nativexcomponent-…-callback.md` |
| `OH_NativeXComponent_RegisterCallback` signature, API 8, return codes | `capi-native-interface-xcomponent-h.md` |
| `OH_NativeXComponent_GetXComponentSize` returns **vp** | ditto |
| Header `<ace/xcomponent/native_interface_xcomponent.h>`, lib `libace_ndk.z.so` | ditto |
| Headers `<native_window/external_window.h>`, `<native_buffer/native_buffer.h>`, `<native_vsync/native_vsync.h>` + libs | `capi-external-window-h.md`, `capi-oh-nativebuffer.md`, `capi-nativevsync.md` |
| `OH_NATIVE_XCOMPONENT_OBJ`, `OH_XCOMPONENT_ID_LEN_MAX = 128`, the `napi_get_named_property` + `napi_unwrap` recipe | guide + `native-window-guidelines.md` |
| Full EGL init sequence and `eglSwapBuffers` | `napi-xcomponent-guidelines.md` §开发示例 |
| CMakeLists content, `externalNativeOptions`, `abiFilters` | guide + `ArkTSXComponent/build-profile.json5` |
| No XComponent-specific `module.json5` config needed | both samples' `module.json5` |
| `RegisterOnFrameCallback` runs on the **UI main thread** | `displaysync-xcomponent.md` |
| `OH_NativeVSync` callback runs on **its own created thread** | `native-vsync-guidelines.md` |
| `OH_DisplaySoloist` is for **non-UI-thread** frame-controlled drawing | `displaysoloist-native-guidelines.md` + `displaysync-overview.md` |
| `OH_NativeXComponent` lifetime crash risk; migrate to `OH_ArkUI_SurfaceHolder` | `napi-xcomponent-guidelines.md` §迁移 |
| `void* window` NativeWindow is refcounted by the system, released after `OnSurfaceDestroyed` | `capi-oh-nativexcomponent-…-callback.md` |
| Previewer: **"Richtext、Web、Video、XComponent组件不支持预览"** + **"不支持调用C++库的预览"** | DevEco Studio 界面预览 guide |
| Previewer: XComponent examples "以真机运行为准，当前DevEco Studio预览器不支持" | `ts-basic-components-xcomponent.md` line 726 |
| ArkTS `Canvas` exposes only 2D contexts; no WebGL type in ArkUI | `ts-canvasrenderingcontext2d.md`, `ts-offscreencanvasrenderingcontext2d.md`, repo-wide grep |
| WebGL is an ArkWeb capability, **enabled by default** (`disableWebGL` default `false`) | `arkts-apis-webview-SecurityParams.md` |
| ArkGraphics 3D `@ohos.graphics.scene` exists from **API 12**, scene-graph + glTF, not raw GL | `js-apis-scene.md` |
| `OH_NativeXComponent_Callback` is stored by `XComponentPattern` **as a raw pointer**; must stay valid until `onSurfaceDestroy` returns | `ui/arkts-stability-crash-issues.md` |
| `OH_NativeXComponent` is raw-pointer managed; no API calls after `onSurfaceDestroy` completes | ditto |
| Handoff to a render thread: **either** `OH_NativeWindow_NativeObjectReference`/`Unreference`, **or** `join()` inside `OnSurfaceDestroyed` | `graphics/native-common-mistakes.md` |
| Never `OH_NativeWindow_DestroyNativeWindow()` a window obtained from the XComponent lifecycle | ditto |
| Crash signatures: `libsurface.z.so(OH_NativeWindow_DestroyNativeWindow / _NativeWindowHandleOp / _NativeObjectUnreference)` | ditto |
| `napi_env` is thread-bound; use `napi_create_threadsafe_function`; `napi_load_module` forbidden off main thread | `napi-guidelines.md`, `napi-faq-about-stability.md` |
| Previewer API whitelist includes `Canvas`/`OffscreenCanvas`, excludes XComponent | DevEco `ide-previewer-api-list` |
| Official XComponent OpenGL ES samples and their paths | `napi-xcomponent-guidelines.md` §相关实例 + samples repo tree |

### ⚠️ Inferred (documented facts combined; not stated in one sentence)

1. **"`libraryname` auto-loads the `.so`."** The docs say `onLoad` = *"Triggered when the plugin is loaded"* and that
   `nm_modname` must equal `libraryname` — which together entail that ArkUI performs the load. No single official
   sentence says "ArkUI calls `dlopen` on `libraryname`". **Confidence: high (~95%).**
2. **`OnSurfaceCreated/Changed/Destroyed/DispatchTouchEvent` run on the UI main thread.** Explicitly documented only
   for the *frame* callback (*"Callback回调函数运行于UI主线程"*). The nearest general rule is
   `ndk-build-ui-overview.md`: *"需要保证相关UI接口调用在应用主线程上调用"*. `DispatchTouchEvent` is inherently an
   input→UI event. Developer measurements on the Huawei forum report identical thread IDs (UI thread).
   **Confidence: high (~90%), but no official sentence names the thread for these four callbacks.**
3. **EGL must be created/drawn/swapped on one thread.** This is EGL-spec behaviour, not something HarmonyOS documents.
   The `NdkNativeImage` sample does all EGL work inside one spawned thread, consistent with it, and
   `native-common-mistakes.md` treats the "NativeWindow handed to a render thread" architecture as normal (it
   prescribes the refcount protocol rather than forbidding it). **Confidence: high (standard EGL semantics + supported
   architecture), but no HarmonyOS doc explicitly blesses `eglSwapBuffers` off the UI thread.**
4. **`eglChooseConfig` with `maxConfigSize = 1`.** The official sample does this; it is unusual vs. the EGL spec (which
   expects an array sized to the number of matching configs). It works in the sample. **Do not copy blindly if you need
   more than one candidate config** — query `numConfigs` and allocate properly.
5. **Previewer mechanism** ("doesn't run the native .so/GPU stack"). The *conclusion* is official (two sources); the
   *mechanism* is the standard explanation and is corroborated by Huawei forum staff, but not stated as such in a doc.

### ❌ Could not confirm

1. **No documented API to feed an `XComponent` Surface into the `Web` component** (or vice versa). I searched the ArkWeb
   and XComponent docs and found nothing. This is "not found", not "explicitly prohibited". See §8.3.
2. **`OH_NativeXComponent_Callback` invocation thread** is not stated in a single explicit sentence anywhere I found.
   See ⚠️ #2 — treat as UI-thread, but verify if you depend on it.
3. **Maximum practical frame rate / latency figures** for `RegisterOnFrameCallback` vs. `DisplaySoloist` — the docs say
   requested rates are not guaranteed ("会受限于系统功耗性能约束和屏幕刷新率硬件能力限制") and give no numbers.
4. **Whether `OH_ArkUI_SurfaceHolder` / `OH_ArkUI_SurfaceCallback` callbacks run on the UI thread** — not explicitly
   stated; assumed UI-thread by analogy with the lifecycle callbacks. The API 19 C reference documents **no thread
   restriction whatsoever** for this family. **Verify on device if you depend on it.**
5. **The exact meaning of 「不支持跨模块加载」** ("does not support cross-module loading") for `libraryname` is never
   defined in the docs. Practical reading: the `.so` must be packaged in the same HAP/module as the `XComponent`.
   **Unverified beyond that.**
6. **ArkGraphics 3D (`@ohos.graphics.scene`)** — I confirmed from the API reference that it exists from **API 12**
   (`SystemCapability.ArkUi.Graphics3D`) and provides glTF loading, a `SceneNode` tree, materials/images/shader
   *resources*, and post-processing. I did **not** stress-test its practical limits (custom render passes, raw GLSL,
   performance). Treat the "not a raw GL replacement" characterisation as directional but well-grounded.
7. **The specific Previewer failure mode for XComponent** (black frame? no render? crash?). Docs say only "not
   supported". Do not assert a failure mode.

### Version notes (API 12 → 24)

- **API 12:** `XComponentOptions`; `XComponentController.onSurfaceCreated/Changed/Destroyed`; `SurfaceRect`;
  `setXComponentSurfaceRect`; `enableAnalyzer`; `enableSecure` (13+).
- **API 18:** `OnNativeLoadCallback` type; `renderFit` all values allowed on SURFACE; expanded unsupported-attribute
  list on SURFACE; `RegisterOnFrameCallback` only delivers while attached to the tree.
- **API 19:** `NativeXComponentParameters`; the whole `OH_ArkUI_SurfaceHolder` / `OH_ArkUI_SurfaceCallback` family;
  `OHNativeWindow` typedef in the XComponent header. Huawei recommends migrating here.
- **API 20:** `lockCanvas` / `unlockCanvasAndPost`; `hdrBrightness`; `NODE` type deprecated; surface show/hide callbacks.
- **API 22:** `setXComponentSurfaceConfig`; multi-threaded UI-component creation (mounting still UI-thread-only).
- **API 24:** `hdrBrightness(brightness, type?)` with `HdrType { DEFAULT, AIHDR, EDR }`.
- **API 26 (beyond your range):** `SecurityParams.disableWebGL`.

*(The DevEco Studio Previewer limitation applies across all of these.)*
