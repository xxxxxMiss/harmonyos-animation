/*
 * AnchoredPaging.ets
 *
 * A drop-in scroll effect: **pull past the top to page backwards, reach the end
 * to page forwards, and never lose the reader's place while the data changes.**
 *
 * It knows nothing about your data
 * --------------------------------
 * There is no `pageSize`, no item type, no fetch, no `loadOlder` here. The
 * effect never touches your array — it tells you *when* to load, and gives you
 * one call in which to do it so the anchor can be held across the mutation:
 *
 *     const paging = new AnchoredPaging();
 *     paging.onRequestOlder = () => { this.items = older.concat(this.items); };  // your logic
 *     paging.onRequestNewer = () => { this.items = this.items.concat(newer); };
 *
 * That split is the point. An existing project keeps its own data source, its
 * own page size, its own loading flags, its own empty/error states. What it
 * cannot easily write itself is the anchoring, and that is all this provides.
 *
 * Everything tunable is a parameter
 * ---------------------------------
 * `prefetchRows`, the pull threshold, the progress granularity, the anchor
 * tolerance and its runaway budgets are all in `AnchoredPagingConfig`. Nothing
 * that a host might already have an opinion about is hardcoded.
 *
 * Wiring (scroll events only — works with a watch crown)
 * -----------------------------------------------------
 *     List({ scroller: this.scroller }) { ...your rows... }
 *       .onScrollIndex((s, e) => paging.handleScrollIndex(s, e, this.items.length))
 *       .onScrollStart(() => paging.handleScrollStart())
 *       .onScrollStop(() => paging.handleScrollStop())
 *       .onReachStart(() => paging.handleReachStart())
 *       .onScrollFrameBegin((o, st) => paging.handleScrollFrameBegin(o, st))
 *     // and in your row: .onAreaChange(() => paging.handleRowResized())
 *
 * Then wrap the mutation of an insertion that happens *above* the viewport:
 *
 *     paging.insertAnchored(older.length, () => {
 *       this.items = older.concat(this.items);
 *     });
 *
 * `insertAnchored` captures the anchor before `mutate()` runs and starts holding
 * after it, so the host never has to sequence those calls correctly by hand.
 *
 * No gestures, no wall-clock waits
 * --------------------------------
 * Only scroll events are used, so a digital crown drives it exactly like a
 * finger. The only timer anywhere is `setTimeout(fn, 0)`, and only to leave a
 * layout callback — never to wait for something to finish. See
 * `docs/LIST-SCROLL-ANCHOR.md` for why both matter.
 */

import { AnchorKeeper, AnchorOptions } from './AnchorKeeper';

/**
 * Everything the effect lets you tune. Every field is optional and has a
 * default, so `new AnchoredPaging()` works, and an existing project can supply
 * only the values it disagrees with.
 */
export interface AnchoredPagingOptions {
  /**
   * How many rows from the end the viewport must be before `onRequestNewer`
   * fires. Raise it for a slower data source, lower it to load later.
   */
  prefetchRows?: number;
  /** vp the user must pull past row 0 before releasing triggers `onRequestOlder`. */
  pullThresholdVp?: number;
  /** Granularity of `pullStep` (the reported range is `0..pullSteps`). */
  pullSteps?: number;
  /** Forwarded to `AnchorKeeper`; see `AnchorOptions`. */
  anchor?: AnchorOptions;
}

/** Resolved, fully-populated configuration. */
export class AnchoredPagingConfig {
  readonly prefetchRows: number;
  readonly pullThresholdVp: number;
  readonly pullSteps: number;
  readonly anchor: AnchorOptions;

  constructor(options?: AnchoredPagingOptions) {
    const o: AnchoredPagingOptions = options ?? {};
    this.prefetchRows = o.prefetchRows ?? 2;
    this.pullThresholdVp = o.pullThresholdVp ?? 80;
    this.pullSteps = o.pullSteps ?? 10;
    this.anchor = o.anchor ?? {};
  }
}

/** `-1` = idle, `0..pullSteps-1` = pulling, `pullSteps` = release to load. */
export const PULL_IDLE: number = -1;

/**
 * The effect.
 *
 * `@ObservedV2` so a `@ComponentV2` can bind directly to `pullStep` / `holding`
 * in its `build()` without copying them into `@Local` — the state lives here,
 * not in the page.
 */
