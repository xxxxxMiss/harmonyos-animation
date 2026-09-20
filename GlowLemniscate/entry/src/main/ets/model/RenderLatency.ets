/*
 * RenderLatency.ets — stands in for the real render pipeline.
 *
 * ⚠️ THIS IS THE ONLY PLACE IN THE PROJECT ALLOWED TO USE `setTimeout(fn, ms)`.
 *
 * Everywhere else the rule is `setTimeout(fn, 0)`, because a mechanism that
 * waits a fixed number of milliseconds for "the layout to settle" is
 * unportable — the right delay depends on the device, the data and the frame
 * rate, and a number that works on a phone is wrong on a watch.
 *
 * That rule is about the *mechanism*. Modelling how long a real device takes to
 * produce a row is a different thing: the delay is a property of the pipeline
 * being simulated, not a guess the mechanism makes. It lives here, behind one
 * enum, so it is obvious that nothing in `scroll/` depends on it.
 *
 * Why this exists at all: the original demo resolved a row on the next tick.
 * That is not what a watch does. On wearable hardware a row can take 400–600 ms
 * from insertion to its final height, and — this is the part that matters — it
 * can get there in several steps rather than one. A page of 30 such rows
 * produces well over a hundred height changes arriving long after the load,
 * which is the settle storm that broke the anchor.
 */

import { FeedItem } from './FeedItem';

/** How long rows take to reach their final height, and in how many steps. */
export enum LatencyProfile {
  /** Resolves on the next tick. What the demo did before. */
  INSTANT = 0,
  /** ~120 ms in one step — fast phone. */
  FAST = 1,
  /** 400–600 ms in one step — typical watch. */
  WATCH = 2,
  /**
   * 400–900 ms in three steps — a watch under load, e.g. an image decode
   * followed by a re-layout of the text block. This is the case that exposes
   * control-flow bugs, because every intermediate height is another layout
   * change arriving after the anchor has already been restored once.
   */
  WATCH_STAGED = 3
}

/** Deterministic pseudo-random in [0,1). */
function rnd(seed: number): number {
  const x: number = Math.sin(seed * 12.9898) * 43758.5453;
  return x - Math.floor(x);
}

export class LatencyHarness {
  /** Tunables, so a test can be pushed past what a real device does. */
  static readonly WATCH_MIN_MS: number = 400;
  static readonly WATCH_MAX_MS: number = 600;
  static readonly WORST_MAX_MS: number = 900;

  static label(profile: LatencyProfile): string {
    switch (profile) {
      case LatencyProfile.INSTANT:
        return '即时（下一 tick）';
      case LatencyProfile.FAST:
        return '手机 ~120ms';
      case LatencyProfile.WATCH:
        return '手表 400-600ms';
      case LatencyProfile.WATCH_STAGED:
        return '手表 400-900ms · 分 3 段';
      default:
        return '?';
    }
  }

  /** How many steps this profile moves a row through before it settles. */
  static stages(profile: LatencyProfile): number {
    return profile === LatencyProfile.WATCH_STAGED ? 3 : 1;
  }

  /** The delay for one row, in ms. Zero means "resolve on the next tick". */
  static delayFor(profile: LatencyProfile, seed: number): number {
    switch (profile) {
      case LatencyProfile.INSTANT:
        return 0;
      case LatencyProfile.FAST:
        return 100 + rnd(seed) * 40;
      case LatencyProfile.WATCH:
        return LatencyHarness.WATCH_MIN_MS +
          rnd(seed) * (LatencyHarness.WATCH_MAX_MS - LatencyHarness.WATCH_MIN_MS);
      case LatencyProfile.WATCH_STAGED:
        return LatencyHarness.WATCH_MIN_MS +
          rnd(seed) * (LatencyHarness.WORST_MAX_MS - LatencyHarness.WATCH_MIN_MS);
      default:
        return 0;
    }
  }

  /**
   * Drives `item` from its skeleton to its final height.
   *
   * The timers are deliberately not cancelled when a row scrolls out of the
   * built window. The row's height is *data*, not view state: it has to finish
   * arriving even if the row is recycled meanwhile, otherwise the list never
   * settles and there is nothing stable for the anchor to hold on to.
   */
  static schedule(item: FeedItem, profile: LatencyProfile): void {
    if (profile === LatencyProfile.INSTANT) {
      setTimeout(() => {
        item.settle();
      }, 0);
      return;
    }
    const total: number = LatencyHarness.delayFor(profile, item.seed);
    const steps: number = LatencyHarness.stages(profile);
    for (let s = 1; s <= steps; s++) {
      // Intermediate steps are fractions of the total, so a 3-stage row lands
      // at ~1/3 and ~2/3 of its final height before the last one.
      const at: number = Math.round(total * (s / steps));
      const step: number = s;
      setTimeout(() => {
        item.advanceTo(step, steps);
      }, at);
    }
  }
}
