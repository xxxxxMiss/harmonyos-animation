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
import { LatencyHarness, LatencyProfile } from '../model/RenderLatency';
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
  /**
   * Position in the list. Needed so the effect can tell a row growing above the
   * reading position — which shoves the reader — from one growing below it,
   * which nobody can see.
   */
  @Require @Param index: number;
  /**
   * Bubbles the row's size change up to the scroll effect, in vp.
   *
   * The delta is reported rather than just a ping: the effect needs it to
   * measure how much layout it absorbed, and the row is the only place that
   * knows it.
   */
  @Event onSized: (index: number, deltaVp: number) => void = () => {
  };

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
        if (this.item.settled) {
          Row() {
            Text((this.item.kind === MsgKind.QUESTION
              ? ('第 ' + this.item.round + ' 轮 · 提问')
              : ('第 ' + this.item.round + ' 轮 · 回答 ' + this.item.slot + ' / ' + this.item.answerCount))
              // The row's own height, on screen. It is the single number the
              // whole effect reacts to, and printing it is what turns "rows
              // render late" from a claim into something observable: on the
              // watch profile it reads 60vp and then climbs to its final value
              // 400-600 ms later.
              + '  ·  ' + this.item.currentHeight + 'vp')
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
            Text('渲染中… ' + this.item.currentHeight + ' → ' + this.item.finalHeight + 'vp')
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
    .height(this.item.currentHeight)
    .padding({ left: 12, right: 16, top: 12, bottom: 12 })
    // Answers are inset so a round reads as one visual block.
    .margin({ left: this.item.kind === MsgKind.QUESTION ? 0 : 20 })
    .backgroundColor(this.item.settled
      ? (this.item.kind === MsgKind.QUESTION ? '#1A1A28' : '#14141C')
      : '#0E0E14')
    .borderRadius(12)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      // Two filters, and both are load-bearing.
      //
      // 1. Width changes are ignored: only a HEIGHT change moves anything below
      //    this row, and only that is worth waking the hold for.
      // 2. `before === 0` is a component being *constructed*, not a row
      //    resizing — `onAreaChange` also fires when a row enters or leaves the
      //    built window, which the hold's own align jump causes. Those carry no
      //    displacement, and counting them made the absorbed-churn readout
      //    meaningless: one rebuild reported every row in the list appearing
      //    from nothing, inflating it from 241 vp to 2128 vp on device.
      const before: number = Number(oldValue.height);
      const after: number = Number(newValue.height);
      if (before > 0 && before !== after) {
        hilog.info(DOMAIN, TAG, 'rowSized %{public}s #%{public}d %{public}svp -> %{public}svp',
          this.item.id, this.index, before.toFixed(0), after.toFixed(0));
        this.onSized(this.index, after - before);
      }
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
  @Local items: FeedItem[] = FeedSource.pageRounds(
    FeedSource.START_ROUND, ROUNDS_PER_PAGE, LatencyHarness.stages(LatencyProfile.WATCH));
  /**
   * Which render-latency profile the demo simulates. Switch it to compare.
   *
   * Defaults to the watch profile on purpose. It used to default to `INSTANT`,
   * which made the page look broken in the other direction: with rows settling
   * on the next tick the hold converges inside a frame or two, so the demo
   * showed *nothing happening at all* — no late rows to observe, no reason for
   * the anchoring to exist. The realistic case is the one worth opening on.
   */
  @Local profile: LatencyProfile = LatencyProfile.WATCH;
  /**
   * Demo-only switch: whether insertions go through the hold at all.
   *
   * Purely a host-side decision — `insertAnchored` is called or it is not, and
   * the effect is untouched. It exists because "the anchor works" and "the rows
   * really do render late" look identical from the outside: both are silent.
   * Turning the hold off is what makes the second one visible, because the
   * displacement it was absorbing then lands on screen.
   */
  @Local anchorOn: boolean = true;
  /** Display only: how many rounds the current rows span. */
  @Local roundsShown: number = ROUNDS_PER_PAGE;
  /** Bumped on every re-seed so `Repeat` rebuilds rows with the new plan. */
  @Local generation: number = 0;
  /** Shown in the HUD so the active profile is visible even off the bar. */
  @Local profileInUse: string = LatencyHarness.label(LatencyProfile.WATCH);
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
    // The initial seed is built in a field initialiser, so its latency plan is
    // started here; every later batch goes through `planRows()`.
    this.planRows(this.items);
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

  /**
   * Starts the latency plan for a freshly created batch of rows.
   *
   * Deliberately NOT done in `FeedRow.aboutToAppear`. `Repeat` reuses row
   * components by position, so a rebuild — a reseed, in particular — does not
   * re-run that lifecycle hook, and the new items would never be scheduled.
   * They then render at `currentHeight == skeletonHeight` forever, which is
   * exactly the "one row stuck on 加载中…" that showed up on device.
   *
   * Scheduling belongs to whoever created the data, not to whoever happens to
   * be rendering it.
   */
  private planRows(rows: FeedItem[]): FeedItem[] {
    for (let i = 0; i < rows.length; i++) {
      if (!rows[i].settled) {
        LatencyHarness.schedule(rows[i], this.profile);
      }
    }
    return rows;
  }

  /** Re-seeds the conversation under a new latency profile. */
  private reseed(profile: LatencyProfile): void {
    this.profile = profile;
    this.generation++;
    const stages: number = LatencyHarness.stages(profile);
    this.items = this.planRows(
      FeedSource.pageRounds(FeedSource.START_ROUND, ROUNDS_PER_PAGE, stages));
    this.profileInUse = LatencyHarness.label(profile);
    this.roundsShown = ROUNDS_PER_PAGE;
    this.olderRound = FeedSource.START_ROUND - 1;
    this.newerRound = FeedSource.START_ROUND + ROUNDS_PER_PAGE;
    this.paging.release();
    // A reseed replaces the whole conversation, so keeping the old offset would
    // drop the reader into the middle of unrelated data.
    this.scroller.scrollToIndex(0, true);
    hilog.info(DOMAIN, TAG, 'reseed profile=%{public}s stages=%{public}d rows=%{public}d',
      LatencyHarness.label(profile), stages, this.items.length);
  }

  @Builder
  profileBar() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        ForEach([LatencyProfile.INSTANT, LatencyProfile.FAST,
          LatencyProfile.WATCH, LatencyProfile.WATCH_STAGED], (p: LatencyProfile) => {
          Text(LatencyHarness.shortLabel(p))
            .fontSize(10)
            .fontColor(this.profile === p ? '#0B0B12' : '#8A8AA8')
            .backgroundColor(this.profile === p ? '#6C7BFF' : '#1A1A28')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(6)
            .onClick(() => {
              this.reseed(p);
            })
        }, (p: LatencyProfile) => String(p))
      }
      .width('100%')

      Row({ space: 8 }) {
        Text(this.anchorOn ? '锚定 开' : '锚定 关')
          .fontSize(10)
          .fontColor(this.anchorOn ? '#0B0B12' : '#E8A0A0')
          .backgroundColor(this.anchorOn ? '#7CE0A0' : '#3A1A22')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(6)
          .onClick(() => {
            this.anchorOn = !this.anchorOn;
          })
        Text(this.anchorOn
          ? ('本次装载吸收了 ' + this.paging.churnVp.toFixed(0) + 'vp 高度变化，画面未移动')
          : '锚定关闭：这些高度变化会直接落在画面上')
          .fontSize(10)
          .fontColor(this.anchorOn ? '#6A6A82' : '#C08080')
          .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12, bottom: 6 })
  }

  // ---------------------------------------------------------------------------
  // Business logic. None of this is known to the scroll effect.
  // ---------------------------------------------------------------------------

  /**
   * Runs a data mutation through the hold — or not, when the demo's anchor
   * switch is off.
   *
   * `insertAnchored` is the *only* thing the host has to remember, and this
   * wrapper is where the host gets to decide whether to use it. With it off the
   * list behaves like a plain List: the insertion lands, late rows grow, and the
   * reader is thrown by exactly `paging.maxDriftVp` — which is the evidence that
   * the latency is real and not something the harness merely logs.
   */
  private mutateAnchored(rowsInsertedAbove: number, mutate: () => void): void {
    if (this.anchorOn) {
      this.paging.insertAnchored(rowsInsertedAbove, mutate);
    } else {
      mutate();
    }
  }

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
      const page: FeedItem[] = this.planRows(FeedSource.pageRounds(fromRound, ROUNDS_PER_PAGE,
        LatencyHarness.stages(this.profile)));
      // 0 rows were inserted above the anchor — this is an append.
      this.mutateAnchored(0, () => {
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
      const page: FeedItem[] = this.planRows(FeedSource.pageRounds(fromRound,
        this.olderRound - fromRound + 1, LatencyHarness.stages(this.profile)));
      // `page.length`, not a constant: the anchor shifts by exactly the number
      // of rows that were inserted above it.
      this.mutateAnchored(page.length, () => {
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
      } else if (this.paging.atTop) {
        Text('已到顶部 · 下拉一段距离后松手可加载更早的对话')
          .fontSize(12).fontColor('#5A5A70')
      } else {
        // The pull only arms at row 0, so saying "已到顶部" whenever the pull is
        // idle told the reader they were at the top right after an anchored load
        // had deliberately left them somewhere else.
        Text('已加载更早的对话 · 回到最早一条再下拉可继续加载')
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
      // `高度变化` is the honest headline number: it is the total size change
      // rows reported while the reader's position was held. The per-correction
      // drift readout is structurally near zero (the framework applies the
      // correction inside the same layout pass as the resize), so printing that
      // would suggest nothing happened.
      Text(this.roundsShown + ' 轮 · ' + this.items.length + ' 条消息  ·  首项 ' +
        this.paging.firstVisible + '  ·  修正 ' + this.paging.corrections + ' 次  ·  高度变化 ' +
        this.paging.churnVp.toFixed(0) + 'vp ·  ' + this.profileInUse)
        .fontSize(11)
        .fontColor('#6A6A82')
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 4 })

      this.profileBar()
      this.pullStrip()

      List({ space: 10, scroller: this.scroller }) {
        Repeat<FeedItem>(this.items)
          .each((ri: RepeatItem<FeedItem>) => {
            ListItem() {
              FeedRow({
                item: ri.item,
                index: ri.index,
                onSized: (index: number, deltaVp: number) => {
                  this.paging.handleRowResized(index, deltaVp);
                }
              })
            }
          })
          .key((item: FeedItem) => this.generation + '/' + item.id)
          // Virtual scrolling was commented out here for several revisions while
          // the hold was being debugged, which quietly turned the demo into a
          // build-everything list: every row stayed built, so every row kept
          // reporting area changes and the anchor's calibration window never
          // behaved the way a real long list makes it behave. It is required for
          // the case this effect exists for, and it works under V2.
          .virtualScroll({ totalCount: this.items.length })
      }
      .width('100%')
      .layoutWeight(1)
      // Off-screen rows kept built, on top of the built window. A row that has
      // scrolled just out of view still finishes its late render here instead of
      // being recycled mid-flight.
      .cachedCount(8)
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
