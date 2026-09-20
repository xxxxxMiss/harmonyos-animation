# 长列表 · 分页加载 · 滚动锚定

> **三条硬约束**（本项目实际采用的形态）：
> 1. **全量 V2 状态管理** —— `@ComponentV2` / `@Local` / `@Param` / `@ObservedV2` / `@Trace`，
>    整棵树不允许 V1/V2 混用。
> 2. **只用滚动事件，不用任何手势监听** —— 需要兼容手表：表冠只会产生滚动事件，
>    没有触摸手势。所以没有 `Refresh`（下拉刷新本身就是手势组件）、没有 `onTouch`、
>    没有 pan/swipe。分页完全由 `onScrollIndex` 驱动。
> 3. **不允许 `setTimeout(fn, ms)`** —— 延迟多少才够是无法事先确定的，手机上对的数在手表上就是错的。
>    全工程只允许 `setTimeout(fn, 0)`，而且只用来"跳出布局回调"，绝不用来"等某件事完成"。

> 页面：`GlowLemniscate/entry/src/main/ets/pages/ListPage.ets`
> 核心：`GlowLemniscate/entry/src/main/ets/scroll/AnchorKeeper.ets`
> 数据：`GlowLemniscate/entry/src/main/ets/model/FeedItem.ets`
> 路由：`resources/base/profile/main_pages.json` → `pages/Index`（首页有"列表 Demo"按钮）、`pages/ListPage`

---

## 0. 用起来：`AnchoredPaging`（业务无关，全部可配置）

滚动效果本身和业务**完全解耦**，放在 `entry/src/main/ets/scroll/AnchoredPaging.ets`。
它不知道什么叫 `pageSize`、不知道你的数据类型、不碰你的数组、不发起请求 ——
它只告诉你**什么时候该加载**，并给你一个把「改数据」包起来的调用，好让位置在改动期间被保住。

```ts
import { AnchoredPaging, PULL_IDLE } from '../scroll/AnchoredPaging';

private scroller: ListScroller = new ListScroller();
private paging: AnchoredPaging = new AnchoredPaging({
  prefetchRows: 2,       // 距末尾几行开始要下一页
  pullThresholdVp: 80,   // 触顶后下拉多少 vp，松手才算一次请求
  pullSteps: 10,         // 指示器进度格数
  anchor: {
    toleranceVp: 1.0,    // 位置恢复到这个误差内就算到位
    maxCorrections: 40,  // 单次保持的失控保护
    stallLimit: 3        // 连续几次量不到锚定行就放弃
  }
});

aboutToAppear(): void {
  this.paging.attach(this.scroller);
  // 效果不持有数据：它只发问，你来回答。你原有的 loadOlder / loadNewer 原样保留。
  this.paging.onRequestOlder = () => { this.loadOlder(); };
  this.paging.onRequestNewer = () => { this.loadNewer(); };
}
```

接线只有六个滚动回调（**没有手势**，表冠同样驱动）：

```ts
List({ scroller: this.scroller }) { /* 你自己的行 */ }
  .onScrollIndex((s, e) => this.paging.handleScrollIndex(s, e, this.items.length))
  .onScrollStart(() => this.paging.handleScrollStart())
  .onScrollStop(() => this.paging.handleScrollStop())
  .onReachStart(() => this.paging.handleReachStart())
  .onScrollFrameBegin((o, st) => this.paging.handleScrollFrameBegin(o, st))
// 每一行还要接一个：
//   .onAreaChange(() => this.paging.handleRowResized())
```

你自己的加载逻辑里，把「改数据」这一步包进 `insertAnchored`：

```ts
private loadOlder(): void {
  const page: MyItem[] = this.api.fetchOlder();      // 你的业务，你的分页大小
  this.paging.insertAnchored(page.length, () => {     // 上方插入了 page.length 行
    this.items = page.concat(this.items);             // 数组是你的，怎么改都行
  });
}

private loadNewer(): void {
  const page: MyItem[] = this.api.fetchNewer();
  this.paging.insertAnchored(0, () => {               // 追加在下方，不移动锚点
    this.items = this.items.concat(page);
  });
}
```

`insertAnchored` 在 `mutate()` **之前**抓锚点、**之后**开始保持 —— 这两步的先后顺序
是调用方最容易搞错的地方，所以只通过这一个入口暴露。

### 0.1 哪些是效果的参数，哪些是你的

这是解耦的关键分界，不要混：

| 属于**效果**（`AnchoredPagingOptions`） | 属于**你的业务**（效果完全不碰） |
|---|---|
| `prefetchRows` —— 距末尾多少行触发 | `pageSize` —— 一页多少条 |
| `pullThresholdVp` —— 下拉多少才触发 | 数据源、请求、缓存 |
| `pullSteps` —— 进度粒度 | `loadingOlder/loadingNewer` 等状态位 |
| `anchor.toleranceVp` / `maxCorrections` / `stallLimit` | 空态、错误态、局部刷新 |

判据很简单：**「滚动该怎么反应」是效果的；「数据从哪来、一次要多少」是你的。**

### 0.1.1 页大小按「轮次」算，不是常量

聊天场景里一轮 = 1 个提问 + **N 个回答**（N 每次不同），所以**按轮次分页时每页条数是变的**，
根本不存在「一页多少条」这种常量。本仓库的演示就是按这个来的：

