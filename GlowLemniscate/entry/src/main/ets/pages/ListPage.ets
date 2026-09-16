/*
 * ListPage.ets — a long, variable-height feed with scroll-driven paging and a
 * scroll anchor that survives out-of-order row rendering.
 *
 * Read `AnchorKeeper.ets` first: it holds the actual anchoring mechanism. This
 * file is the wiring around it.
 *
 * Three constraints shape this page
 * ---------------------------------
 * 1. **V2 state management.** `@ComponentV2` / `@Local` / `@Param` /
 *    `@ObservedV2` / `@Trace` throughout. V1 and V2 components cannot be mixed
 *    in one tree, so every component here is V2.
 *
 * 2. **No gesture listeners — scroll events only.** This has to run on a watch,
 *    where the digital crown produces scroll events and there are no touch
 *    gestures at all. So there is no `Refresh` (pull-to-refresh is a gesture
 *    component), no `onTouch`, no pan/swipe. Paging is driven purely by
 *    `onScrollIndex`, which the crown drives exactly like a finger.
 *
 * 3. **No `setTimeout(fn, ms)`.** How long anything takes is not knowable ahead
 *    of time, and a fixed wait that is right on a phone is wrong on a watch. The
 *    only timer used anywhere is `setTimeout(fn, 0)`, to step out of a layout
 *    pass — never to wait for one.
 *
 * `Repeat(...).virtualScroll(...)` IS used here. It requires the V2 decorators —
 * under V1 it fails outright with "__RepeatVirtualScroll2Impl(-1) it is not
 * allowed to use Repeat virtualScroll inside a @Component!" and then silently
 * stops tracking the array, which is why the V1 revision of this page could
 * never grow past its first page.
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { FeedItem, FeedSource } from '../model/FeedItem';
import { AnchorKeeper } from '../scroll/AnchorKeeper';

/** Rows per page, both directions. */
const PAGE_SIZE: number = 20;

/**
 * How close to the END the viewport must get before the next page is appended,
 * in rows. Purely position based, so it behaves identically for a finger, a
 * crown or a programmatic scroll.
 */
const PREFETCH_ROWS: number = 2;

/**
 * How far past the top the user must pull, in vp, before releasing triggers a
 * load of older data.
 *
 * Loading merely on "the viewport is near row 0" is wrong for this page: the
 * page would insert 20 rows above before the user ever saw where the top was,
 * so the anchoring is impossible to observe. Requiring an explicit pull past the
 * top and then a release means the top stays put on screen until the user asks
 * for more, exactly like a pull-to-refresh — but driven by scroll events only,
 * so a watch's digital crown produces `onScrollStop` the same way.
 */
const PULL_THRESHOLD_VP: number = 80;

/** Steps in the pull progress indicator. */
const PULL_STEPS: number = 10;

const DOMAIN: number = 0x0000;
const TAG: string = 'ListPage';

/**
 * One row.
 *
 * `@Param` rather than a plain prop: a deferred row flips `item.ready` when its
 * content arrives, and `@ObservedV2` + `@Trace` on that field is what turns it
 * into a re-render of this one row instead of the whole list.
 */
@ComponentV2
struct FeedRow {
  @Require @Param item: FeedItem;
  /** Bubbles the row's size change up to the anchor keeper. */
  @Event onSized: () => void = () => {
  };

  aboutToAppear(): void {
    if (!this.item.ready) {
      // Stands in for an asynchronous data source. A real one would resolve a
      // promise here; there is deliberately no delay constant, because the
      // right number is unknowable and device dependent. `setTimeout(fn, 0)`
      // only moves the state write out of the current layout pass — it is not
      // a wait.
      setTimeout(() => {
        this.item.ready = true;
      }, 0);
    }
  }

  build() {
    Column({ space: 6 }) {
      if (this.item.ready) {
        Row() {
          Text(this.item.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#E8E8F0')
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('#' + this.item.seq)
            .fontSize(12)
            .fontColor('#7A7A92')
        }
        .width('100%')

        Text(this.item.preview)
          .fontSize(13)
          .fontColor('#9A9AB0')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        // Fills whatever height is left. Without this the taller rows are just
        // empty space, which reads as a layout bug rather than as variable rows.
        Column()
          .width('100%')
          .layoutWeight(1)
          .backgroundColor('#1B1B26')
          .borderRadius(8)
      } else {
        // Placeholder. Deliberately shorter than the real row, so the list is
        // forced to re-lay out when the content lands.
        Row({ space: 10 }) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color('#6C7BFF')
          Text('加载中…  #' + this.item.seq)
            .fontSize(13)
            .fontColor('#6A6A82')
          Blank()
        }
        .width('100%')
        .height(28)
      }
    }
    .width('100%')
    .height(this.item.ready ? this.item.height : this.item.skeletonHeight)
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.item.ready ? '#14141C' : '#0E0E14')
    .borderRadius(12)
    .onAreaChange((_oldValue: Area, _newValue: Area) => {
      // Fires both when a row first appears and when its height changes.
      this.onSized();
    })
  }
}

