/*
 * ListPage.ets — demo host for the `AnchoredPaging` scroll effect.
 *
 * This page is deliberately *only* business logic:
 *
 *   · what a row looks like            (FeedRow)
 *   · where the data comes from        (FeedSource)
 *   · how many rows a page holds       (PAGE_SIZE)
 *   · how it loads older / newer data  (loadOlder / loadNewer)
 *
 * Everything about *scrolling* — when a top pull counts as a request, when the
 * end prefetches, and how the reading position survives a layout change — lives
 * in `../scroll/AnchoredPaging.ets` and is configured, not inherited. Dropping
 * that effect into an existing project means constructing one `AnchoredPaging`
 * and wiring six callbacks; none of the host's own constants or loading logic
 * has to move.
 *
 * The page also follows three project-wide constraints:
 *
 * 1. **V2 state management** (`@ComponentV2` / `@Local` / `@Param` /
 *    `@ObservedV2` / `@Trace`). V1 and V2 components cannot be mixed in one tree,
 *    and `Repeat(...).virtualScroll(...)` only works under V2 — under V1 it
 *    silently stops tracking the array.
 * 2. **Scroll events only, no gesture listeners** — a watch's digital crown
 *    produces scroll events and no touch gestures.
 * 3. **No `setTimeout(fn, ms)`** — only `setTimeout(fn, 0)`, and only to step out
 *    of a layout callback.
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { FeedItem, FeedSource } from '../model/FeedItem';
import { AnchoredPaging, PULL_IDLE } from '../scroll/AnchoredPaging';

/** Business constant: rows per page. Belongs to the host, not to the effect. */
const PAGE_SIZE: number = 20;

const DOMAIN: number = 0x0000;
const TAG: string = 'ListPage';

/**
 * One row. `@Param` rather than a plain prop: a deferred row flips
 * `item.ready` when its content arrives, and `@ObservedV2` + `@Trace` on that
 * field turns it into a re-render of this one row instead of the whole list.
 */
@ComponentV2
struct FeedRow {
  @Require @Param item: FeedItem;
  /** Bubbles the row's size change up to the scroll effect. */
  @Event onSized: () => void = () => {
  };

  aboutToAppear(): void {
    if (!this.item.ready) {
      // Stands in for an asynchronous data source. A real one would resolve a
      // promise here; there is deliberately no delay constant, because the right
      // number is unknowable and device dependent. `setTimeout(fn, 0)` only moves
      // the state write out of the current layout pass — it is not a wait.
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
  /**
   * Status-bar inset in vp, published by `EntryAbility` before the content is
   * loaded. `@StorageProp` is a V1 decorator, so it is read directly instead.
   */
  @Local topInsetPx: number = AppStorage.get<number>('topSafeInsetPx') ?? 0;

  private scroller: ListScroller = new ListScroller();

  /**
   * The entire scroll effect, configured rather than inherited.
   *
   * These are the values this page happens to want; an existing project passes
   * its own, or omits the argument entirely to take the defaults.
   */
  private readonly paging: AnchoredPaging = new AnchoredPaging({
    prefetchRows: 2,        // rows from the end before asking for the next page
    pullThresholdVp: 80,    // vp past the top before a release loads earlier data
    pullSteps: 10,          // progress granularity of the indicator
    anchor: {
      toleranceVp: 1.0,     // anchor considered restored within this many vp
      maxCorrections: 40,   // runaway guard for one hold
      stallLimit: 3         // give up after this many unmeasurable samples
    }
  });

  /** Business state: where the next page starts, in each direction. */
  private olderFrom: number = 0;
  private newerFrom: number = 0;

  aboutToAppear(): void {
    this.paging.attach(this.scroller);
    // The effect never owns the data — it asks, and the host answers.
    this.paging.onRequestOlder = () => {
      this.loadOlder();
    };
    this.paging.onRequestNewer = () => {
      this.loadNewer();
    };
    // Plain fields only — no @Local writes during the first render pass.
    this.olderFrom = FeedSource.START_SEQ - 1;
    this.newerFrom = FeedSource.START_SEQ + PAGE_SIZE;
  }

  aboutToDisappear(): void {
    this.paging.release();
  }

  // ---------------------------------------------------------------------------
  // Business logic. None of this is known to the scroll effect.
  // ---------------------------------------------------------------------------

  /** Append the next page. Nothing was inserted above, so no anchor shift. */
  private loadNewer(): void {
    if (this.loadingNewer || this.newerFrom > FeedSource.MAX_SEQ) {
      return;
    }
    this.loadingNewer = true;
    const from: number = this.newerFrom;

    // `setTimeout(fn, 0)` is only here to leave the layout pass that raised the
    // scroll event before touching state. It is not a simulated latency.
    setTimeout(() => {
      const page: FeedItem[] = FeedSource.page(from, PAGE_SIZE);
      this.paging.insertAnchored(0, () => {
        this.items = this.items.concat(page);
      });
      this.newerFrom = from + page.length;
      this.loadingNewer = false;
      hilog.info(DOMAIN, TAG, 'loadNewer from=%{public}d -> items=%{public}d',
        from, this.items.length);
    }, 0);
  }

  /** Prepend the previous page. The rows land above, so they shift the anchor. */
  private loadOlder(): void {
    if (this.loadingOlder || this.olderFrom < FeedSource.MIN_SEQ) {
      return;
    }
    this.loadingOlder = true;
    const from: number = Math.max(FeedSource.MIN_SEQ, this.olderFrom - PAGE_SIZE + 1);
    const count: number = this.olderFrom - from + 1;

    setTimeout(() => {
      const page: FeedItem[] = FeedSource.page(from, count);
      this.paging.insertAnchored(page.length, () => {
        this.items = page.concat(this.items);
      });
      this.olderFrom = from - 1;
      this.loadingOlder = false;
      hilog.info(DOMAIN, TAG, 'loadOlder from=%{public}d n=%{public}d -> items=%{public}d',
        from, page.length, this.items.length);
    }, 0);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  /** Fixed-height, so a pull never changes the List's layout. */
  @Builder
  pullStrip() {
    Row() {
      if (this.loadingOlder) {
        LoadingProgress().width(16).height(16).color('#6C7BFF')
        Text('正在加载更早的数据…').fontSize(12).fontColor('#8A8AA8').margin({ left: 8 })
      } else if (this.paging.pullStep >= this.paging.config.pullSteps) {
        Text('松开即可加载更早的数据').fontSize(12).fontColor('#7CE0A0')
      } else if (this.paging.pullStep > PULL_IDLE) {
        Text('继续下拉加载更早的数据  ' + '█'.repeat(this.paging.pullStep) +
          '░'.repeat(this.paging.config.pullSteps - this.paging.pullStep))
          .fontSize(12).fontColor('#8A8AA8')
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

      Text('共 ' + this.items.length + ' 条  ·  首项 ' + this.paging.firstVisible +
        '  ·  锚定修正 ' + this.paging.corrections + ' 次')
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
                  this.paging.handleRowResized();
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
      // ---- the whole wiring: six scroll callbacks -------------------------
      .onScrollIndex((start: number, end: number) => {
        this.paging.handleScrollIndex(start, end, this.items.length);
      })
      .onScrollStart(() => {
        this.paging.handleScrollStart();
      })
      .onScrollStop(() => {
        this.paging.handleScrollStop();
      })
      .onReachStart(() => {
        this.paging.handleReachStart();
      })
      .onScrollFrameBegin((offset: number, state: ScrollState) => {
        return this.paging.handleScrollFrameBegin(offset, state);
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
