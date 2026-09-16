/*
 * FeedItem.ets — the demo data behind the long list.
 *
 * The rows deliberately misbehave in the two ways that make scroll anchoring
 * necessary:
 *
 *   1. Every row has its own height, derived deterministically from its
 *      sequence number, so the list is genuinely variable-height.
 *   2. Some rows "render slowly": they first occupy a short placeholder and only
 *      take their real height once their content arrives, which happens out of
 *      order relative to their neighbours.
 *
 * V2 state management: `@ObservedV2` + `@Trace` instead of `@Observed`.
 *
 * `@Trace` is applied only to `ready`, the single field that changes after
 * construction. Marking the readonly fields too would make every row observable
 * for no benefit. `ready` has to be observable because a row flips it when its
 * content lands, and the row component's `@Param` must re-render for that one
 * row — rebuilding the array instead would defeat `Repeat`.
 */

/** Deterministic pseudo-random in [0, 100000) — the classic GLSL hash. */
function hash32(n: number): number {
  const x: number = Math.sin(n * 12.9898) * 43758.5453;
  return Math.floor((x - Math.floor(x)) * 100000);
}

const TITLES: string[] = [
  'HarmonyOS NEXT 渲染管线',
  'ArkUI 声明式布局',
  'Skia 与 Rosen 的关系',
  'texture 与 surface 的合成',
  '离屏渲染与 bloom',
  '虚拟列表的复用策略',
  '滚动锚定与位置保持',
  '可变高度列表的测量',
  '异步内容与布局抖动',
  'DisplaySync 与帧调度',
  '图形栈的脏区合并',
  '长列表的内存回收'
];

/** One row of the feed. */
@ObservedV2
export class FeedItem {
  readonly id: string;
  /** 1-based position in the whole feed; used for the label. */
  readonly seq: number;
  readonly title: string;
  readonly preview: string;
  /** Height once the row has fully rendered. */
  readonly height: number;
  /** Height while the row is still showing its placeholder. Always shorter. */
  readonly skeletonHeight: number;
  /**
   * Whether this row's content arrives asynchronously. There is deliberately no
   * delay constant here — how long a real fetch takes is not knowable, so the
   * row simply starts un-ready and the page resolves it on the next tick.
   */
  readonly deferred: boolean;
  /** Flipped to true when the content has arrived. Observed by the row. */
  @Trace ready: boolean;

  constructor(seq: number) {
    const h: number = hash32(seq);
    this.id = 'row-' + seq;
    this.seq = seq;
    this.title = TITLES[h % TITLES.length];
    this.preview = '第 ' + seq + ' 条 · 高度 ' + (104 + (h % 132)) + 'px · ' +
      (seq % 6 === 0 ? '异步内容' : '即时渲染');
    // 104..235 vp, stable for a given seq so runs are reproducible.
    this.height = 104 + (h % 132);
    // A placeholder that is visibly shorter than the real row, so the list
    // actually re-lays out when the content lands.
    this.skeletonHeight = 68;
    // One row in six defers, and they are deliberately not consecutive so the
    // rows settle out of order.
    this.deferred = seq % 6 === 0;
    this.ready = !this.deferred;
  }
}

/** Stand-in for a paged network feed. */
export class FeedSource {
  /** First and last sequence number available, so the demo is bounded. */
  static readonly MIN_SEQ: number = 1;
  static readonly MAX_SEQ: number = 600;
  /** Sequence the page starts on, so there is history above and below. */
  static readonly START_SEQ: number = 281;

  /** Builds `count` rows starting at sequence `from`, clamped to the range. */
  static page(from: number, count: number): FeedItem[] {
    const out: FeedItem[] = [];
    const last: number = Math.min(from + count - 1, FeedSource.MAX_SEQ);
    for (let seq = Math.max(from, FeedSource.MIN_SEQ); seq <= last; seq++) {
      out.push(new FeedItem(seq));
    }
    return out;
  }
}
