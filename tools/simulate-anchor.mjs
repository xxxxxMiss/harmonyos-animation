/*
 * simulate-anchor.mjs
 *
 * A headless harness for the scroll-anchor control flow.
 *
 * Why this exists
 * ---------------
 * On a watch, a row can take 400–600 ms from insertion to its final height, and
 * a page of 30 rows settles out of order. That is a *lot* of layout changes
 * arriving long after the load, and it is the case the on-device demo — which
 * resolves rows on the next tick — never exercises.
 *
 * `AnchorKeeper.ets` cannot run here: it needs `ListScroller`, `getItemRect` and
 * `LengthMetrics`. But the part that matters for this question is pure
 * arithmetic — how many corrections a hold issues, and what the guards do when
 * that number grows. So the control flow is ported line by line and driven
 * against a synthetic list.
 *
 * This is a model, not the device. It will not catch ArkUI-specific problems.
 * What it does catch is control-flow bugs, in particular whether the guards are
 * sized for a realistic settle storm.
 *
 * Run: node tools/simulate-anchor.mjs
 */

// ---------------------------------------------------------------------------
// Synthetic list
// ---------------------------------------------------------------------------

/** Deterministic pseudo-random in [0,1). */
function rnd(seed) {
  const x = Math.sin(seed * 12.9898) * 43758.5453;
  return x - Math.floor(x);
}

const SKELETON_H = 60;

/** Builds rows whose heights vary and which settle over `stages` steps. */
function makeRows(count, cfg, salt) {
  const rows = [];
  for (let i = 0; i < count; i++) {
    const finalH = 84 + Math.floor(rnd(i + salt) * 120);      // 84..203 vp
    if (rnd(i * 3 + salt + 7) >= cfg.deferredFraction) {
      rows.push({ skeletonH: finalH, stages: [] });           // never resizes
      continue;
    }
    const lat = cfg.minLatency +
      rnd(i * 5 + salt + 11) * (cfg.maxLatency - cfg.minLatency);
    const stages = [];
    for (let s = 1; s <= cfg.stages; s++) {
      const frac = s / cfg.stages;
      stages.push({
        h: Math.round(SKELETON_H + (finalH - SKELETON_H) * frac),
        at: lat * frac
      });
    }
    rows.push({ skeletonH: SKELETON_H, stages });
  }
  return rows;
}

class FakeList {
  constructor(viewportH, cacheRows) {
    this.viewportH = viewportH;
    this.cacheRows = cacheRows;
    this.now = 0;
    this.scrollOffset = 0;
    this.rows = [];
    this.heights = [];
    this.stage = [];
  }

  setRows(rows) {
    this.rows = rows;
    this.heights = rows.map((r) => r.skeletonH);
    this.stage = rows.map(() => -1);
  }

  /** Inserts rows at the front, keeping the existing state aligned. */
  prependRows(extra) {
    this.rows = extra.concat(this.rows);
    this.heights = extra.map((r) => r.skeletonH).concat(this.heights);
    this.stage = extra.map(() => -1).concat(this.stage);
  }

  get rowCount() {
    return this.rows.length;
  }

  /** Advances settling; returns how many rows changed height. */
  advanceTo(t) {
    this.now = t;
    let changed = 0;
    for (let i = 0; i < this.rows.length; i++) {
      const stages = this.rows[i].stages;
      let s = this.stage[i];
      while (s + 1 < stages.length && stages[s + 1].at <= t) {
        s++;
      }
      if (s !== this.stage[i]) {
        this.stage[i] = s;
        const h = s < 0 ? this.rows[i].skeletonH : stages[s].h;
        if (h !== this.heights[i]) {
          this.heights[i] = h;
          changed++;
        }
      }
    }
    return changed;
  }

  get totalH() {
    let t = 0;
    for (let i = 0; i < this.heights.length; i++) {
      t += this.heights[i];
    }
    return t;
  }

  rowTop(i) {
    let t = 0;
    for (let k = 0; k < i; k++) {
      t += this.heights[k];
    }
    return t;
  }

  get maxScroll() {
    return Math.max(0, this.totalH - this.viewportH);
  }

  /** Row i's top edge relative to the viewport top. */
  y(i) {
    return this.rowTop(i) - this.scrollOffset;
  }

  /** Only rows inside the built window report a rect — as with virtualScroll. */
  getItemRect(i) {
    if (i < 0 || i >= this.rowCount || !Number.isFinite(this.heights[i])) {
      return null;
    }
    const y = this.y(i);
    const h = this.heights[i];
    const margin = this.cacheRows * 80;
    if (y + h <= -margin || y >= this.viewportH + margin) {
      return null;
    }
    return { x: 0, y, width: 100, height: h };
  }