```ts
const ROUNDS_PER_PAGE: number = 5;          // 业务常量：一页 5 轮

const page: FeedItem[] = FeedSource.pageRounds(fromRound, ROUNDS_PER_PAGE);
this.paging.insertAnchored(page.length, () => {   // ← 传实际行数，不是配置里的页大小
  this.items = page.concat(this.items);
});
this.newerRound = fromRound + FeedSource.roundsIn(page);
```

一轮 1~5 个回答，所以 5 轮实际会返回 **10~30 条**，每次都不一样。
**滚动效果为此一行都不用改** —— `insertAnchored` 收的是**实际插入行数**，
`totalCount` 读的是真实数组长度，`prefetchRows` 本来就是「距末尾几行」而非绝对条数。
这也是 §0.1 那张分界表的直接验证：效果不知道页大小，所以页大小怎么变都无所谓。

演示里 HUD 同时显示两个数，就是为了让这件事可见：

```
42 轮 · 118 条消息  ·  首项 20  ·  锚定修正 2 次
```

前者是业务计数的，后者是派生的 —— 没有任何地方配置过 118。

### 0.2 效果暴露的可观测状态

`AnchoredPaging` 是 `@ObservedV2`，字段带 `@Trace`，
所以 `@ComponentV2` 的 `build()` 里**直接读就行**，不需要再拷进 `@Local`：

| 字段 | 含义 |
|---|---|
| `pullStep` | `PULL_IDLE`(-1) 空闲；`0..pullSteps-1` 下拉中；`pullSteps` 松手即可加载 |
| `holding` | 是否正在保持位置 |
| `corrections` | 累计修正次数（排查用） |
| `atTop` | 视口是否停在 row 0 |
| `firstVisible` | 当前可见首行 |

`ListPage.ets` 现在只是一个**演示宿主**：它只剩「行长什么样 / 数据从哪来 / 一页多少条」，
所有滚动相关的代码都在效果里。想看你自己的项目该怎么接，直接对照那个文件。

---

## 0.3 复杂测试案例：400-900ms 的分段渲染

真机（尤其手表）上，一行从插入到渲染完成可能要 **400-600ms**，而且不是一步到位 ——
可能先骨架、再半高、最后定高。一页 30 行这样settle，会产生**上百次布局变化**，
全部在锚定已经复位之后才到达。原来的演示「下一 tick 就就绪」，完全没覆盖这个场景。

`tools/simulate-anchor.mjs` 用真实设备的参数跑了一遍，**复现了失效**：

```
scenario                                  settle  corrections  layoutEvt  budget   finalErr  worst
A  baseline — instant settle, 1 stage         0ms           2          9       ok       0vp     0vp
B  120ms, 1 stage                           139ms           5         35       ok       0vp     0vp
C  watch 400-600ms, 1 stage                 595ms           9         35       ok       0vp     0vp
D  watch 400-600ms, 2 stages                595ms          14         70       ok       0vp     0vp
E  worst 400-900ms, 3 stages, 30 rows       887ms          39        159       ok       0vp     0vp
```

修复前的同一套场景（保留在 git 历史里）：

```
B  120ms                       finalErr =  725vp
C  watch 400-600ms             finalErr = -786vp
E  400-900ms 3 stages, 30 rows  finalErr =  325vp   ← correction budget exhausted
```

### 0.3.1 两个真 bug

**（1）修正量被写成了「增量」，但 `align = START` 每次调用都会重新定基。**

`scrollToIndex(..., align = START)` 先把该行顶边对齐到视口顶部，**再**位移 `extraOffset`。
所以基准每次都重建，`y = k · extra` 对每次调用独立成立，**正确答案是一个常量**：

```
extra = savedY / k
```

它和「上方内容长高了多少」完全无关，没有任何需要迭代求解的东西。

旧实现却把它当成围绕某个原点的局部仿射，折叠了一个残差：

```ts
y0 = y - k * extra;          // 只有在布局没动过时才成立
extra += (savedY - y0) / k;
```

`y0` 是**推导**出来的、不是重新测量的。手表上 400-600ms 的延迟意味着每次折叠
面对的都是一个已经移动过的布局 —— 锚点跑偏几百 vp，而且 `k` 也被带坏：

```
k re-derived 17 times; final k = -0.150
  t=416ms  k -1 -> 0.7
  t=448ms  k -1 -> 2.35
  t=560ms  k -1 -> 6.375
  t=576ms  k 6.375 -> -15.663
```

`k` 是 vp→vp 的单位换算，不可能合理地为 6.4 或 -15.7 —— 它是拿**内容位移**除以**修正位移**算出来的。

修复后的轨迹，`extra` 恒等于 `40 = -savedY`，只靠 `rowTop` 增长推动 offset：

```
apply t=112  extra=40.0 -> offset=2741  y=-40.0
apply t=128  extra=40.0 -> offset=2884  y=-40.0
apply t=144  extra=40.0 -> offset=3480  y=-40.0
final: offset=3480 rowTop=3440 y=-40.0 target=-40
```

**（2）`maxCorrections` 把「正常的落位」也算成了预算消耗。**

它现在只在**未收敛**时累加，收敛即归零。一页手表列表能产生 100+ 次高度变化，
按旧的算法 40 次就耗尽了 —— 这正是「400-600ms 就失灵」的直接原因。