@Entry
@ComponentV2
struct ListPage {
  /**
   * Seeded at declaration. Assigning a @Local array from `aboutToAppear` lands
   * inside the routed page's first render pass, and ArkUI rejects state writes
   * there ("State variable ... has changed during render").
   */
  @Local items: FeedItem[] = FeedSource.page(FeedSource.START_SEQ, PAGE_SIZE);
  @Local loadingNewer: boolean = false;
  @Local loadingOlder: boolean = false;
  /** Initialised eagerly so the strip is populated on the first frame. */
  @Local hud: string = '共 ' + PAGE_SIZE + ' 条  ·  首项 0  ·  锚定修正 0 次';
  /**
   * Pull progress for the indicator strip: -1 idle, 0..PULL_STEPS-1 pulling,
   * PULL_STEPS ready to release. Quantised on purpose — `onScrollFrameBegin`
   * runs every frame, and writing state at that rate would re-render the strip
   * continuously.
   */
  @Local pullStep: number = -1;
  /**
   * Status-bar inset in vp, published by `EntryAbility` before the content is
   * loaded. `@StorageProp` is a V1 decorator, so it is read directly instead.
   */
  @Local topInsetPx: number = AppStorage.get<number>('topSafeInsetPx') ?? 0;

  private scroller: ListScroller = new ListScroller();
  private keeper: AnchorKeeper = new AnchorKeeper();

  /** Topmost / bottommost visible row, kept current by `onScrollIndex`. */
  private firstVisible: number = 0;
  private lastVisible: number = 0;
  /** Next sequence to prepend downwards; < MIN_SEQ means history is exhausted. */
  private olderFrom: number = 0;
  /** Next sequence to append upwards; > MAX_SEQ means the end is reached. */
  private newerFrom: number = 0;
  /** True while a scroll is in progress. */
  private scrolling: boolean = false;

  /**
   * Guards against appending the instant the list appears. `onScrollIndex` fires
   * during the first layout with `start = 0`, which would otherwise fire
   * immediately and never stop. The bottom only becomes eligible once the
   * viewport has actually moved away from the end.
   */
  private bottomArmed: boolean = false;

  /** True while the viewport is pinned at row 0, maintained via scroll events. */
  private atTop: boolean = false;
  /** Pull accumulated past the top, in vp. Reset whenever the top is left. */
  private pull: number = 0;

  /**
   * A load finished while the list was still moving, so the hold is deferred to
   * `onScrollStop`.
   *
   * Starting the hold mid-scroll is what corrupted the anchor's calibration: the
   * two samples that determine how `extraOffset` maps onto the screen were taken
   * while inertia was still moving the list, so they disagreed and the correction
   * came out wrong. Waiting for the scroll to stop costs nothing — the anchor is
   * captured before the insert either way.
   */
  private beginOnSettle: boolean = false;

  aboutToAppear(): void {
    this.keeper.attach(this.scroller);
    // The anchor lands *after* `onScrollStop` has already run, so without this
    // the strip would report the pre-correction position.
    this.keeper.onSettled = () => {
      this.refreshHud();
    };
    // Plain fields only — no @Local writes during the first render pass.
    this.olderFrom = FeedSource.START_SEQ - 1;
    this.newerFrom = FeedSource.START_SEQ + PAGE_SIZE;
  }

  aboutToDisappear(): void {
    this.keeper.release();
  }

  /**
   * Begins the anchor hold, or defers it to `onScrollStop` if the list is still
   * moving. Calibrating mid-fling produces a wrong mapping; see `beginOnSettle`.
   */
  private startHold(): void {
    if (this.scrolling) {
      this.beginOnSettle = true;
    } else {
      this.keeper.begin();
    }
  }

  private refreshHud(): void {
    const held: number = this.keeper.heldIndex();
    this.hud = '共 ' + this.items.length + ' 条  ·  首项 ' + this.firstVisible +
      '  ·  锚定修正 ' + this.keeper.restores + ' 次' +
      (held >= 0 ? '  ·  保持中 #' + held : '');
  }