  /**
   * `align = START` plus `extra`, which on device measures as `y = -extra`.
   * Clamped at both ends exactly as the framework clamps.
   */
  scrollToIndex(i, extra) {
    const want = this.rowTop(i) + extra;
    this.scrollOffset = Math.min(this.maxScroll, Math.max(0, want));
  }
}

// ---------------------------------------------------------------------------
// Port of AnchorKeeper's control flow
// ---------------------------------------------------------------------------

const Phase = { ALIGN: 0, CORRECT: 1, VERIFY: 2 };

class Keeper {
  constructor(list, opts) {
    this.list = list;
    // Defaults mirror AnchorOptions.
    this.opts = Object.assign({ toleranceVp: 1.0, stallLimit: 3, maxCorrections: 40 }, opts);
    this.index = -1;
    this.savedY = 0;
    this.k = -1;
    this.y0 = 0;
    this.phase = Phase.ALIGN;
    this.extra = 0;
    this.active = false;
    this.dirty = false;
    this.armed = false;
    this.awaitingScroll = false;
    this.stalls = 0;
    this.corrections = 0;
    this.holdTotal = 0;
    this.restores = 0;
    this.y0Clean = false;
    this.budgetTripped = false;
    this.layoutEvents = 0;
    this.reArmedByScroll = 0;
  }

  capture(i) {
    const r = this.list.getItemRect(i);
    this.index = i;
    this.savedY = r ? r.y : 0;
  }

  shift(d) {
    this.index += d;
  }

  begin() {
    this.extra = 0;
    this.phase = Phase.ALIGN;
    this.stalls = 0;
    this.corrections = 0;
    this.holdTotal = 0;
    this.y0Clean = false;
    this.awaitingScroll = false;
    this.active = true;
    this.dirty = true;
    this.arm();
  }

  notifyLayoutChanged() {
    if (!this.active) {
      return;
    }
    this.layoutEvents++;
    this.dirty = true;
    this.awaitingScroll = false;
    // A row resized, so everything below it shifted. Any slope derived across
    // this point describes the layout, not the correction — see the VERIFY phase.
    this.y0Clean = false;
    this.arm();
  }

  /** The list reported a scroll — this is what releases a pending correction. */
  onScrollSettled() {
    if (!this.awaitingScroll) {
      return;
    }
    this.awaitingScroll = false;
    this.reArmedByScroll++;
    this.arm();
  }

  /** `setTimeout(fn, 0)`: runs on the next tick. */
  arm() {
    if (this.armed) {
      return;
    }
    this.armed = true;
    this.pending = true;
  }

  release() {
    this.active = false;
    this.dirty = false;
    this.awaitingScroll = false;
  }

  tick() {
    if (this.pending) {
      this.pending = false;
      this.armed = false;
      this.step();
    }
  }