### 0.3.2 另外两处配套改动

- **行只在高度真的变化时才上报**：`onAreaChange((o, n) => ...)` 里比较 `height`。
  行进出构建窗口也会触发这个回调，而锚定自己的 ALIGN 跳转就会造成大量进出 ——
  上报它们会把每次位移都标记成「布局动过」，永久堵死 `k` 的标定。
- **`k` 只在干净窗口内标定**：`cleanWindow` 在 `applyCorrection` 置位、在任何一次
  高度变化时清零。跨越一次 settle 的测量描述的是布局，不是映射。

### 0.3.3 怎么手工跑这个案例

真机上列表页顶部有一条 profile 切换条：

| 档位 | 含义 |
|---|---|
| 即时（下一 tick） | 修复前的演示行为，作为对照 |
| 手机 ~120ms | 单段 |
| 手表 400-600ms | 单段 |
| **手表 400-900ms · 分 3 段** | **最难的一档**，骨架→半高→定高 |

切换会重新播种对话。

**延迟时间是否真的落在 400-600ms？** `RenderLatency.schedule()` 会把**请求值**和
**实际触发值**都打进 hilog（`setTimeout` 只保证"不早于"，所以两者要分开看）：

```
schedule id=r82-m2 profile=手表 400-600ms seed=52150 total=572ms steps=1 at=[572]
schedule id=r84-m0 profile=手表 400-600ms seed=6496  total=490ms steps=1 at=[490]
fire     id=r82-m2 step=1/1 requested=572ms actual=572ms
fire     id=r84-m0 step=1/1 requested=490ms actual=490ms
```

真机实测（400-600ms 档，16 个样本，含连续加载 79→105→128 条期间）：

| | min | max | 平均 |
|---|---|---|---|
| requested | 404ms | 574ms | — |
| **actual** | **407ms** | **575ms** | 483ms |
| 偏差 | +0ms | +5ms | +1.2ms |

**16/16 全部落在 400-600ms 窗口内。** 静态核算也一致：整段对话里 102 个异步行的
请求值全部落在 401-599ms。

`WATCH_STAGED`（400-900ms）分三段：第 1 段 134-299ms、第 2 段 268-599ms、
第 3 段 401-898ms。

**所有时间只在 `model/RenderLatency.ets` 里**——
那是全工程唯一允许 `setTimeout(fn, ms)` 的地方，因为它在模拟流水线，
而不是让机制去猜一个延迟。`scroll/` 目录下仍然零墙钟等待。

### 0.3.4 为什么下拉加载时「看不到跳动」，以及这个数字在哪

一个反复出现的疑问：*下拉走 `loadOlder` 时并没有感觉到行在跳，延迟渲染真的生效了吗？*
延迟是真的，但**「看不到跳动」恰恰是锚定生效的表现**，而且有三个叠加的原因把现象藏住了：

**（1）新加载的行全部落在视口上方，本来就看不见。**
顶部下拉时 `firstVisible == 0`，`insertAnchored` 走的是 `capture(0, forceTopAlign = true)`
分支，`savedY = 0`；插入的 17 行全在锚点之上。锚点被重新钉回视口顶部之后，
读者看到的是**原来那一屏**，新行在它上面。要看到骨架态，得往上滚进新区块。

**（2）虚拟滚动下，视口外的行根本不在组件树里。**
`Repeat(...).virtualScroll({totalCount})` 只构建构建窗口内的行（外加 `cachedCount`）。
落在窗口外的行**是数据不是组件**，它们的高度变化不产生任何布局变化，也不触发 `onAreaChange`。
实测（`cachedCount(2)`）：17 行前置 + 5 行异步延迟，`onAreaChange` **一次都没有**上报；
把 `cachedCount` 提到 8 之后，紧邻视口上方的那两行才上报。
这不是缺陷，是虚拟滚动的定义 —— 也说明**前置插入这条路径上，延迟渲染本身是伤不到读者的**，
锚定在这里真正负责的是插入那一刻的位移（`shift`）。

**（3）修正和位移落在同一次布局里，`maxDriftVp` 结构性地接近 0。**
`scrollToIndex` 是异步的，框架会在**发生 resize 的那次布局**里把它一起应用掉。
所以 `VERIFY` 量到的残余永远是 0 —— 实测每次都是 `converged y=0.0 target=0.0`。
用 `maxDriftVp` 当"吸收了多少"的指标会得出"什么都没发生"的错误结论。

**能说明问题的数字是 `AnchorKeeper.churnVp`：当前 hold 期间，锚点之上的行上报的
高度变化绝对值之和。** 它就是"没有 hold 的话，画面上方会移动多少"。

真机一次下拉加载的完整证据（`cachedCount(8)`，手表 400-600ms 档）：

```
23:03:38.410  begin index=17 savedY=0.0
23:03:38.799  rowSized r80-m3 #13 60vp -> 186vp     <- 延迟 413ms 后落位，+126vp
23:03:38.799  converged y=0.0 target=0.0            <- 视口未动
23:03:38.905  rowSized r81-m0 #14 60vp -> 118vp     <- 延迟 515ms 后落位，+58vp
23:03:38.906  converged y=0.0 target=0.0            <- 视口未动
HUD: 首项 17 · 修正 2 次 · 高度变化 241vp
```