  /**
   * The single place paging is decided. Called from `onScrollIndex`, which the
   * digital crown drives exactly like a finger — no gesture handling anywhere.
   */
  private onVisibleRangeChanged(start: number, end: number): void {
    this.firstVisible = start;
    this.lastVisible = end;

    // `atTop` is derived from the visible range rather than from `onReachStart`
    // alone, so it is correct on the first layout too. Leaving row 0 cancels any
    // pull in progress: the top is no longer where the user is.
    if (start === 0) {
      this.atTop = true;
    } else {
      this.atTop = false;
      this.pull = 0;
      if (this.pullStep !== -1) {
        this.pullStep = -1;
      }
    }

    // Appending still prefetches, because it cannot move what is already above
    // the viewport, so there is nothing to preserve and nothing to observe.
    if (end < this.items.length - 1 - PREFETCH_ROWS) {
      this.bottomArmed = true;
    }
    if (this.bottomArmed && end >= this.items.length - 1 - PREFETCH_ROWS) {
      this.bottomArmed = false;
      this.loadNewer();
    }
  }

  /**
   * Accumulates how far the user has pulled past the top.
   *
   * `onScrollFrameBegin` reports the amount the list is *about to* scroll, before
   * clamping, so while the viewport is pinned at row 0 every further downward
   * request is pure pull. Scrolling toward the start is a negative offset, so the
   * magnitude of a negative offset is the pull distance.
   *
   * This is a frame-level scroll hook, not a gesture: a watch's digital crown
   * drives it exactly like a finger.
   */
  private onScrollFrame(offset: number, state: ScrollState): void {
    if (!this.atTop || state !== ScrollState.Scroll || offset >= 0) {
      return;
    }
    this.pull += -offset;
    const step: number = this.pull >= PULL_THRESHOLD_VP
      ? PULL_STEPS
      : Math.floor(this.pull / PULL_THRESHOLD_VP * PULL_STEPS);
    if (step !== this.pullStep) {
      this.pullStep = step;
    }
  }

  /**
   * The pull is only acted on when the user lets go — so the top position stays
   * on screen while they are deciding, which is the whole point.
   */
  private onScrollReleased(): void {
    const ready: boolean = this.atTop && this.pull >= PULL_THRESHOLD_VP;
    this.pull = 0;
    if (this.pullStep !== -1) {
      this.pullStep = -1;
    }
    if (ready) {
      hilog.info(DOMAIN, TAG, 'pull released past threshold -> loadOlder');
      this.loadOlder();
    } else if (this.atTop) {
      hilog.info(DOMAIN, TAG, 'pull released under threshold, ignored');
    }
  }

  /**
   * Append the next page at the bottom.
   *
   * No `shift()` here: nothing was inserted above the anchor, so its index is
   * still valid. The keeper still runs, because arriving rows change the layout
   * under the viewport as they settle.
   */
  private loadNewer(): void {
    if (this.loadingNewer || this.newerFrom > FeedSource.MAX_SEQ) {
      return;
    }
    this.loadingNewer = true;
    const from: number = this.newerFrom;

    // `setTimeout(fn, 0)` is only here to leave the layout pass that raised
    // `onScrollIndex` before touching state. It is not a simulated latency.
    setTimeout(() => {
      this.keeper.capture(this.firstVisible);
      const page: FeedItem[] = FeedSource.page(from, PAGE_SIZE);
      this.items = this.items.concat(page);
      this.newerFrom = from + page.length;
      this.loadingNewer = false;
      // Appending cannot move what is already above the viewport, but the rows
      // arriving still change the layout underneath, so the hold is still worth
      // taking — just not while the list is moving.
      this.startHold();
      this.refreshHud();
      hilog.info(DOMAIN, TAG, 'loadNewer from=%{public}d -> items=%{public}d',
        from, this.items.length);
    }, 0);
  }

  /**
   * Prepend the previous page when the viewport reaches the top.
   *
   * This is the case that genuinely needs the anchor: 20 rows land *above* the
   * viewport, so the visible content would otherwise jump 20 rows.
   */
  private loadOlder(): void {
    if (this.loadingOlder || this.olderFrom < FeedSource.MIN_SEQ) {
      return;
    }
    this.loadingOlder = true;
    const from: number = Math.max(FeedSource.MIN_SEQ, this.olderFrom - PAGE_SIZE + 1);
    const count: number = this.olderFrom - from + 1;

    setTimeout(() => {
      // Top-aligned: the viewport is at the very top by definition here, so
      // `y = 0` is both simpler and more accurate than a measured offset.
      this.keeper.capture(this.firstVisible, true);

      const page: FeedItem[] = FeedSource.page(from, count);
      this.items = page.concat(this.items);
      this.olderFrom = from - 1;

      // Everything shifted down by `page.length`, so the anchored row now lives
      // that many positions further along.
      this.keeper.shift(page.length);

      this.loadingOlder = false;
      this.startHold();
      this.refreshHud();
      hilog.info(DOMAIN, TAG, 'loadOlder from=%{public}d n=%{public}d -> items=%{public}d',
        from, page.length, this.items.length);
    }, 0);
  }