  step() {
    if (!this.active || this.index < 0 || this.awaitingScroll || !this.dirty) {
      return;
    }
    if (this.corrections > this.opts.maxCorrections) {
      this.budgetTripped = true;
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

    const rect = this.list.getItemRect(this.index);
    if (!rect) {
      this.stalls++;
      if (this.stalls >= this.opts.stallLimit) {
        this.stalled = true;
        this.dirty = false;
      } else {
        this.arm();
      }
      return;
    }
    this.stalls = 0;

    if (this.phase === Phase.CORRECT) {
      // `align = START` re-bases on every call: it puts the row's top at the
      // viewport top and then displaces by `extra`, so `y == k * extra` and the
      // answer is a CONSTANT — `savedY / k` — no matter how far the content
      // above has grown. This is the whole correction; there is nothing to
      // solve iteratively.
      this.extra = this.savedY / this.k;
      this.phase = Phase.VERIFY;
      this.applyCorrection(this.extra);
      return;
    }

    // ---- VERIFY -----------------------------------------------------------
    const err = rect.y - this.savedY;
    if (Math.abs(err) <= this.opts.toleranceVp) {
      this.dirty = false;
      // The guard counts attempts that did NOT converge, so a long but
      // productive settle storm never trips it.
      this.corrections = 0;
      return;
    }
    // Still off, so `k` is wrong. Re-derive it — but only from a measurement
    // with no resize in between, otherwise `y / extra` describes the layout
    // rather than the mapping.
    if (this.y0Clean && Math.abs(this.extra) > 1) {
      const measured = rect.y / this.extra;
      if (Math.abs(measured) > 0.05 && Math.abs(measured - this.k) > 0.001) {
        if (this.trace) {
          this.trace.push({ t: this.list.now, from: +this.k.toFixed(3), to: +measured.toFixed(3) });
        }
        this.k = measured;
      }
    }
    this.extra = this.savedY / this.k;
    this.applyCorrection(this.extra);
  }

  applyCorrection(extra) {
    this.list.scrollToIndex(this.index, extra);
    if (this.log) {
      this.log.push('    apply t=' + String(this.list.now).padStart(4) +
        ' phase=' + this.phase + ' extra=' + extra.toFixed(1).padStart(8) +
        ' -> offset=' + this.list.scrollOffset.toFixed(0).padStart(6) +
        ' y=' + this.list.y(this.index).toFixed(1).padStart(8));
    }
    this.restores++;
    this.corrections++;
    this.holdTotal++;
    // The measurement taken after this call is clean unless something resizes
    // before it arrives.
    this.y0Clean = true;
    // The pending scroll is released by the next scroll event.
    this.awaitingScroll = true;
    this.scrollPending = true;
  }
}

// ---------------------------------------------------------------------------
// Scenario
// ---------------------------------------------------------------------------

const base = {
  rows: 40,
  viewportH: 400,        // a watch: roughly 400 vp tall
  cacheRows: 3,
  inserted: 20,
  deferredFraction: 0.6,
  stages: 1,
  minLatency: 0,
  maxLatency: 0,
  anchorIndex: 4,
  durationMs: 4000,
  anchor: {}
};

function run(cfg) {
  const list = new FakeList(cfg.viewportH, cfg.cacheRows);
  list.setRows(makeRows(cfg.rows, cfg, 1));
  list.advanceTo(0);

  const keeper = new Keeper(list, cfg.anchor);
  // The row the user is reading sits 40 vp above the fold.
  list.scrollOffset = Math.min(list.maxScroll, list.rowTop(cfg.anchorIndex) + 40);
  keeper.capture(cfg.anchorIndex);
  const targetY = keeper.savedY;

  // A page arrives above the anchor — the pull-to-load case.
  list.prependRows(makeRows(cfg.inserted, cfg, 101));
  keeper.shift(cfg.inserted);
  keeper.begin();

  const samples = [];
  for (let t = 0; t <= cfg.durationMs; t += 16) {
    const changed = list.advanceTo(t);
    for (let c = 0; c < changed; c++) {
      keeper.notifyLayoutChanged();
    }
    // A pending correction is released by the next scroll event.
    if (keeper.scrollPending) {
      keeper.scrollPending = false;
      keeper.onScrollSettled();
    }
    keeper.tick();
    samples.push({ t, y: list.y(keeper.index), active: keeper.active });
  }

  list.advanceTo(cfg.durationMs + 2000);
  const finalY = list.y(keeper.index);
  const target = targetY;

  // Last moment any row resizes.
  let lastSettle = 0;
  for (const r of list.rows) {
    for (const s of r.stages) {
      lastSettle = Math.max(lastSettle, s.at);
    }
  }
  // Worst deviation over the last 300 ms, i.e. once everything has settled and
  // the effect has had its chance to react.
  let worst = 0;
  for (const s of samples) {
    if (s.t >= cfg.durationMs - 300 && Math.abs(s.y - target) > Math.abs(worst)) {
      worst = s.y - target;
    }
  }

  return {
    restores: keeper.holdTotal,
    layoutEvents: keeper.layoutEvents,
    budgetTripped: keeper.budgetTripped,
    stalled: keeper.stalled === true,
    lastSettle: Math.round(lastSettle),
    finalErr: +(finalY - target).toFixed(1),
    worst: +worst.toFixed(1)
  };
}

// ---------------------------------------------------------------------------

const scenarios = [
  ['A  baseline — instant settle, 1 stage', { ...base }],
  ['B  120ms, 1 stage', { ...base, minLatency: 100, maxLatency: 140 }],
  ['C  watch 400-600ms, 1 stage', { ...base, minLatency: 400, maxLatency: 600 }],
  ['D  watch 400-600ms, 2 stages', { ...base, minLatency: 400, maxLatency: 600, stages: 2 }],
  ['E  worst 400-900ms, 3 stages, 30 rows',
    { ...base, minLatency: 400, maxLatency: 900, stages: 3, inserted: 30, deferredFraction: 0.8 }]
];

console.log('Scroll-anchor simulation — does the hold survive a realistic settle storm?');
console.log('watch viewport 400 vp, 3 cached rows, 20-30 rows inserted above the anchor\n');
console.log('scenario'.padEnd(42) + 'settle  corrections  layoutEvt  budget   finalErr  worst');
console.log('-'.repeat(94));

const results = [];
for (const [name, cfg] of scenarios) {
  const r = run(cfg);
  results.push({ name, r });
  console.log(
    name.padEnd(42) +
    String(r.lastSettle + 'ms').padStart(7) +
    String(r.restores).padStart(12) +
    String(r.layoutEvents).padStart(11) +
    String(r.budgetTripped ? 'TRIPPED' : 'ok').padStart(9) +
    String(r.finalErr + 'vp').padStart(10) +
    String(r.worst + 'vp').padStart(8));
}

// Diagnostic: what happens to y over time in scenario B (the failing short-latency case)?
console.log();
console.log('--- y trace for scenario B (120ms) ---');
{
  const cfg = scenarios[1][1];
  const list = new FakeList(cfg.viewportH, cfg.cacheRows);
  list.setRows(makeRows(cfg.rows, cfg, 1));
  list.advanceTo(0);
  const keeper = new Keeper(list, cfg.anchor);
  keeper.log = [];
  list.scrollOffset = Math.min(list.maxScroll, list.rowTop(cfg.anchorIndex) + 40);
  keeper.capture(cfg.anchorIndex);
  const target = keeper.savedY;
  // Load a page above the anchor.
  list.prependRows(makeRows(cfg.inserted, cfg, 101));
  keeper.shift(cfg.inserted);
  keeper.begin();
  console.log('  target y = ' + target + 'vp   anchor index = ' + keeper.index +
    '   rows = ' + list.rowCount);
  let lastY = null;
  for (let t = 0; t <= cfg.durationMs; t += 16) {
    const changed = list.advanceTo(t);
    for (let c = 0; c < changed; c++) { keeper.notifyLayoutChanged(); }
    if (keeper.scrollPending) { keeper.scrollPending = false; keeper.onScrollSettled(); }
    keeper.tick();
    const y = list.y(keeper.index);
    if (keeper.log.length && !keeper.dumped) { /* noop */ }
    if (lastY === null || Math.abs(y - lastY) > 0.5) {
      console.log('  t=' + String(t).padStart(4) + 'ms  y=' + y.toFixed(1).padStart(8) +
        '  err=' + (y - target).toFixed(1).padStart(8) +
        '  active=' + (keeper.active ? 1 : 0) + ' dirty=' + (keeper.dirty ? 1 : 0) +
        '  phase=' + keeper.phase + ' corr=' + keeper.corrections +
        '  offset=' + list.scrollOffset.toFixed(0));
      lastY = y;
    }
  }
  console.log('  corrections issued (first 14):');
  for (const l of keeper.log.slice(0, 14)) { console.log(l); }
  if (keeper.log.length > 14) { console.log('    ... ' + (keeper.log.length - 14) + ' more'); }
  console.log('  final: offset=' + list.scrollOffset.toFixed(0) +
    ' rowTop=' + list.rowTop(keeper.index).toFixed(0) +
    ' y=' + list.y(keeper.index).toFixed(1) +
    ' maxScroll=' + list.maxScroll.toFixed(0) +
    ' target=' + target);
}

// Diagnostic: is k staying at its calibrated value?
console.log();
console.log('--- k refinement trace for scenario C (400-600ms) ---');
{
  const cfg = scenarios[2][1];
  const list = new FakeList(cfg.viewportH, cfg.cacheRows);
  list.setRows(makeRows(cfg.rows, cfg, 1));
  list.advanceTo(0);
  const keeper = new Keeper(list, cfg.anchor);
  keeper.trace = [];
  list.scrollOffset = Math.min(list.maxScroll, list.rowTop(cfg.anchorIndex) + 40);
  keeper.capture(cfg.anchorIndex);
  list.prependRows(makeRows(cfg.inserted, cfg, 101));
  keeper.shift(cfg.inserted);
  keeper.begin();
  for (let t = 0; t <= cfg.durationMs; t += 16) {
    const changed = list.advanceTo(t);
    for (let c = 0; c < changed; c++) { keeper.notifyLayoutChanged(); }
    if (keeper.scrollPending) { keeper.scrollPending = false; keeper.onScrollSettled(); }
    keeper.tick();
  }
  const tr = keeper.trace;
  console.log('k re-derived ' + tr.length + ' times; final k = ' + keeper.k.toFixed(3));
  for (const e of tr.slice(0, 8)) {
    console.log('  t=' + String(e.t).padStart(4) + 'ms  k ' + e.from + ' -> ' + e.to + '  (extra=' + e.extra + ')');
  }
  if (tr.length > 8) { console.log('  ... ' + (tr.length - 8) + ' more'); }
}
console.log();
const broken = results.filter((x) => Math.abs(x.r.finalErr) > 2);
if (broken.length === 0) {
  console.log('PASS — the anchor survived every scenario.');
} else {
  console.log('FAIL — anchor lost in ' + broken.length + ' scenario(s):');
  for (const x of broken) {
    console.log('  · ' + x.name + '  finalErr=' + x.r.finalErr + 'vp' +
      (x.r.budgetTripped ? '   ← correction budget exhausted, hold released' : ''));
  }
}
process.exit(broken.length === 0 ? 0 : 1);