@ObservedV2
export class AnchoredPaging {
  readonly config: AnchoredPagingConfig;

  /**
   * Ask the host to load earlier data and insert it above the viewport. The
   * host does the insertion, wrapped in `insertAnchored`.
   */
  onRequestOlder: () => void = () => {
  };
  /** Ask the host to load later data and append it below the viewport. */
  onRequestNewer: () => void = () => {
  };

  /** Pull progress for an indicator: `PULL_IDLE`, or `0..config.pullSteps`. */
  @Trace pullStep: number = PULL_IDLE;
  /** True while the position is being held across a layout change. */
  @Trace holding: boolean = false;
  /** Corrections applied in total — useful as a diagnostic readout. */
  @Trace corrections: number = 0;
  /** True while the viewport is pinned at row 0. */
  @Trace atTop: boolean = true;
  /**
   * Topmost visible row. Traced so a host that displays it updates live —
   * `handleScrollIndex` is where it changes, and that is not a state write the
   * host would otherwise see.
   */
  @Trace firstVisible: number = 0;
  /**
   * How far the anchored row drifted during the current hold, in vp, and the
   * worst it got. These are the displacement the hold absorbed: what the reader
   * would have been thrown by had nothing been holding the position. Diagnostics
   * only — nothing in the effect reads them back.
   */
  @Trace lastDriftVp: number = 0;
  @Trace maxDriftVp: number = 0;
  /** Layout changes the current hold has been told about. See `AnchorKeeper`. */
  @Trace layoutEvents: number = 0;
  /** Height churn absorbed by the current hold, in vp. See `AnchorKeeper`. */
  @Trace churnVp: number = 0;

  private readonly keeper: AnchorKeeper;
  private scroller: ListScroller | undefined = undefined;

  /** Bottommost visible row, from `handleScrollIndex`. Not traced: unused by UI. */
  private lastVisible: number = 0;
  /** Total row count as last reported by the host. */
  private totalRows: number = 0;

  /** Pull accumulated past the top, in vp. */
  private pull: number = 0;
  /** True while a scroll is in progress. */
  private scrolling: boolean = false;
  /** A load finished mid-scroll, so the hold is deferred to the stop. */
  private holdOnSettle: boolean = false;
  /** Guards the end-prefetch so the first layout cannot fire it. */
  private endArmed: boolean = false;

  constructor(options?: AnchoredPagingOptions) {
    this.config = new AnchoredPagingConfig(options);
    this.keeper = new AnchorKeeper(this.config.anchor);
    this.keeper.onSettled = () => {
      this.holding = this.keeper.isHolding();
      this.corrections = this.keeper.restores;
      this.lastDriftVp = this.keeper.lastDriftVp;
      this.maxDriftVp = this.keeper.maxDriftVp;
      this.layoutEvents = this.keeper.layoutEvents;
      this.churnVp = this.keeper.churnVp;
    };
  }

  /** Bind to the host's List. Safe to call again if the List is recreated. */
  attach(scroller: ListScroller): void {
    this.scroller = scroller;
    this.keeper.attach(scroller);
  }

  /** True while a scroll is in progress. */
  isScrolling(): boolean {
    return this.scrolling;
  }

  /** Drop the hold, e.g. from `aboutToDisappear`. */
  release(): void {
    this.keeper.release();
    this.holding = false;
  }

  // -------------------------------------------------------------------------
  // Scroll event handlers. Wire each one to the matching List callback.
  // -------------------------------------------------------------------------

  /**
   * @param totalCount the host's own row count — the effect never holds the
   *        data, so it is told how long the list currently is.
   */
  handleScrollIndex(start: number, end: number, totalCount: number): void {
    this.firstVisible = start;
    this.lastVisible = end;
    this.totalRows = totalCount;

    // `atTop` is derived from the visible range rather than from
    // `onReachStart` alone, so it is already correct on the first layout.
    if (start === 0) {
      this.atTop = true;
    } else {
      this.atTop = false;
      this.resetPull();
    }

    // Prefetch at the end. Appending cannot move what is already above the
    // viewport, so there is nothing to preserve and nothing to observe; but the
    // first layout must not fire it, hence the arming flag.
    if (end < totalCount - 1 - this.config.prefetchRows) {
      this.endArmed = true;
    }
    if (this.endArmed && end >= totalCount - 1 - this.config.prefetchRows) {
      this.endArmed = false;
      this.onRequestNewer();
    }
  }

