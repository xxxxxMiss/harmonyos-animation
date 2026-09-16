/*
 * AnchorKeeper.ets
 *
 * Keeps the reading position pinned while the list re-lays out underneath the
 * user.
 *
 * The problem
 * -----------
 * Rows in this feed do not all render at once. A row whose content is still
 * arriving occupies a short placeholder, and when the real content lands it
 * grows. Rows therefore settle out of order, and every time one of them changes
 * height the List re-runs layout: everything below the change slides, and the
 * row the user was reading drifts away.
 *
 * `maintainVisibleContentPosition` does not help. Its own documentation says it
 * only holds the position when data is inserted or deleted **above** the
 * visible area, with LazyForEach. A row growing in place, or a page appended at
 * the bottom, are both outside that contract.
 *
 * The fix
 * -------
 * Remember which row was at the top of the viewport and exactly where it sat,
 * then put it back after each layout change:
 *
 *   1. `capture()`  — before touching the data, record (index, y) of the
 *      topmost visible row, where `y` is `getItemRect().y`, i.e. its offset
 *      from the top edge of the list viewport.
 *   2. `begin()`    — after the data change, start holding.
 *   3. `notifyLayoutChanged()` — every row calls this from `onAreaChange`, so
 *      each time a row settles we re-pin.
 *
 * Everything is event driven. See "No wall-clock waits" below.
 *
 * How the correction is derived
 * -----------------------------
 * `scrollToIndex(..., align = START)` places the row's top edge at the viewport
 * top, which is a known base; `extraOffset` then displaces it, giving a locally
 * affine relationship
 *
 *     y(extra) = y0 + k * extra        =>        extra* = (savedY - y0) / k
 *
 * `k` folds in both the sign convention and the unit, and it is *measured*
 * rather than assumed — guessing it wrong on device walked the list away from
 * the target until the row left the built range entirely. `k` starts at -1,
 * which is the value observed when the list is at rest (vp in, vp out, inverted),
 * and is re-derived from every real correction: after applying `extra`, an
 * observed `y` gives `k = (y - y0) / extra`. So an inaccurate starting guess
 * costs one extra pass and then self-corrects.
 *
 * An earlier revision calibrated with a dedicated probe scroll of `PROBE_VP`.
 * That was removed: the probe is a second, *small* scroll issued immediately
 * after the align jump, and if it does not change the visible range it produces
 * no scroll event to wait on. Deriving `k` from the correction we were going to
 * make anyway needs no extra scroll at all.
 *
 * No wall-clock waits, and no polling
 * -----------------------------------
 * This class contains no `setTimeout(fn, ms)`. Waiting a fixed number of
 * milliseconds for "the layout to settle" is unportable — the right delay
 * depends on the device, the data and the frame rate, and on a watch it is
 * simply wrong.
 *
 * It also does not poll. The first revision re-armed itself immediately after
 * every `scrollToIndex`, which on device made it measure the *pre-scroll* state
 * over and over: the residual was a constant 48 vp (exactly `PROBE_VP`) while
 * `extra` walked away by 48 vp a step, until the budget tripped. `setTimeout(fn,
 * 0)` steps out of the current layout pass but does not guarantee the framework
 * has applied a scroll.
 *
 * So the next step is driven by the framework instead:
 *   - `applyCorrection()` marks the keeper as waiting for the scroll to land and
 *     arms nothing;
 *   - the page reports `onScrollSettled()` from `List.onScrollIndex` /
 *     `onScrollStop` — genuine scroll events, which a watch's digital crown
 *     produces exactly like a finger;
 *   - row resizes still arrive through `notifyLayoutChanged()`.
 *
 * `setTimeout(fn, 0)` is used only to move work out of a layout callback, never
 * to wait for one.
 *
 * The hold therefore has no deadline. It ends when:
 *   - the page calls `release()` (the user took over the scroll), or
 *   - a new `capture()`/`begin()` supersedes it, or
 *   - the target row never becomes measurable (`STALL_LIMIT`), or
 *   - the per-hold correction budget (`MAX_CORRECTIONS`) trips.
 * Holding itself costs nothing: with no events arriving, no work happens.
 */

