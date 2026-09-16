# AGENTS.md — 本仓库的工作约定

> 这个文件会被 agent 会话自动加载。它记录的是**项目约定**，不是需求文档；
> 需求背景看 `README.md`，技术细节看 `REPORT.md` 与 `docs/`。

## 0. 硬性工作流：完成任务后自动提交

**每完成一个任务，必须把改动提交并推送到 origin。** 不需要用户再提醒。

```bash
git add -A
git -c core.pager=cat diff --cached --stat     # 先看清单
git commit -m "<一句话说清做了什么>"
git push
```

要求：

- **提交前先 `git diff --cached` 检查是否混入了不该提交的东西**（见 §1）。
- 提交信息写清楚「做了什么 + 为什么」，涉及真机验证的把关键日志/结论带上。
- 一个任务一个提交；不要把多个不相关的改动塞进同一个提交。
- 远程：`git@github.com:xxxxxMiss/harmonyos-animation.git`，主分支 `main`。

## 1. 绝对不能提交的东西

| 路径 | 原因 |
|---|---|
| `GlowLemniscate/build-profile.json5` | DevEco 会把签名配置写进去：**加密后的 `keyPassword`/`storePassword`** + 指向本机 `~/.ohos/config` 的绝对路径。既是凭据又和机器绑定。仓库里有 `build-profile.example.json5` 作为模板 |
| `*.p12` `*.p7b` `*.cer` `*.csr` | 签名材料本体 |
| `.hvigor-home/` | 本项目的 hvigor 缓存（约 15 MB 构建缓存） |
| `GlowLemniscate/.hvigor/` `**/build/` | 构建产物与构建报告（报告里含本机绝对路径） |
| `research/raw/` | 第三方文档缓存（约 3 MB），引用 URL 已在 `research/*.md` 里 |

**动手前先确认 `.gitignore` 已经覆盖**，`git check-ignore -v <path>` 可以验证。

## 2. 编译与验证

```bash
cd GlowLemniscate
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
export HVIGOR_USER_HOME=$PWD/../.hvigor-home          # 缓存留在工作区内，不写 ~/.hvigor
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw --no-daemon assembleHap
```

纯 Node 的几何验证（不需要设备）：

```bash
node tools/verify-geometry.mjs        # 期望输出 PASS，mismatching: 0
```

真机验证（改了列表/滚动/UI 之后应当跑一遍）：

```bash
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
$HDC list targets
$HDC install -r GlowLemniscate/entry/build/default/outputs/default/entry-default-signed.hap
$HDC shell hilog -r && $HDC shell aa start -a EntryAbility -b com.example.myapplication
$HDC shell uinput -T -c <x> <y>                       # 点击
$HDC shell uinput -T -m <x1> <y1> <x2> <y2>           # 滑动
$HDC shell snapshot_display -f /data/local/tmp/x.jpeg && $HDC file recv /data/local/tmp/x.jpeg /tmp/x.jpeg
```

排查问题时 `hilog` 里的 `AnchorKeeper` / `ListPage` tag 是最直接的证据来源。

## 3. 列表页的三条硬约束（不要回退）

`entry/src/main/ets/pages/ListPage.ets` 与 `scroll/AnchorKeeper.ets`：

1. **全量 V2 状态管理** —— `@ComponentV2` / `@Local` / `@Param` / `@ObservedV2` / `@Trace`。
   V1 与 V2 组件不能混在一棵树里。`Repeat(...).virtualScroll(...)` **必须**在 V2 下才工作，
   在 V1 里会报 `it is not allowed to use Repeat virtualScroll inside a @Component!`，
   随后 List 静默停止跟踪数组。
2. **只用滚动事件，不用手势监听** —— 需要兼容手表：表冠只产生滚动事件。
   不要引入 `Refresh`、`onTouch`、pan/swipe。分页只用
   `onScrollIndex` / `onScrollStart` / `onScrollStop` / `onScrollFrameBegin` / `onReachStart`。
3. **禁止 `setTimeout(fn, ms)`** —— 只允许 `setTimeout(fn, 0)`，且只用来「跳出布局回调」，
   绝不用来「等某件事完成」。延迟多少才够是无法事先确定的，手机上对的数在手表上就是错的。
   需要等某个状态就绪时，挂到真实事件上（滚动事件 / `onAreaChange`）。

另外两个踩过的坑，改这块之前先看 `docs/LIST-SCROLL-ANCHOR.md` §3.3：
`getItemRect()` 返回 **vp**（不是 px）；`onReachEnd`/`onAreaChange`/路由页 `aboutToAppear`
都在渲染流程内，在里面写状态会被 ArkUI 拒绝。

## 4. 目录导航

```
REPORT.md                      特效移植的调研正文（原理、方案对比、真机结论）
README.md                      快速上手 / 编译 / 调参速查
docs/LIST-SCROLL-ANCHOR.md     长列表分页与滚动锚定：机制、踩坑、验证状态
GlowLemniscate/                可编译工程（ArkTS，API 12 基线）
  entry/src/main/ets/glow/       shader 几何移植 + drawing API 渲染器
  entry/src/main/ets/scroll/     AnchorKeeper：滚动锚定器
  entry/src/main/ets/model/      FeedItem：列表数据与异步内容模拟
  entry/src/main/ets/pages/      Index（发光页）/ ListPage（长列表）
tools/verify-geometry.mjs      纯 Node 的几何正确性验证
preview/                       HTML 孪生体 + 对比/真机截图
research/                      深度调研报告（raw/ 是文档缓存，不入库）
```

## 5. 写作约定

- 注释和文档用中文；代码标识符用英文。
- 注释解释**为什么**，不复述代码在做什么。踩过的坑、反直觉的取值、被否决的方案要写清楚，
  否则下一个人会把它们改回去。
- 数值结论要能追溯（哪个文件、哪次真机日志、哪条命令算出来的）。
