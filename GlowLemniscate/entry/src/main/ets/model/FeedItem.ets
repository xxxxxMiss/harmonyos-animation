/*
 * FeedItem.ets — demo data for the long list: a conversation, modelled the way
 * a real chat is.
 *
 * Rounds, not rows
 * ----------------
 * A conversation is not a flat list of equal items. It is a sequence of
 * **rounds**, and one round is one question plus however many answers it got —
 * one, three, five, it varies. That is why the page size in this demo is counted
 * in rounds and the number of *messages* a page delivers is not a constant.
 *
 * `FeedSource.pageRounds()` therefore returns a different number of rows every
 * time. Nothing downstream cares: the scroll effect is handed the length that
 * actually came back (`insertAnchored(rows.length, …)`), never a configured page
 * size. A flat feed and a round-based feed drive it identically.
 *
 * The rows also misbehave in the two ways that make scroll anchoring necessary:
 *
 *   1. Every row has its own height, derived deterministically from its id, so
 *      the list is genuinely variable-height.
 *   2. Some rows "render slowly": they first occupy a short placeholder and only
 *      take their real height once their content arrives, out of order relative
 *      to their neighbours.
 *
 * V2 state management: `@ObservedV2` + `@Trace`. `@Trace` is applied only to
 * `ready`, the single field that changes after construction; marking the
 * readonly fields too would make every row observable for no benefit.
 */

/** Deterministic pseudo-random in [0, 100000) — the classic GLSL hash. */
function hash32(n: number): number {
  const x: number = Math.sin(n * 12.9898) * 43758.5453;
  return Math.floor((x - Math.floor(x)) * 100000);
}

/** Which side of the round a message is on. */
export enum MsgKind {
  QUESTION = 0,
  ANSWER = 1
}

const QUESTIONS: string[] = [
  'ArkUI 的虚拟列表是怎么复用的？',
  'drawing 和 Canvas 2D 该选哪个？',
  '滚动位置为什么会被布局带跑？',
  'displaySync 和 requestAnimationFrame 的区别？',
  '手表上怎么处理滚动？',
  '为什么不能写 setTimeout(fn, ms)？',
  '色调映射在做什么？',
  'Repeat 和 LazyForEach 怎么选？',
  'XComponent 和原生 GL 值得上吗？',
  '长列表的内存怎么回收？'
];

const ANSWER_OPENERS: string[] = [
  '简单说，',
  '关键在于，',
  '这里有个反直觉的点：',
  '分两种情况，',
  '实测下来的结论是，'
];

/** One message: either the question of a round, or one of its answers. */
@ObservedV2
export class FeedItem {
  readonly id: string;
  /** 1-based round this message belongs to. */
  readonly round: number;
  readonly kind: MsgKind;
  /** 0 for the question, 1..N for the answers. */
  readonly slot: number;
  /** How many answers this round has — the question row shows "1 / N". */
  readonly answerCount: number;
  readonly title: string;
  readonly preview: string;
  /** Height once the row has fully rendered. */
  readonly finalHeight: number;
  /** Height while the row is still showing its placeholder. Always shorter. */
  readonly skeletonHeight: number;
  /** Seed for the deterministic latency draw. */
  readonly seed: number;
  /**
   * How many stages this row moves through, chosen by the active latency profile
   * in `planFor()`. 1 = straight to the final height.
   */
  stages: number = 1;
  /** Whether this row's content arrives asynchronously at all. */
  readonly async: boolean;
  /**
   * The height the row renders at right now. This is the field that makes the
   * list re-lay out — several times per row under the staged watch profile,
   * which is what produces a realistic settle storm.
   */
  @Trace currentHeight: number;
  /** Index of the stage reached so far; equals `stages` when settled. */
  @Trace stage: number;

  constructor(round: number, kind: MsgKind, slot: number, answerCount: number) {
    const h: number = hash32(round * 31 + slot * 7);
    this.round = round;
    this.kind = kind;
    this.slot = slot;
    this.answerCount = answerCount;
    this.id = 'r' + round + '-m' + slot;
    this.title = kind === MsgKind.QUESTION
      ? QUESTIONS[h % QUESTIONS.length]
      : (ANSWER_OPENERS[h % ANSWER_OPENERS.length] + '第 ' + slot + ' 条回答');
    this.preview = kind === MsgKind.QUESTION
      ? '第 ' + round + ' 轮 · 提问'
      : '第 ' + round + ' 轮 · 回答 ' + slot + ' / ' + answerCount;
    // Questions are compact and fairly uniform; answers are the variable ones.
    this.finalHeight = kind === MsgKind.QUESTION ? 92 + (h % 40) : 84 + (h % 120);
    // A placeholder that is visibly shorter than the real row, so the list
    // actually re-lays out when the content lands.
    this.skeletonHeight = 60;
    // Roughly one row in seven arrives asynchronously, deliberately not
    // consecutive so the rows settle out of order.
    this.seed = h;
    this.async = h % 7 === 0;
    // Filled in by `planFor()`, which knows the active latency profile.
    this.currentHeight = this.finalHeight;
    this.stage = 1;
  }