import { LengthMetrics } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'AnchorKeeper';

/** Consider the position restored once the row is this close to where it was. */
const TOLERANCE_VP: number = 1.0;

/** Consecutive unmeasurable samples before giving up on the target row. */
const STALL_LIMIT: number = 3;

/** Hard cap on corrections for one hold, so a pathological layout cannot spin. */
const MAX_CORRECTIONS: number = 40;

/** Phases of one solve. See `step()`. */
enum Phase {
  /** Displace by zero to establish the `align = START` base. */
  ALIGN = 0,
  /** Read `y0`, then apply the exact correction. */
  SOLVE = 1,
  /** Verify, refine `k` from the result, and correct any residual. */
  VERIFY = 2
}

/** `getItemRect` returns a usable rect only for a row the list has built. */
function usable(rect: RectResult): boolean {
  return rect !== undefined && rect !== null && rect.height > 0;
}

export class AnchorKeeper {
  private scroller: ListScroller | undefined = undefined;

  /** Index of the row that was at the top of the viewport. */
  private index: number = -1;
  /** Its `getItemRect().y` at capture time. */
  private savedY: number = 0;

  /**
   * Measured slope `dy / d(extraOffset)`. Folds in the sign convention *and*
   * the unit, so the keeper never has to assume either.
   */
  /**
   * Measured slope `dy / d(extraOffset)`; starts at the value observed with the
   * list at rest and is refined from every correction actually applied.
   */
  private k: number = -1;
  /** Row position when `extra == 0`, from the ALIGN phase. */
  private y0: number = 0;
  private phase: Phase = Phase.ALIGN;
  private extra: number = 0;

  private active: boolean = false;
  /**
   * Set whenever a row resizes. A correction only runs while this is set, so a
   * hold that has already converged never touches the scroll position again --
   * otherwise the keeper would fight a scroll that happened in between.
   */
  private dirty: boolean = false;
  /** Coalesces bursts of layout callbacks into one deferred step. */
  private armed: boolean = false;
  /**
   * Consecutive measurements that produced nothing usable. Reset whenever a
   * correction is issued.
   */
  private stalls: number = 0;
  /**
   * Corrections issued for the CURRENT hold. This must be separate from
   * `restores`, which is cumulative for the HUD — using the cumulative counter
   * as the budget meant the guard tripped once and stayed tripped forever.
   */
  private corrections: number = 0;
  /**
   * Set after a `scrollToIndex` and cleared when the framework reports the
   * scroll. While set, the keeper will not re-measure, because a measurement
   * taken before the scroll lands describes the old position.
   */
  private awaitingScroll: boolean = false;

  /** Diagnostics for the on-screen HUD. */
  restores: number = 0;

  /**
   * Called whenever the hold converges or is dropped, so the owner can refresh
   * any readout of the current position. Without it a HUD refreshed from a
   * scroll callback would still show the pre-correction state, because the
   * correction lands after that callback.
   */
  onSettled: () => void = () => {
  };

  attach(scroller: ListScroller): void {
    this.scroller = scroller;
  }

  /** True while the keeper is holding the position. */
  isHolding(): boolean {
    return this.active;
  }

  /** For the HUD: which row is being held, or -1. */
  heldIndex(): number {
    return this.active ? this.index : -1;
  }

