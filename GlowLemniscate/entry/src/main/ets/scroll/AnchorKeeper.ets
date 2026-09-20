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
 * top, which is a known base; `extraOffset` then displaces it. Because the base
 * is re-established on **every** call, the relationship is
 *
 *     y = k * extra        =>        extra* = savedY / k
 *
 * and that is a **constant**. It does not depend on how far the content above
 * has grown, and there is nothing to solve iteratively.
 *
 * `k` folds in both the sign convention and the unit; it starts at -1, the value
 * measured on device (vp in, vp out, inverted), and is re-derived as `y / extra`
 * from a displacement whose result can be measured cleanly. A wrong guess costs
 * one extra pass and then self-corrects.
 *
 * What this replaced, and why
 * ---------------------------
 * The first revision treated `y` as locally affine around an *interpolated*
 * origin and folded in a residual:
 *
 *     y0 = y - k * extra ;   extra += (savedY - y0') / k
 *
 * That is only valid while the layout holds still between the two measurements,
 * because `y0` is re-derived rather than re-measured. It is not valid on a
 * watch, where rows settle 400-600 ms after insertion: every fold was computed
 * against a layout that had already moved. Measured symptoms were an anchor that
 * walked 600-790 vp away, and a `k` poisoned from -1 to 6.4 and -15.7 by
 * dividing a content shift by the displacement.
 *
 * `tools/simulate-anchor.mjs` reproduces both the old failure and the fix.
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
 *   - the per-hold correction budget (`anchor.maxCorrections`) trips.
 * Holding itself costs nothing: with no events arriving, no work happens.
 */

import { LengthMetrics } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'AnchorKeeper';

/**
 * Tunables for the anchoring itself.
 *
 * These are injected rather than fixed, so the effect can be dropped into a
 * project that already has its own ideas about tolerances and budgets. Every
 * field has a default that works for a general-purpose list.
 *
 * All three are **convergence / give-up** knobs, not behaviour knobs: changing
 * them alters how precisely the position is restored and how quickly the effect
 * stops trying. None of them affects *when* paging happens — that is
 * `AnchoredPagingConfig` (`prefetchRows`, `pullThresholdVp`).
 *
 * Where each one sits in one hold:
 *
 *     ALIGN   scrollToIndex(index, START, 0)     // brings the row into view
 *     CORRECT scrollToIndex(index, START, savedY / k)   // <- stallLimit guards this
 *     VERIFY  err = getItemRect(index).y - savedY
 *             |err| <= toleranceVp ? done        // <-- toleranceVp guards this
 *             else re-derive k and re-apply      // <-- maxCorrections guards this
 *
 * A quiet hold is 2 corrections. `maxCorrections` is sized for a settle storm
 * instead, because it guards only attempts that did *not* converge.
 */
export interface AnchorOptions {
  /**
   * The position counts as restored once the row is within this many vp.
   *
   * Not zero on purpose: `k` is measured rather than derived, `extraOffset` is
   * quantised to physical pixels, and so is the layout. Chasing the last
   * fraction means issuing more `scrollToIndex` calls, each of which costs a
   * full layout pass, for something invisible. 1 vp is about 3.2 device px on
   * a 3.24-density phone.
   *
   * Raise it and the row can come back visibly short (a clipped title, an
   * obvious sliver). Lower it and a hold may never satisfy the quantisation, so
   * every load runs until `maxCorrections` trips.
   */
  toleranceVp?: number;
  /**
   * Consecutive samples where the anchored row cannot be measured before the
   * effect stops trying for this hold.
   *
   * `getItemRect()` only reports rows the list has actually **built**. Under
   * `Repeat` + `virtualScroll` a row outside the built window returns a
   * zero-height rect. The ALIGN step scrolls to the row, which normally builds
   * it, but that build is asynchronous relative to this loop.
   *
   * Counted **consecutively** — any successful measurement resets it to zero.
   * One sample is a normal transient (the scroll was issued, the layout pass
   * has not run yet), so 1 would give up on loads that actually work. Each
   * retry is just a deferred re-check, never a wall-clock wait.
   *
   * Tripping it parks the hold (`dirty = false`) rather than dropping it: the
   * next row resize retries. Note that it can trip harmlessly — when `savedY`
   * is 0 the ALIGN step has already put the row at the top, which is the right
   * answer anyway.
   */
  stallLimit?: number;
  /**
   * Hard cap on corrections made **without converging**.
   *
   * The counter is reset in `begin()` and again on every convergence, so it
   * measures attempts that are not making progress — not total activity. That
   * distinction matters on a watch: one page of late-settling rows can produce
   * well over a hundred height changes, and counting those as budget exhausted
   * the guard mid-load and released the hold, which is exactly the "it stops
   * working at 400-600 ms" symptom.
   *
   * Deliberately separate from the cumulative `restores` counter used for
   * diagnostics. Using the cumulative value here was an earlier bug: once a
   * session accumulated this many corrections the guard stayed tripped forever
   * and anchoring silently died, with nothing obviously wrong in the log.
   *
   * It exists for a genuinely stuck loop — a row that resizes on *every* layout
   * pass, or a `savedY` that is unreachable. Without it the effect would issue
   * `scrollToIndex` on every event-loop turn forever, burning CPU *and* fighting
   * the user, who would be unable to scroll away.
   *
   * Exceeding it calls `release()`, dropping the hold; the position stays where
   * it ended up. Degrades to "no anchoring", never to a crash.
   */
  maxCorrections?: number;
}

export function defaultAnchorOptions(): Required<AnchorOptions> {
  return {
    toleranceVp: 1.0,
    stallLimit: 3,
    maxCorrections: 40
  };
}

/** Phases of one hold. See `step()`. */
enum Phase {
  /** Bring the anchored row into view; this also builds it. */
  ALIGN = 0,
  /** Apply the one exact displacement the alignment implies. */
  CORRECT = 1,
  /** Measure, and re-derive `k` if the mapping turned out to be wrong. */
  VERIFY = 2
}

/** `getItemRect` returns a usable rect only for a row the list has built. */
function usable(rect: RectResult): boolean {
  return rect !== undefined && rect !== null && rect.height > 0;
}

export class AnchorKeeper {
  private readonly opts: Required<AnchorOptions>;
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
  /** Corrections issued for the current hold, for logging. */
  private holdTotal: number = 0;
  /**
   * True while the last displacement can still be measured cleanly — set when a
   * correction is applied, cleared the moment a row resizes. `y / extra` only
   * describes the vp-to-vp mapping if the layout held still across the two.
   */
  private cleanWindow: boolean = true;
  /**
   * Set after a `scrollToIndex` and cleared when the framework reports the
   * scroll. While set, the keeper will not re-measure, because a measurement
   * taken before the scroll lands describes the old position.
   */
  private awaitingScroll: boolean = false;

  /** Diagnostics for the on-screen HUD. */
  restores: number = 0;
  /**
   * How far the anchored row had drifted the last time it was measured, in vp.
   *
   * This is the *observable consequence of late rendering*: the anchored row
   * cannot move unless something above it changed size, so this number is
   * literally how far the page shifted under the reader while content was
   * arriving. With the hold active it is corrected back to zero and nothing is
   * seen; with the hold off it accumulates into the visible jump.
   *
   * It is measured in `VERIFY`, i.e. **before** the correction is applied, so it
   * reports the displacement rather than the residue of fixing it.
   */
  lastDriftVp: number = 0;
  /** Largest `|lastDriftVp|` seen during the current hold. Reset in `begin()`. */
  maxDriftVp: number = 0;
  /**
   * Layout changes reported to the hold since `begin()`.
   *
   * This is the counter that answers "did the late rendering actually disturb
   * the list?". A row can settle without ever reaching here — under
   * `virtualScroll` a row outside the built window is not in the tree, so its
   * height changes nothing and fires no `onAreaChange`. Late renders that no
   * one measures are late renders that cannot move the reader, so the honest way
   * to report the demo is to count what arrived, not what was scheduled.
   */
  layoutEvents: number = 0;
  /**
   * Total absolute height change, in vp, reported by rows **above** the reading
   * position while the hold was active — the layout churn the hold sat through.
   *
   * This is the number that makes late rendering *visible as a quantity*. The
   * drift counters above cannot report it: `scrollToIndex` is applied by the
   * framework during the very layout pass in which the resize happens, so by the
   * time `VERIFY` measures, the position is already restored and the residue is
   * zero. What is left to measure is the displacement that was absorbed, and
   * that is this sum: with no hold in the way it is exactly how far the content
   * above the reader would have moved.
   *
   * Diagnostics only — nothing in the effect reads it back.
   */
  churnVp: number = 0;

  /**
   * Called whenever the hold's measured state changes — it converged, it drifted,
   * or it was dropped — so the owner can refresh any readout of the current
   * position. Without it a HUD refreshed from a scroll callback would still show
   * the pre-correction state, because the correction lands after that callback.
   */
  onSettled: () => void = () => {
  };

  constructor(options?: AnchorOptions) {
    this.opts = defaultAnchorOptions();
    if (options !== undefined) {
      if (options.toleranceVp !== undefined) {
        this.opts.toleranceVp = options.toleranceVp;
      }
      if (options.stallLimit !== undefined) {
        this.opts.stallLimit = options.stallLimit;
      }
      if (options.maxCorrections !== undefined) {
        this.opts.maxCorrections = options.maxCorrections;
      }
    }
  }

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
    this.holdTotal = 0;
    this.cleanWindow = false;
    this.awaitingScroll = false;
    this.lastDriftVp = 0;
    this.maxDriftVp = 0;
    this.layoutEvents = 0;
    this.churnVp = 0;
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
  /**
   * @param index the resized row's index in the list.
   * @param deltaVp its signed height change in vp.
   *
   * Both are passed in because only the row knows them, and the pair is what
   * makes `churnVp` mean something: a row growing *below* the reading position
   * pushes nothing the reader can see, so it is not churn. Only growth above
   * the anchor moves it.
   */
  notifyLayoutChanged(index: number = -1, deltaVp: number = 0): void {
    if (!this.active) {
      return;
    }
    this.layoutEvents++;
    if (deltaVp !== 0 && index >= 0 && index < this.index) {
      this.churnVp += Math.abs(deltaVp);
    }
    this.dirty = true;
    // A row resized, so everything below it shifted. Any slope derived across
    // this point describes the layout rather than the correction.
    this.cleanWindow = false;
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
    if (this.corrections > this.opts.maxCorrections) {
      hilog.warn(DOMAIN, TAG, 'correction budget exhausted, releasing');
      this.release();
      return;
    }

    if (this.phase === Phase.ALIGN) {
      // Bring the row into view. This also builds it, which is what makes the
      // verification measurement below possible at all.
      this.phase = Phase.CORRECT;
      this.applyCorrection(0);
      return;
    }

    const rect: RectResult = scroller.getItemRect(this.index);
    if (!usable(rect)) {
      // The row is not built (still recycled). Rather than wait a fixed time,
      // count the attempts and give up if it never materialises.
      this.stalls++;
      if (this.stalls >= this.opts.stallLimit) {
        hilog.warn(DOMAIN, TAG, 'row %{public}d never became measurable', this.index);
        this.dirty = false;
      } else {
        this.arm();
      }
      return;
    }
    this.stalls = 0;

    if (this.phase === Phase.CORRECT) {
      // ------------------------------------------------------------------
      // THE WHOLE CORRECTION, and it is a constant.
      //
      // `scrollToIndex(..., align = START)` re-bases on every call: it puts the
      // row's top edge at the viewport top and *then* displaces by
      // `extraOffset`. So `y == k * extra` holds for each call independently of
      // what came before, and the displacement that lands on `savedY` is simply
      //
      //     extra = savedY / k
      //
      // It does NOT depend on how far the content above has grown, and there is
      // nothing to solve iteratively.
      //
      // The first revision instead folded in a residual measured against `y0`:
      // `extra += (savedY - y) / k`. That is only valid while the layout holds
      // still, because `y0` is re-derived rather than re-measured. On a watch,
      // where rows settle 400-600 ms late, every such fold was computed against
      // a layout that had already moved — the anchor walked off by hundreds of
      // vp, and the derived `k` was poisoned into the bargain (observed:
      // -1 -> 0.7 -> 2.35 -> 6.375 -> -15.663).
      // ------------------------------------------------------------------
      this.extra = this.savedY / this.k;
      this.phase = Phase.VERIFY;
      hilog.info(DOMAIN, TAG, 'correct savedY=%{public}s k=%{public}s -> extra=%{public}s',
        this.savedY.toFixed(1), this.k.toFixed(4), this.extra.toFixed(1));
      this.applyCorrection(this.extra);
      return;
    }

    // ---- VERIFY ---------------------------------------------------------
    const err: number = rect.y - this.savedY;
    // Recorded before anything is corrected, so it reports how far the layout
    // actually moved the reader — see `lastDriftVp`.
    this.lastDriftVp = err;
    if (Math.abs(err) > this.maxDriftVp) {
      this.maxDriftVp = Math.abs(err);
    }
    if (Math.abs(err) > this.opts.toleranceVp) {
      hilog.info(DOMAIN, TAG,
        'drift id=%{public}d y=%{public}s target=%{public}s drift=%{public}s vp (re-pinning)',
        this.index, rect.y.toFixed(1), this.savedY.toFixed(1), err.toFixed(1));
    }
    this.onSettled();
    if (Math.abs(err) <= this.opts.toleranceVp) {
      hilog.info(DOMAIN, TAG, 'converged y=%{public}s target=%{public}s k=%{public}s after %{public}d',
        rect.y.toFixed(1), this.savedY.toFixed(1), this.k.toFixed(4), this.holdTotal);
      this.dirty = false;
      // The guard counts attempts that did NOT converge. Resetting here is what
      // keeps a long but productive settle storm from tripping it — on a watch a
      // single page can produce well over a hundred height changes.
      this.corrections = 0;
      this.onSettled();
      return;
    }

    // Still off, so `k` itself is wrong. Re-derive it from this measurement —
    // but only if nothing resized since the displacement was applied, otherwise
    // `y / extra` describes the layout rather than the mapping.
    if (this.cleanWindow && Math.abs(this.extra) > 1) {
      const measured: number = rect.y / this.extra;
      if (Math.abs(measured) > 0.05 && Math.abs(measured - this.k) > 0.001) {
        hilog.info(DOMAIN, TAG, 'refine k %{public}s -> %{public}s',
          this.k.toFixed(4), measured.toFixed(4));
        this.k = measured;
      }
    }
    this.extra = this.savedY / this.k;
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
    this.holdTotal++;
    // The measurement that follows is clean unless something resizes first.
    this.cleanWindow = true;
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