  /**
   * Fixed-height indicator, so the pull never changes the List's layout — the
   * top row stays exactly where it is while the user pulls, which is what makes
   * the anchoring observable.
   */
  @Builder
  pullStrip() {
    Row() {
      if (this.loadingOlder) {
        LoadingProgress().width(16).height(16).color('#6C7BFF')
        Text('正在加载更早的数据…').fontSize(12).fontColor('#8A8AA8').margin({ left: 8 })
      } else if (this.pullStep >= PULL_STEPS) {
        Text('松开即可加载更早的数据').fontSize(12).fontColor('#7CE0A0')
      } else if (this.pullStep >= 0) {
        Text('继续下拉加载更早的数据  ' + '█'.repeat(this.pullStep) +
          '░'.repeat(PULL_STEPS - this.pullStep)).fontSize(12).fontColor('#8A8AA8')
      } else {
        Text('已到顶部 · 下拉一段距离后松手可加载更早的数据')
          .fontSize(12).fontColor('#5A5A70')
      }
    }
    .width('100%')
    .height(28)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  footer() {
    Row() {
      if (this.loadingNewer) {
        LoadingProgress().width(20).height(20).color('#6C7BFF')
        Text('加载中…').fontSize(13).fontColor('#7A7A92').margin({ left: 8 })
      } else if (this.newerFrom > FeedSource.MAX_SEQ) {
        Text('— 已经到底了 —').fontSize(13).fontColor('#5A5A70')
      } else {
        Text('继续滚动加载更多').fontSize(13).fontColor('#5A5A70')
      }
    }
    .width('100%')
    .height(40)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  topBar() {
    Row() {
      Button('返回')
        .fontSize(14)
        .height(34)
        .backgroundColor('#22222E')
        .fontColor('#D8D8E4')
        .onClick(() => {
          this.getUIContext().getRouter().back();
        })
      Text('长列表 · 滚动分页 · 滚动锚定')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#E8E8F0')
        .margin({ left: 12 })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
  }

  build() {
    Column() {
      this.topBar()

      Text(this.hud)
        .fontSize(11)
        .fontColor('#6A6A82')
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 6 })

      this.pullStrip()

      List({ space: 10, scroller: this.scroller }) {
        Repeat<FeedItem>(this.items)
          .each((ri: RepeatItem<FeedItem>) => {
            ListItem() {
              FeedRow({
                item: ri.item,
                onSized: () => {
                  this.keeper.notifyLayoutChanged();
                }
              })
            }
          })
          .key((item: FeedItem) => item.id)
          .virtualScroll({ totalCount: this.items.length })
      }
      .width('100%')
      .layoutWeight(1)
      .cachedCount(3)
      .scrollBar(BarState.Auto)
      // ---- paging, driven entirely by scroll position ---------------------
      .onScrollIndex((start: number, end: number) => {
        // A real scroll happened — this is what releases the anchor keeper's
        // pending correction. Driven by the crown exactly like a finger.
        this.keeper.onScrollSettled();
        this.onVisibleRangeChanged(start, end);
      })
      .onReachEnd(() => {
        hilog.info(DOMAIN, TAG, 'onReachEnd items=%{public}d', this.items.length);
      })
      // ---- pull past the top ----------------------------------------------
      .onReachStart(() => {
        // Sets the flag only. It deliberately does NOT clear `pull`: on device
        // this callback fires again while the spring edge effect settles, which
        // wiped an in-progress pull of 271 vp down to 0 just before release.
        // The pull is cleared when the viewport leaves row 0, and on release.
        this.atTop = true;
      })
      .onScrollFrameBegin((offset: number, state: ScrollState) => {
        this.onScrollFrame(offset, state);
        return { offsetRemain: offset };
      })
      // ---- scroll lifecycle ----------------------------------------------
      .onScrollStart(() => {
        this.scrolling = true;
        // The user (or the crown) has taken over: stop holding immediately so
        // the keeper never fights them.
        this.keeper.release();
      })
      .onScrollStop(() => {
        this.scrolling = false;
        this.keeper.onScrollSettled();
        if (this.beginOnSettle) {
          this.beginOnSettle = false;
          this.keeper.begin();
        }
        this.onScrollReleased();
        this.refreshHud();
      })

      // Outside the List on purpose: a sibling child next to a
      // `virtualScroll` Repeat breaks its virtual-scroll implementation.
      this.footer()
    }
    .width('100%')
    .height('100%')
    .padding({ top: px2vp(this.topInsetPx) })
    .backgroundColor('#08080C')
  }
}