`#13`、`#14` 都 < 锚点索引 17，所以计入 `churnVp`；`#21`、`#22` 在锚点之下，不计。
241 = 11 + 46 + 126 + 58，与逐行日志逐项对得上。

**反证**：同一个下拉，把顶部 `锚定` 开关关掉（`insertAnchored` 不调用，效果本体不动），
首行从 `第 82 轮 · 提问` 变成 `第 77 轮 · 提问` —— 读者被甩回整整一页。
开关打开时同样的操作，首行停在 `第 82 轮`、`首项 17`。

> 因此列表页默认档位是**手表 400-600ms**而不是"即时"：即时档下 hold 一帧内就收敛，
> 整个页面看上去什么也没发生，反而更像坏了。
> 另外 `churnVp` 必须过滤 `before > 0`（组件构造而非行 resize）——
> 不加这个过滤，一次重建会把 241vp 报成 2128vp。

### 0.3.5 整页插入 vs 逐条 unshift：同样的数据，结果完全不同

一个很自然的疑问：*演示里从上方插入数据，列表一点不跳；可我在真实穿戴设备上跳得厉害，
是不是因为我一条一条 `unshift`？* —— **是，而且这是主因。**

`InsertMode` 就是这个对照实验（列表页顶部「整页插入 / 逐条 unshift」开关）：

| 插入方式 | 锚定 | 首行 |
|---|---|---|
| 整页 `concat` | 开 | 不动（`首项 17`，吸收 241vp） |
| **逐条 `unshift`** | **关** | **`第 82 轮` → `第 77 轮`，甩回一整页** |
| 逐条 `unshift` | 开 | 不动（吸收 383vp） |

**「逐条 + 关锚定」就是没有锚定的真实业务**，一页 17-21 行会在几毫秒内进完
（实测 `setTimeout(fn, 0)` 链：21 行 5ms），每一行都是一次独立的数组变更 + 一次布局，
读者的位置被推 N 次。整页插入只有一次。

#### 逐条插入踩到的坑（`insertAnchored` 已修）

就算锚定开着，逐条插入在修复前也是错的。原因在 `insertAnchored` 里：

```ts
// 修复前
const wasAtTop = this.firstVisible === 0;
this.keeper.capture(this.firstVisible, wasAtTop);   // ← 每次调用都重新 capture
```

`firstVisible` 只由 `onScrollIndex` 刷新，而**紧凑的插入循环跑得比滚动事件快**：
21 行在 5ms 内进完，期间一个滚动事件都没有。于是 `shift()` 已经把锚点索引往前推了，
`capture()` 又把它按一个**过期的** `firstVisible` 拽回去 —— 每迭代一次落后一行。
真机日志里能直接看到这个形状：

```
capture index=0 top-aligned
begin index=1 savedY=0.0
begin index=2 savedY=0.0
begin index=3 savedY=0.0     ← 索引被一行一行推着走
```

修复：**hold 还活着的时候，锚点以 hold 自己为准，不再 capture。**
`shift()` 一直跟着每次插入走，`savedY` 是 hold 正在维持的位置；
`capture()` 是「开始一次 hold」用的，不是「继续一次 hold」用的：

```ts
if (!this.keeper.isHolding()) {
  this.keeper.capture(this.firstVisible, this.firstVisible === 0);
}
```

修复后同样的 21 行只有**一次** `capture`：

```
capture index=0 top-aligned
begin index=1 / 2 / 3 / ... / 21       ← 每次只 shift(+1)
```

`tools/simulate-anchor.mjs` 里加了对应的回归（数据、延迟、落位时间完全相同，
**唯一变量是 capture 次数**）：

```
mode                                          captures  finalErr   worst  maxDrift
整页 concat  · 一次 insertAnchored(n)                    1       0vp     0vp     295vp
逐条 unshift · 修复前（每次重新 capture）                      20      93vp    93vp     143vp
逐条 unshift · 修复后（hold 期间不 capture）                   1       0vp     0vp     295vp
```

> 另外注意 `unshift` 的方向：把一页**正序**逐条 `unshift` 进去，页面会**倒过来**存。
> 这个 bug 很安静 —— 列表照样变长、锚定照样生效，只有顺序反了。
> 真机上表现为 `第 81 轮 · 回答 2 / 2` 渲染在 `回答 1 / 2` **上面**。
> 演示里因此是**倒序**遍历这一页（见 `prependOneByOne`）。

#### 所以真实设备为什么跳得厉害

按可能性排序，前三条都能单独造成"跳得厉害"：

1. **逐条 unshift 且没有锚定** —— 一次插入一次位移，一页就是 N 次。
2. **行高不确定**：真实数据没有高度字段，行高靠内容量出来。
   插入瞬间列表并不知道这一行多高，只能按均值估；等 400-600ms 后内容到位、
   真实高度出来，列表再把估值改掉 —— **每次修正都是一次跳动**。
   演示里每行都显式写了 `.height()`，所以列表的几何一开始就是准的。
   这是"演示不跳、真机跳"最容易被忽略的一条。
3. **`Repeat.virtualScroll()` 没有 `onGetItemMainSizeByIndex`**（见 §8），
   所以"提前告诉列表每行多高"在 `Repeat` 下做不到，只能靠行自己声明高度。
4. 逐条插入时若走了锚定，还要用**修复后**的 `insertAnchored`（见上）。

