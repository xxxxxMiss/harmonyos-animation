/*
 * ListPage.ets — demo host for the `AnchoredPaging` scroll effect.
 *
 * This page is deliberately *only* business logic:
 *
 *   · what a message looks like        (FeedRow)
 *   · where the data comes from        (FeedSource)
 *   · how much a page holds            (ROUNDS_PER_PAGE — counted in ROUNDS)
 *   · how it loads older / newer data  (loadOlder / loadNewer)
 *
 * Everything about *scrolling* — when a top pull counts as a request, when the
 * end prefetches, and how the reading position survives a layout change — lives
 * in `../scroll/AnchoredPaging.ets` and is configured, not inherited.
 *
 * The page size is counted in rounds, not rows
 * --------------------------------------------
 * This is a conversation: one round is one question plus 1..N answers, so a page
 * of `ROUNDS_PER_PAGE` rounds delivers a **different number of rows every time**
 * (between 2x and 6x the round count). There is no row-count constant anywhere,
 * and there cannot be.
 *
 * Nothing in the scroll effect had to change for that. It is handed the length
 * that actually came back — `insertAnchored(rows.length, …)` — and never a
 * configured page size, so a flat feed and a round-based feed drive it
 * identically. See `docs/LIST-SCROLL-ANCHOR.md` §0.1.
 *
 * Three project-wide constraints also apply:
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
import { FeedItem, FeedSource, MsgKind } from '../model/FeedItem';
import { AnchoredPaging, PULL_IDLE } from '../scroll/AnchoredPaging';

/**
 * Business constant: how many **rounds** one page holds.
 *
 * Note what is NOT here: a rows-per-page constant. A round carries 1..N answers,
 * so the row count per page is computed from whatever came back. Everything that
 * needs a count — `insertAnchored`, the list's `totalCount`, the prefetch
 * threshold — reads the real array length.
 */
const ROUNDS_PER_PAGE: number = 5;

const DOMAIN: number = 0x0000;
const TAG: string = 'ListPage';