  handleScrollStart(): void {
    this.scrolling = true;
    // The user (or the crown) has taken over: stop holding so the effect never
    // fights them.
    this.keeper.release();
    this.holding = false;
  }

  /** The release at the end of a pull is what triggers the backwards load. */
  handleScrollStop(): void {
    this.scrolling = false;
    this.keeper.onScrollSettled();
    if (this.holdOnSettle) {
      this.holdOnSettle = false;
      this.beginHold();
    }
    const ready: boolean = this.atTop && this.pull >= this.config.pullThresholdVp;
    this.resetPull();
    if (ready) {
      this.onRequestOlder();
    }
  }

  /**
   * Accumulates the pull past the top.
   *
   * `onScrollFrameBegin` reports the amount the list is *about to* scroll, before
   * clamping, so while the viewport is pinned at row 0 every further downward
   * request is pure pull. Scrolling toward the start is a negative offset.
   *
   * Returns the callback result unchanged — the host just forwards it, so it
   * cannot get the `offsetRemain` contract wrong.
   */
  handleScrollFrameBegin(offset: number, state: ScrollState): OnScrollFrameBeginHandlerResult {
    if (this.atTop && state === ScrollState.Scroll && offset < 0) {
      this.pull += -offset;
      const steps: number = this.config.pullSteps;
      const step: number = this.pull >= this.config.pullThresholdVp
        ? steps
        : Math.floor(this.pull / this.config.pullThresholdVp * steps);
      if (step !== this.pullStep) {
        this.pullStep = step;
      }
    }
    return { offsetRemain: offset };
  }

  /**
   * `onReachStart` only sets the flag. It deliberately does NOT clear the pull:
   * on device it fires again while the spring edge effect settles, which wiped a
   * 271 vp pull down to 0 just before release and made the whole feature dead.
   */
  handleReachStart(): void {
    this.atTop = true;
  }

  /**
   * Wire every row's `onAreaChange` to this.
   *
   * @param index the row's index in the list.
   * @param deltaVp the row's signed height change in vp. Reporting both is what
   *        lets the effect measure how much layout it absorbed *above the
   *        reading position* — see `AnchorKeeper.churnVp`.
   */
  handleRowResized(index: number = -1, deltaVp: number = 0): void {
    this.keeper.notifyLayoutChanged(index, deltaVp);
  }

  // -------------------------------------------------------------------------
  // Data mutation
  // -------------------------------------------------------------------------

  /**
   * Runs `mutate()` with the reading position held.
   *
   * @param rowsInsertedAbove how many rows `mutate()` adds *above* the anchor.
   *        Pass `0` when appending at the bottom.
   *
   * When rows go in above, the viewport is at row 0 by definition, so the anchor
   * is pinned to the top rather than to a measured offset — a measured `y` would
   * include any spring overscroll still in flight and be restored with it.
   */
  insertAnchored(rowsInsertedAbove: number, mutate: () => void): void {
    const wasAtTop: boolean = this.firstVisible === 0;
    this.keeper.capture(this.firstVisible, wasAtTop);
    mutate();
    if (rowsInsertedAbove !== 0) {
      this.keeper.shift(rowsInsertedAbove);
    }
    // Capturing and beginning are separated by the host's mutation, so expose
    // them only through this one call — sequencing them by hand is exactly the
    // kind of thing a caller gets wrong.
    this.beginHold();
  }

  private beginHold(): void {
    // Starting a hold mid-scroll corrupts the calibration that maps
    // `extraOffset` onto screen space: the two samples disagree because inertia
    // is still moving the list. Defer to the stop instead of waiting a fixed
    // time for it.
    if (this.scrolling) {
      this.holdOnSettle = true;
      return;
    }
    this.keeper.begin();
    this.holding = this.keeper.isHolding();
  }

  private resetPull(): void {
    this.pull = 0;
    if (this.pullStep !== PULL_IDLE) {
      this.pullStep = PULL_IDLE;
    }
  }
}