**建议**：拿到一页之后**攒成一批再改数组**（`items = page.concat(items)`），
用一次 `insertAnchored(page.length, …)` 包住；确实必须逐条进的时候，
让每行一开始就占**最终高度**（骨架 = 定高），或者接受行会二次增长。

---

## 1. 要解决的问题

列表里**每一条的高度都不一样**，而且**有些条目渲染很慢**：
它们先占一个较矮的骨架，几百毫秒后内容才到、高度才撑开。
这些慢条目**不是按顺序落位的**，所以视图在用户阅读期间会反复重排：

- 下面某条撑高 → 它下面的所有内容整体位移；
- 在顶部插入一页 → 视口里的内容**直接跳后 20 条**。

结果就是"看着看着位置就跑了"。

## 2. 为什么不用 `maintainVisibleContentPosition`

`List` 确实有这个属性（API 12），但官方文档写得很明确：

> The visible content position will only remain unchanged when **LazyForEach** is used to
> insert or delete data **outside the visible area**. If ForEach is used … the visible
> content position will change even if *maintainVisibleContentPosition* is set to *true*.
> —— `component/list.d.ts`

两个限制正好都撞上本场景：

1. 它只覆盖**在可见区之上插入/删除**；**底部追加**和**某一条自己长高**都在契约之外；
2. 它只认 `LazyForEach`，而这里用的是 `Repeat`。

所以需要一个显式的锚定机制。

## 3. 锚定机制

核心思路：**记住视口顶部那一行是谁、它当时在什么位置，然后每次布局变化后把它放回去。**

```
capture()              改动数据之前：记录 (index, y)
   │                     index 来自 List.onScrollIndex 的 start
   │                     y     = getItemRect(index).y，相对视口顶边的偏移
   ▼
（替换 items 数组）
   ▼
begin()                改动之后：开始保持
   ▼
notifyLayoutChanged()  每个条目 onAreaChange 都调它 —— 慢条目落位就重锚一次
   ▼
step()                 量误差 → scrollToIndex 修正 → 复查，直到误差 ≤ 1px
   ▼
settle()               布局安静 700ms 后解除保持
```

### 3.1 修正量是**量出来的**，不是猜出来的（但不再需要额外探针）

最初的实现假设 `extraOffset` 的单位和符号，结果在真机上**朝反方向走**，把目标行一路推出构建范围：

```
prime index=20 extra=0.0
applied idx=20 extra=-661.4  off 0->2145    item0.h=0  itemT=661/64
applied idx=20 extra=-1322.8 off 2145->1484 itemT=0/0
unmeasurable after prime, accepting
```

两次修正都让误差变大。根因是 `getItemRect()` 返回 **vp**，而当时传的是 `LengthMetrics.px()`，
ArkUI 按屏幕密度（该机 1216/375 = **3.243**）把每次修正都缩小了 —— 实测
`k = dy/d(extra)` 稳定在 **−0.3082 … −0.2140**，正好是 1/3.24。

所以现在不再假设，而是**标定**。放置到 `align = START` 后位移是局部仿射的：

```
y(extra) = y0 + k · extra        →        extra* = (savedY − y0) / k
```

`k` 把**符号和单位一起吸收掉**，初值取静止时的实测值 −1，之后**从每一次真实修正里反解**：

```ts
// ALIGN:  apply(0)                       建立 align=START 基准，等滚动事件
// SOLVE:  读 y0；extra = (savedY - y0)/k ；apply(extra)
// VERIFY: 读 y；收敛则结束，否则 k = (y - y0)/extra 修正后重算
```

真机日志：`solve y0=0.0 k=-1.0000 -> extra=0.0` → `converged y=0.0 target=0.0 k=-1.0000 after 2`。
**两次修正收敛**，单位是 `LengthMetrics.vp()`（与 `getItemRect` 一致）。

### 3.2 三个必须处理的边界

| 情况 | 处理 |
|---|---|
| 锚定行已被回收，`getItemRect` 无有效矩形 | 连续 `STALL_LIMIT` 次仍不可测就放弃，不再空转 |
| `capture()` 拿不到有效矩形 | 退化为"只锚 index、顶对齐"，总比丢掉锚点被整页顶飞好 |
| 修正过程中用户自己滑动 | `List.onTouch` 收到 `TouchType.Down` 就 `release()`。`scrollToIndex` 是程序化的、**不产生触摸事件**，不会误杀自己的修正 |
| 列表正在惯性滑动（触底加载常见） | 直接跳过保持 —— 追加本来就不动上方内容，此时重锚只是跟用户抢滚动 |

还有一个不显眼但重要的点：**只有布局真的变过（`dirty`）才允许修正**，
否则保持期内用户滑走以后定时器还会把他拽回来。

### 3.3 真机上踩到的坑（都已修）

**（1）`Repeat` + `virtualScroll` 在 V1 `@Component` 里不能用。**

```
E AceStateMgmt: FIX THIS APPLICATION ERROR: @Component 'ListPage':
    State variable 'items' has changed during render!
W AceStateMgmt: __RepeatVirtualScroll2Impl(-1)) it is not allowed to use
    Repeat virtualScroll inside a @Component!
```

第二条才是根因。之后 List **静默地不再跟踪数组**：数组涨到 240 条，列表始终只渲染前 20 条，
于是它永远"在末尾"，`onReachEnd` 无限触发、疯狂翻页。