/**
 * One message. `@Param` rather than a plain prop: a deferred row flips
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

  /** The 4vp accent bar that makes the round structure legible at a glance. */
  @Builder
  accent() {
    Column()
      .width(4)
      .height('100%')
      .backgroundColor(this.item.kind === MsgKind.QUESTION ? '#6C7BFF' : '#33334A')
      .borderRadius(2)
  }

  build() {
    Row({ space: 12 }) {
      this.accent()

      Column({ space: 6 }) {
        if (this.item.ready) {
          Row() {
            Text(this.item.kind === MsgKind.QUESTION
              ? ('第 ' + this.item.round + ' 轮 · 提问')
              : ('第 ' + this.item.round + ' 轮 · 回答 ' + this.item.slot + ' / ' + this.item.answerCount))
              .fontSize(11)
              .fontColor(this.item.kind === MsgKind.QUESTION ? '#8A9BFF' : '#6A6A82')
            Blank()
          }
          .width('100%')

          Text(this.item.title)
            .fontSize(this.item.kind === MsgKind.QUESTION ? 16 : 15)
            .fontWeight(this.item.kind === MsgKind.QUESTION ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.item.kind === MsgKind.QUESTION ? '#E8E8F0' : '#C8C8DC')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Text(this.item.preview)
            .fontSize(12)
            .fontColor('#7A7A92')
            .maxLines(1)
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
              .width(16)
              .height(16)
              .color('#6C7BFF')
            Text('加载中…  ' + this.item.preview)
              .fontSize(12)
              .fontColor('#6A6A82')
            Blank()
          }
          .width('100%')
          .height(24)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(this.item.ready ? this.item.height : this.item.skeletonHeight)
    .padding({ left: 12, right: 16, top: 12, bottom: 12 })
    // Answers are inset so a round reads as one visual block.
    .margin({ left: this.item.kind === MsgKind.QUESTION ? 0 : 20 })
    .backgroundColor(this.item.ready
      ? (this.item.kind === MsgKind.QUESTION ? '#1A1A28' : '#14141C')
      : '#0E0E14')
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
  @Local items: FeedItem[] = FeedSource.pageRounds(FeedSource.START_ROUND, ROUNDS_PER_PAGE);
  /** Display only: how many rounds the current rows span. */
  @Local roundsShown: number = ROUNDS_PER_PAGE;
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
      // How close the anchored row must come back before the hold is considered
      // restored. 1 vp is ~3.2 device px here — below perception. Tightening it
      // just makes the loop chase pixel quantisation and run into
      // `maxCorrections`; loosening it leaves a visible sliver.
      toleranceVp: 1.0,
      // Anti-runaway budget for ONE hold (reset in `begin()`). A normal hold
      // needs 2 corrections, so this is ~20x headroom. It exists for rows that
      // resize on every layout pass: without it the effect would keep issuing
      // scrollToIndex forever and would fight the user's own scrolling.
      maxCorrections: 40,
      // Consecutive samples where the anchored row cannot be measured — with
      // virtualScroll a row outside the built window reports no rect. 1 sample
      // is a normal transient, 3 is enough grace without ever waiting on a clock.
      stallLimit: 3
    }
  });

  /** Business state: the next ROUND to load, in each direction. */
  private olderRound: number = 0;
  private newerRound: number = 0;

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
    this.olderRound = FeedSource.START_ROUND - 1;
    this.newerRound = FeedSource.START_ROUND + ROUNDS_PER_PAGE;
  }

  aboutToDisappear(): void {
    this.paging.release();
  }

  // ---------------------------------------------------------------------------
  // Business logic. None of this is known to the scroll effect.
  // ---------------------------------------------------------------------------

  /**
   * Append the next N rounds.
   *
   * `page.length` is whatever that batch turned out to be — 2x to 6x the round
   * count — and it is computed here, never configured anywhere.
   */
  private loadNewer(): void {
    if (this.loadingNewer || this.newerRound > FeedSource.MAX_ROUND) {
      return;
    }
    this.loadingNewer = true;
    const fromRound: number = this.newerRound;

    // `setTimeout(fn, 0)` is only here to leave the layout pass that raised the
    // scroll event before touching state. It is not a simulated latency.
    setTimeout(() => {
      const page: FeedItem[] = FeedSource.pageRounds(fromRound, ROUNDS_PER_PAGE);
      // 0 rows were inserted above the anchor — this is an append.
      this.paging.insertAnchored(0, () => {
        this.items = this.items.concat(page);
      });
      this.newerRound = fromRound + FeedSource.roundsIn(page);
      this.roundsShown += FeedSource.roundsIn(page);
      this.loadingNewer = false;
      hilog.info(DOMAIN, TAG, 'loadNewer rounds=%{public}d rows=%{public}d -> total %{public}d',
        FeedSource.roundsIn(page), page.length, this.items.length);
    }, 0);
  }

  /** Prepend the previous N rounds. Every row of them lands above the anchor. */
  private loadOlder(): void {
    if (this.loadingOlder || this.olderRound < FeedSource.MIN_ROUND) {
      return;
    }
    this.loadingOlder = true;
    // Walk backwards, clamped at the start of the conversation.
    const fromRound: number = Math.max(FeedSource.MIN_ROUND,
      this.olderRound - ROUNDS_PER_PAGE + 1);

    setTimeout(() => {
      const page: FeedItem[] = FeedSource.pageRounds(fromRound, this.olderRound - fromRound + 1);
      // `page.length`, not a constant: the anchor shifts by exactly the number
      // of rows that were inserted above it.
      this.paging.insertAnchored(page.length, () => {
        this.items = page.concat(this.items);
      });
      this.olderRound = fromRound - 1;
      this.roundsShown += FeedSource.roundsIn(page);
      this.loadingOlder = false;
      hilog.info(DOMAIN, TAG, 'loadOlder rounds=%{public}d rows=%{public}d -> total %{public}d',
        FeedSource.roundsIn(page), page.length, this.items.length);
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
        Text('正在加载更早的对话…').fontSize(12).fontColor('#8A8AA8').margin({ left: 8 })
      } else if (this.paging.pullStep >= this.paging.config.pullSteps) {
        Text('松开即可加载更早的对话').fontSize(12).fontColor('#7CE0A0')
      } else if (this.paging.pullStep > PULL_IDLE) {
        Text('继续下拉加载更早的对话  ' + '█'.repeat(this.paging.pullStep) +
          '░'.repeat(this.paging.config.pullSteps - this.paging.pullStep))
          .fontSize(12).fontColor('#8A8AA8')
      } else {
        Text('已到顶部 · 下拉一段距离后松手可加载更早的对话')
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
      } else if (this.newerRound > FeedSource.MAX_ROUND) {
        Text('— 已经是最新的对话了 —').fontSize(13).fontColor('#5A5A70')
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
      Text('对话列表 · 按轮次分页 · 滚动锚定')
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

      // The row count and the round count are both shown on purpose: the first
      // is derived, the second is what the page size is actually counted in.
      Text(this.roundsShown + ' 轮 · ' + this.items.length + ' 条消息  ·  首项 ' +
        this.paging.firstVisible + '  ·  锚定修正 ' + this.paging.corrections + ' 次')
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
      // ---- the whole wiring: five scroll callbacks + row onAreaChange ------
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