  /**
   * Records the current reading position. Call this immediately BEFORE mutating
   * the data, otherwise the index refers to the pre-insertion array.
   *
   * @param firstVisibleIndex from `List.onScrollIndex`.
   * @param forceTopAlign anchor the row to the very top of the viewport instead
   *        of trusting `getItemRect().y`. Useful when something has already
   *        displaced the list (an overscroll bounce, a header), because a `y`
   *        measured then would be restored *with* that offset and leave the
   *        list permanently shifted.
   */
  capture(firstVisibleIndex: number, forceTopAlign: boolean = false): void {
    // Never leave a stale anchor behind if this capture fails.
    this.index = -1;
    const scroller: ListScroller | undefined = this.scroller;
    if (scroller === undefined || firstVisibleIndex < 0) {
      return;
    }
    this.index = firstVisibleIndex;
    if (forceTopAlign) {
      this.savedY = 0;
      hilog.info(DOMAIN, TAG, 'capture index=%{public}d top-aligned', firstVisibleIndex);
      return;
    }
    const rect: RectResult = scroller.getItemRect(firstVisibleIndex);
    if (!usable(rect)) {
      // Unmeasured or recycled row. Anchoring the index with a top alignment is
      // an approximation, but it is far better than dropping the anchor and
      // letting an insertion throw the user back a whole page.
      this.savedY = 0;
      hilog.info(DOMAIN, TAG, 'capture index=%{public}d unmeasured, top-aligned',
        firstVisibleIndex);
      return;
    }
    this.savedY = rect.y;
    hilog.info(DOMAIN, TAG, 'capture index=%{public}d y=%{public}s h=%{public}s',
      firstVisibleIndex, rect.y.toFixed(1), rect.height.toFixed(1));
  }

  /**
   * Shifts the anchor when rows are inserted or removed above it, so the same
   * logical row stays anchored across a prepend.
   */
  shift(delta: number): void {
    if (this.index >= 0) {
      this.index += delta;
    }
  }

  /** Starts holding. Call right after the data array has been replaced. */
  begin(): void {
    if (this.index < 0) {
      return;
    }
    this.extra = 0;
    this.phase = Phase.ALIGN;
    this.stalls = 0;
    this.corrections = 0;
    this.awaitingScroll = false;
    this.active = true;
    this.dirty = true;
    hilog.info(DOMAIN, TAG, 'begin index=%{public}d savedY=%{public}s',
      this.index, this.savedY.toFixed(1));
    this.arm();
  }

  /**
   * A row resized. Every row wires `onAreaChange` to this, which is what makes
   * the keeper react to rows that settle long after the data arrived.
   */
  notifyLayoutChanged(): void {
    if (!this.active) {
      return;
    }
    this.dirty = true;
    // Rows appearing or resizing is independent proof that the pending scroll
    // has been applied, so it also releases the wait.
    this.awaitingScroll = false;
    this.arm();
  }

  /** Drops the hold, e.g. when the user takes over the scroll. */
  release(): void {
    if (this.active) {
      hilog.info(DOMAIN, TAG, 'released after %{public}d correction(s)', this.restores);
    }
    this.active = false;
    this.dirty = false;
    this.awaitingScroll = false;
    this.onSettled();
  }

  /**
   * Defers a step out of the current layout pass. `setTimeout(fn, 0)` only — it
   * means "run this later in the event loop", not "wait for something to
   * finish". The flag coalesces the burst of `onAreaChange` callbacks that a
   * single layout pass produces into one step.
   */
  private arm(): void {
    if (this.armed) {
      return;
    }
    this.armed = true;
    setTimeout(() => {
      this.armed = false;
      this.step();
    }, 0);
  }