`virtualScroll` 需要 **V2 装饰器**。**迁到 V2 之后 `virtualScroll` 正常工作**（已在真机确认）。

**（2）`onReachEnd` / `onAreaChange` / 路由页 `aboutToAppear` 都在渲染流程内。**
在里面写状态会直接触发同一条 "changed during render" 错误。
所以状态写入统一用 `setTimeout(fn, 0)` 挪出布局回调，`items` 则在字段声明处初始化。

**（3）单位：`getItemRect()` 返回 vp，`extraOffset` 也按 vp 消费。**
最初传 `LengthMetrics.px()`，ArkUI 按屏幕密度（该机 1216/375 = **3.243**）把每次修正都缩小了 ——
实测 `k = dy/d(extra)` 稳定在 −0.3082…−0.2140，正好 1/3.24。

**（4）去掉所有定时等待后暴露的两个新问题：**

- **`setTimeout(fn, 0)` 不能保证滚动已经生效。** 每次 `scrollToIndex` 后立刻重新测量，
  测到的是**滚动前**的位置：残差恒定 48vp、`extra` 却每步走远 48vp，直到预算耗尽。
  → 现在 `applyCorrection()` 只置 `awaitingScroll`，由页面在
  `onScrollIndex` / `onScrollStop` 里回调 `onScrollSettled()` 来放行 —— 用的是**真正的滚动事件**。

- **`restores` 是累计诊断计数器，却被当成了单次预算。** 一旦触顶就永久失效。
  → 拆成独立的 `corrections`（每次 `begin()` 归零）。

**（5）标定不能在惯性滑动中进行。**
上下各滑几次后，ALIGN 与下一次测量之间列表还在因惯性移动，两个采样点互相矛盾，
`k` 被标定成 −1.36 之类的错值，修正随之漂移。
→ 页面把 `begin()` **推迟到 `onScrollStop`**（`beginOnSettle`）：载入完成时若仍在滚动就先记住，停下来再开始保持。
锚点本来就是在插入前捕获的，推迟不影响正确性。修好后真机稳定输出 `k=-1.0000`。

**（6）标定探针被删掉了。**
早期用一个专门的 `PROBE_VP`（48vp）位移来测 `k`。但那是紧跟 ALIGN 之后的**第二次小幅滚动**，
如果它没有改变可见区间，就不会产生滚动事件可用于等待，保持会卡住。
现在 `k` 直接从**本来就要做的那次修正**里反解：`k = (y − y0) / extra`，
不需要任何额外滚动；初值 −1（静止时实测值），估错也只是多一轮，随后自纠正。

## 4. 两个加载方向

### 4.1 顶部：**拉过顶部 + 松手** 才加载（不是"接近顶部就加载"）

早期实现是"可见首项 ≤ 2 行就插入 20 条"。这样**根本看不到上一次顶部在哪** ——
数据在用户还没到顶时就插进来了，锚定效果无从观察。

现在改成下拉刷新的语义，但**只用滚动事件实现**（不引入 `Refresh`，它在手表上无意义）：

| 步骤 | 事件 | 处理 |
|---|---|---|
| 视口停在 row 0 | `onScrollIndex(start === 0)` / `onReachStart` | `atTop = true` |
| 继续下拉 | `onScrollFrameBegin(offset, state)` | `offset < 0` 且 `state === Scroll` 时累加 `pull += -offset` |
| 松手 | `onScrollStop` | `pull ≥ PULL_THRESHOLD_VP`(80vp) 才 `loadOlder()` |
| 离开顶部 | `onScrollIndex(start > 0)` | 清空 `pull` |

`onScrollFrameBegin` 给出的是**本帧将要滚动的量**（夹紧之前，单位 vp），
所以视口已经钉在 row 0 时，任何继续向下的请求都是纯"拉过量"。
它是**帧级滚动钩子而不是手势**，表冠驱动方式和手指完全一致。

顶部有一条**固定 28vp** 的提示条（不改变 List 布局，顶部行因此纹丝不动）：
`已到顶部 · 下拉一段距离后松手可加载更早的数据` →
`继续下拉加载更早的数据 ███░░░░░░░` → `松开即可加载更早的数据` → `正在加载更早的数据…`。

**踩到的坑**：`onReachStart` 在弹簧回弹过程中会**再次触发**，
如果在那里清零 `pull`，实测会把已经拉到 271vp 的进度在松手前一刻抹成 0，功能完全失效。
现在 `onReachStart` 只置标志、不清零；清零只发生在"离开 row 0"和"松手"两处。

### 4.2 底部：仍是接近末尾即预取

追加不会移动视口上方的内容，没有需要保住的位置，也没有需要观察的过程，
所以保持常规的无限滚动预取（`end` 接近末尾时追加 20 条）。
为防止首帧就触发，底部同样需要"先离开末尾"才允许触发（`bottomArmed`）。

## 5. 用到的 API（均已对 SDK 声明核实）