  /** Applies the latency plan chosen by the harness. */
  planFor(stages: number, async: boolean): void {
    if (stages > 1) {
      this.stages = stages;
    }
    if (async) {
      // Start as a skeleton and let the harness advance the stages.
      this.stages = Math.max(this.stages, 1);
      this.stage = 0;
      this.currentHeight = this.skeletonHeight;
    } else {
      this.stage = this.stages;
      this.currentHeight = this.finalHeight;
    }
  }

  /** True once the row has reached its final height. */
  get settled(): boolean {
    return this.stage >= this.stages;
  }

  /** Moves to stage `s` of `of`, interpolating the height. */
  advanceTo(s: number, of: number): void {
    if (s <= this.stage) {
      return;
    }
    this.stage = s;
    if (s >= of) {
      this.currentHeight = this.finalHeight;
    } else {
      const frac: number = s / of;
      this.currentHeight =
        Math.round(this.skeletonHeight + (this.finalHeight - this.skeletonHeight) * frac);
    }
  }

  /** Jumps straight to the final height. */
  settle(): void {
    this.stage = this.stages;
    this.currentHeight = this.finalHeight;
  }
}

/** Stand-in for a paged conversation feed. */
export class FeedSource {
  /** Inclusive round range available, so the demo is bounded. */
  static readonly MIN_ROUND: number = 1;
  static readonly MAX_ROUND: number = 160;
  /** Round the page starts on, so there is history above and below. */
  static readonly START_ROUND: number = 82;

  /** One round has 1..MAX_ANSWERS answers. Deterministic, so runs repeat. */
  static readonly MAX_ANSWERS: number = 5;

  /** How many answers round `round` has. This is what makes a page's row count vary. */
  static answerCount(round: number): number {
    if (round < FeedSource.MIN_ROUND || round > FeedSource.MAX_ROUND) {
      return 0;
    }
    return 1 + hash32(round) % FeedSource.MAX_ANSWERS;
  }

  /** Every message of one round: the question, then its answers. */
  static round(round: number, stages: number = 1): FeedItem[] {
    const out: FeedItem[] = [];
    const answers: number = FeedSource.answerCount(round);
    if (answers === 0) {
      return out;
    }
    const q: FeedItem = new FeedItem(round, MsgKind.QUESTION, 0, answers);
    q.planFor(stages, q.async);
    out.push(q);
    for (let slot = 1; slot <= answers; slot++) {
      const a: FeedItem = new FeedItem(round, MsgKind.ANSWER, slot, answers);
      a.planFor(stages, a.async);
      out.push(a);
    }
    return out;
  }

  /**
   * `count` consecutive rounds, flattened.
   *
   * The returned length is `count + sum(answerCount(r))`, so it differs from
   * call to call — anywhere from `2 * count` to `(1 + MAX_ANSWERS) * count`.
   * That is the whole point: the caller passes `rows.length` to the scroll
   * effect, and the effect has no page size to be wrong about.
   */
  /**
   * @param stages how many height steps each asynchronous row moves through.
   *        Supplied by `LatencyHarness` so the demo can be run against a
   *        realistic watch profile instead of settling on the next tick.
   */
  static pageRounds(fromRound: number, count: number, stages: number = 1): FeedItem[] {
    const out: FeedItem[] = [];
    const first: number = Math.max(fromRound, FeedSource.MIN_ROUND);
    const last: number = Math.min(fromRound + count - 1, FeedSource.MAX_ROUND);
    for (let round = first; round <= last; round++) {
      const msgs: FeedItem[] = FeedSource.round(round, stages);
      for (let i = 0; i < msgs.length; i++) {
        out.push(msgs[i]);
      }
    }
    return out;
  }

  /** How many rounds a batch of rows spans — used only for display. */
  static roundsIn(rows: FeedItem[]): number {
    if (rows.length === 0) {
      return 0;
    }
    return rows[rows.length - 1].round - rows[0].round + 1;
  }
}