  private step(): void {
    const scroller: ListScroller | undefined = this.scroller;
    if (!this.active || scroller === undefined || this.index < 0) {
      return;
    }
    if (this.awaitingScroll) {
      // A scroll is still in flight; measuring now would read the old position,
      // which is what made the original loop diverge.
      return;
    }
    if (!this.dirty) {
      // Nothing has resized since the last correction; stay armed and idle.
      return;
    }
    if (this.corrections > MAX_CORRECTIONS) {
      hilog.warn(DOMAIN, TAG, 'correction budget exhausted, releasing');
      this.release();
      return;
    }

    if (this.phase === Phase.ALIGN) {
      this.phase = Phase.SOLVE;
      this.applyCorrection(0);
      return;
    }

    const rect: RectResult = scroller.getItemRect(this.index);
    if (!usable(rect)) {
      // The row is not built (still recycled). Rather than wait a fixed time,
      // count the attempts and give up if it never materialises.
      this.stalls++;
      if (this.stalls >= STALL_LIMIT) {
        hilog.warn(DOMAIN, TAG, 'row %{public}d never became measurable', this.index);
        this.dirty = false;
      } else {
        this.arm();
      }
      return;
    }
    this.stalls = 0;

    if (this.phase === Phase.SOLVE) {
      this.y0 = rect.y;
      this.phase = Phase.VERIFY;
      this.extra = (this.savedY - this.y0) / this.k;
      hilog.info(DOMAIN, TAG, 'solve y0=%{public}s k=%{public}s -> extra=%{public}s',
        this.y0.toFixed(1), this.k.toFixed(4), this.extra.toFixed(1));
      this.applyCorrection(this.extra);
      return;
    }

    // ---- VERIFY: measure, refine `k` from what actually happened ----------
    const err: number = rect.y - this.savedY;
    if (Math.abs(err) <= TOLERANCE_VP) {
      hilog.info(DOMAIN, TAG, 'converged y=%{public}s target=%{public}s k=%{public}s after %{public}d',
        rect.y.toFixed(1), this.savedY.toFixed(1), this.k.toFixed(4), this.corrections);
      this.dirty = false;
      this.onSettled();
      return;
    }
    // `y = y0 + k * extra`, and we have all three, so the slope can be measured
    // from the correction just applied instead of from a dedicated probe scroll.
    if (Math.abs(this.extra) > 1) {
      const measured: number = (rect.y - this.y0) / this.extra;
      if (Math.abs(measured) > 0.05 && Math.abs(measured - this.k) > 0.001) {
        hilog.info(DOMAIN, TAG, 'refine k %{public}s -> %{public}s',
          this.k.toFixed(4), measured.toFixed(4));
        this.k = measured;
      }
    }
    this.y0 = rect.y - this.k * this.extra;
    this.extra = (this.savedY - this.y0) / this.k;
    hilog.info(DOMAIN, TAG, 'residual err=%{public}s -> extra=%{public}s',
      err.toFixed(1), this.extra.toFixed(1));
    this.applyCorrection(this.extra);
  }

  /**
   * Places the target row at `align = START` and displaces it by `value`.
   *
   * UNITS: `getItemRect()` reports **vp** and `extraOffset` is consumed in
   * **vp**. Passing `LengthMetrics.px()` made ArkUI divide every correction by
   * the display density (1216/375 = 3.243 on the test device), so the loop crept
   * in geometrically instead of landing. The measured `k` absorbs any such
   * mismatch, but passing the right unit keeps the probe meaningful.
   */
  private applyCorrection(value: number): void {
    const scroller: ListScroller | undefined = this.scroller;
    if (scroller === undefined) {
      return;
    }
    scroller.scrollToIndex(this.index, false, ScrollAlign.START,
      { extraOffset: LengthMetrics.vp(value) });
    this.restores++;
    this.corrections++;
    // Do NOT re-arm here. The next step waits for the framework to report the
    // scroll, either through `onScrollSettled()` (List scroll events) or through
    // `notifyLayoutChanged()` (rows built or resized by the scroll). Arming
    // immediately was the bug: it measured the pre-scroll position and diverged.
    this.awaitingScroll = true;
  }

  /**
   * The list reported a scroll. Called by the page from `List.onScrollIndex`
   * and `List.onScrollStop` — real scroll events, so a watch's digital crown
   * drives this exactly like a finger.
   */
  onScrollSettled(): void {
    if (!this.awaitingScroll) {
      return;
    }
    this.awaitingScroll = false;
    this.arm();
  }
}