| API | 用途 | `@since` |
|---|---|---|
| `Repeat<T>(arr).each().key().virtualScroll({totalCount})` | 虚拟滚动长列表（**需 V2 装饰器**） | 12 |
| `@ComponentV2` / `@Local` / `@Param` / `@Require` / `@Event` | V2 状态管理与组件入参 | 12 |
| `@ObservedV2` / `@Trace` | 行内可变字段的观测 | 12 |
| `ListScroller` / `Scroller.scrollToIndex(index, smooth, align, options)` | 精确跳转 | 11 |
| `ScrollToIndexOptions.extraOffset: LengthMetrics` | 像素级偏移修正 | 12 |
| `ScrollAlign.START` | 顶对齐基准 | — |
| `Scroller.getItemRect(index): RectResult` | 量当前行位置 | 11 |
| `List.onScrollIndex((start, end) => …)` | 跟踪可见区间；底部预取与放行锚定的入口 | 11 |
| `List.onScrollFrameBegin((offset, state) => …)` | 帧级滚动量（vp，夹紧前）→ 累加顶部下拉距离 | 11 |
| `List.onReachStart` | 视口到达起点 | 11 |
| `List.onScrollStart` / `onScrollStop` | 滚动生命周期（非手势，表冠同样触发） | 11 |
| `List.onReachEnd()` | 触底加载 | 11 |
| `List.onTouch` | 区分用户手势与程序化滚动 | — |
| `@Observed` / `@ObjectLink` | 单行内容到达时只重渲染那一行 | — |
| `UIContext.getRouter().pushUrl()/back()` | 路由 | 11 |

## 6. 怎么验证

真机/模拟器上从首页点「列表 Demo」进入，观察顶部的 HUD：

```
共 300 条  ·  可见首项 #281  ·  锚定修正 4 次  ·  保持中 #281
```

**验证顶部下拉**（锚定最关键的一条路径）：
1. 先把列表往下滑一段，记住屏幕最上面是第几条；
2. 滑回顶部、下拉；
3. 松手后新数据插入上方 —— 屏幕最上面**应该还是刚才那条**，而不是往前跳 20 条。

**验证慢条目**：找序号是 6 的倍数的行（HUD 里标了"慢速渲染"），
它们会先显示"渲染中…"骨架再撑开；撑开时视口不应该位移。

## 7. 调参

全部集中在 `AnchoredPaging` 的构造参数里（`ListPage.ets` 里那份就是示例值）：

**行为参数**（决定「什么时候加载」）：

| 参数 | 默认 | 含义 |
|---|---|---|
| `prefetchRows` | 2 | 距**末尾**几行开始请求下一页 |
| `pullThresholdVp` | 80 | 触顶后下拉多少 vp，松手才算一次「加载更早」 |
| `pullSteps` | 10 | 指示条进度格数（量化，避免逐帧写状态） |

**锚定参数**（不改变加载时机，只决定「多精确」和「多快放弃」）。
三个分别卡在保持循环的不同位置：

```
ALIGN   scrollToIndex(index, START, 0)     把锚定行拉进视口（顺带让它被构建）
SOLVE   y0 = getItemRect(index).y          ← stallLimit 管这里（量不到就重试）
        extra = (savedY - y0) / k
        scrollToIndex(index, START, extra)
VERIFY  err = getItemRect(index).y - savedY
        |err| ≤ toleranceVp → 收敛          ← toleranceVp 管这里
        否则 refine k 再修一轮               ← maxCorrections 管这里
```

一次正常保持是 **2 次修正**，三个默认值都是围绕这个事实留的余量。

| 参数 | 默认 | 管什么 | 触发后果 |
|---|---|---|---|
| `anchor.toleranceVp` | 1.0 | **够不够近**（VERIFY 测误差） | 收敛停止修正，保持继续 |
| `anchor.maxCorrections` | 40 | **修太多次了**（每次 `step()` 开头） | 整个保持被 `release()` |
| `anchor.stallLimit` | 3 | **量不到目标行**（`getItemRect` 返空矩形） | 暂停本轮，布局再变会重试 |

- **`toleranceVp` 为什么不取 0**：`k` 是测出来的、`extraOffset` 和布局都会被量化到物理像素。
  追求 0 意味着反复发 `scrollToIndex`（每次都触发一整轮布局）换取看不见的收益。
  这台设备 1216px/375vp = **3.243**，1vp ≈ 3.2 物理像素。
  调大 → 行回来时肉眼可见地差一截；调小 → 可能永远满足不了量化，每轮都修到 `maxCorrections`。
- **`maxCorrections` 必须是「单轮」计数**：它和累计的 `restores`（给 HUD 看的）严格分开。
  **这里踩过真 bug** —— 最初拿累计值当预算，一个会话累计修满 40 次后闸门永久卡死、锚定静默失效，
  日志上还看不出来。正常一轮 2 次，就算 20 行逐条撑开也就 5~8 次，40 是约 20 倍余量。
- **`stallLimit` 是「连续」计数**：一旦量成功立刻归零。单次失败是正常瞬态
  （`scrollToIndex` 发出去了、布局还没跑完），所以不能设 1。
  超时动作是 **`dirty = false` 暂停本轮而不是 release**，下次任何一行改尺寸会重试，可恢复。
  注意它超时**可能完全无害**：`savedY` 为 0 时 ALIGN 已经把行放到顶部，那本来就是正确答案。

**排查对照**：

| 现象 | 大概率是 | 怎么调 |
|---|---|---|
| 频繁 `row N never became measurable`，但位置其实对 | `stallLimit` 太小，把正常的「还没构建完」当失败 | 调大 `stallLimit` |
| 每次都修很多轮才停，位置只差一点点 | `toleranceVp` 太小，在跟像素量化较劲 | `1.0` → `2.0` |
| 出现 `correction budget exhausted` | 有行在反复改高（动画占位/自引用），或 `savedY` 不可达 | **先查数据**，再考虑调大 `maxCorrections` |
| 恢复后明显偏了一截 | `toleranceVp` 太大，过早收敛 | 调小 `toleranceVp` |

不属于效果、留在宿主里的：**页大小**（本演示是 `ROUNDS_PER_PAGE`，按轮计）、数据源、加载状态位。
另外 `cachedCount` 是 List 自己的属性，由宿主按行高设置。

## 8. 真机验证状态

**已在真机验证通过**（HarmonyOS 设备 `9CN0224A11000514`，1216×2688，density 3.243）：
`hdc install` → `snapshot_display` → `hilog` 全流程。

| 项 | 结果 |
|---|---|
| 全量 V2（`@ComponentV2`/`@Local`/`@Param`/`@ObservedV2`/`@Trace`） | ✅ 编译并运行，无 V1/V2 混用报错 |
| `Repeat` + `virtualScroll` | ✅ V2 下正常工作，不再出现 `RepeatVirtualScroll` 报错 |
| **零手势监听** | ✅ 无 `Refresh` / `onTouch` / pan / swipe，只保留 `onScrollIndex` / `onScrollStart` / `onScrollStop` |
| **零 `setTimeout(fn, ms)`** | ✅ 全工程只有 `setTimeout(fn, 0)`（三处，均为跳出布局回调） |
| **到顶不再自动加载** | ✅ 滚到 row 0 后 `共 20 条` 不变，提示条显示"已到顶部…" |
| **短拉被拒绝** | ✅ ~55vp：`pull released under threshold, ignored`，不加载 |
| **拉过阈值后松手才加载** | ✅ ~280vp：`pull released past threshold -> loadOlder` → `loadOlder from=261 n=20 -> items=40` |
| **插入后位置保持** | ✅ `solve y0=0.0 k=-1.0000 -> extra=0.0` → `converged y=0.0 target=0.0`；HUD `共 40 条 · 首项 20 · 锚定修正 2 次`（无锚定时应为 `首项 0`） |
| 滚动到底 → 下方追加 20 条 | ✅ `loadNewer from=301 -> items=40`、`from=321 -> items=60` |
| 标定稳定性 | ✅ 静止时恒为 `k=-1.0000`，两次修正收敛 |
| 预算防护 | ✅ 单次 `corrections` 计数，不再永久失效 |
| 状态栏遮挡 | ✅ 由 `EntryAbility` 在 `loadContent` **之前**发布 `topSafeInsetPx` |

证据截图：`preview/frames/list-anchor-onsite.png`（V1 版的同机制对比）；
本轮真机截图保存在 `/tmp/glowshot/`（`q0/q1/r1/r2`）。

**重构为 `AnchoredPaging` 之后已重新上机**（设备 `9CN0224A11000514`），
按「轮次分页 + 手表 400-600ms」重跑：

| 项 | 结果 |
|---|---|
| 下拉加载 17 行（按轮次，非定长） | ✅ `loadOlder rounds=5 rows=17 -> total 34` |
| 插入后位置保持 | ✅ `capture index=0 top-aligned` → `begin index=17 savedY=0.0` → `converged y=0.0`；HUD `首项 17`，首行仍是 `第 82 轮 · 提问` |
| 延迟渲染确实发生 | ✅ 5 行异步，`schedule` 于 11.701，`fire` 于 12.115-12.246，即 **414/415/517/536/544ms** |
| 延迟造成的布局位移被吸收 | ✅ `高度变化 241vp`（见 §0.3.4），视口位移 0 |
| 对照组（关掉顶部 `锚定` 开关） | ✅ 同一次下拉把首行从 `第 82 轮` 甩到 `第 77 轮`，整整一页 |
| `Repeat` + `virtualScroll` + `cachedCount(8)` | ✅ 正常构建与复用，`RepeatItem.index` 可用（API 12） |
| 真机滚动事件驱动 | ✅ 全程无手势监听，测试用的 `uinput -T -m` 只是模拟系统滚动 |

仍未验证 / 已知取舍：

- **手表未实测**。已按表冠语义改造（只用滚动事件），但真机只在手机上跑过。
- **`k` 初值 −1 是手机上的实测值**。若某设备单位约定不同，首轮会多一次修正后自纠正。
- **`onScrollStop` 才 `begin()`**：滚动过程中不保持。这是刻意的 —— 惯性中标定会得到错值（实测 −1.36）；
  代价是用户停在列表中间时，插入的那一页不会立即补位（等下一次停稳）。
- 慢内容由 `model/RenderLatency.ets` 按档位模拟，默认档位是手表 400-600ms（见 §0.3.3 / §0.3.4）。
- **`Repeat(...).virtualScroll()` 没有 `onGetItemMainSizeByIndex`**（该 API 只在 `WaterFlow` 上，
  本工程 API 12 基线的 `VirtualScrollOptions` 只有 `totalCount` / `reusable`(18) / `onLazyLoading`(19)）。
  所以「提前告诉列表每行多高」这件事在 `Repeat` 下做不到，行高只能由行自己的 `.height()` 声明。
  这也是列表页每行都把 `.height()` 显式写出来的原因：真实业务的数据里没有高度字段，
  高度只能由渲染方给出。
