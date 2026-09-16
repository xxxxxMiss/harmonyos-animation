/*
 * GlowCurve.ets
 *
 * Pure-geometry port of the WebGL fragment shader from the original
 * "canvas 发光线条动画特效" demo. Nothing in this file touches ArkUI, so the
 * math can be unit-tested and reused by any renderer.
 *
 * Shader reference (script.js):
 *
 *   vec2 getLemniscatePosition(float t) {
 *     float a = (1.0 + 0.5 + 0.5 * sin(t)) * 15.0;
 *     return vec2((a * cos(t)) / (1.0 + sin(t)*sin(t)),
 *                 (a * sin(t) * cos(t)) / (1.0 + sin(t)*sin(t)));
 *   }
 *
 *   float getSegment(float t, vec2 pos, float offset, float scale) {
 *     for (int i = 0; i < POINT_COUNT; i++)
 *       points[i] = getLemniscatePosition(offset + float(i)*len + fract(speed*t)*6.28);
 *     vec2 c = (points[0] + points[1]) / 2.0, c_prev;
 *     for (int i = 0; i < POINT_COUNT-1; i++) {   // i = 0 .. 6
 *       c_prev = c;
 *       c = (points[i] + points[i+1]) / 2.0;
 *       dist = min(dist, sdBezier(pos, scale*c_prev, scale*points[i], scale*c));
 *     }
 *     return max(0.0, dist);
 *   }
 */

/** Shader: `#define POINT_COUNT 8`. */
export const POINT_COUNT: number = 8;
/** Shader: `const float len = 0.25` — parametric gap between two samples. */
export const SEG_LEN: number = 0.25;
/** Shader: `const float speed = -0.7`. */
export const SPEED: number = -0.7;
/** Shader literal `fract(speed * t) * 6.28` (2*PI rounded down in the original). */
export const PHASE_PERIOD: number = 6.28;
/** Shader: `float scale = 0.000015 * height` — curve size follows viewport height. */
export const SHAPE_SCALE: number = 0.000015;
/** Shader: `float radius = 0.02` — glow falloff radius, in the shader's pos-space. */
export const GLOW_RADIUS: number = 0.02;
/** Shader: `var dt = 0.015` — time advanced per rendered frame. */
export const TIME_STEP: number = 0.015;

/** A plain 2D point. Mutable on purpose: the renderer reuses instances. */
export interface Vec2 {
  x: number;
  y: number;
}

/**
 * One of the two glowing trails drawn by `main()`.
 * `glow` is the RGB tint the shader multiplies the glow term by
 * (`vec3(0.7, 0.3, 0.9)` for the first segment, `vec3(0.3, 0.5, 0.9)` for the second).
 */
export class TrailSpec {
  readonly offset: number;
  readonly glowR: number;
  readonly glowG: number;
  readonly glowB: number;

  constructor(offset: number, glowR: number, glowG: number, glowB: number) {
    this.offset = offset;
    this.glowR = glowR;
    this.glowG = glowG;
    this.glowB = glowB;
  }
}

/** The two `getSegment()` calls in the shader's `main()`. */
export const TRAILS: TrailSpec[] = [
  new TrailSpec(0.0, 0.7, 0.3, 0.9),
  new TrailSpec(3.7, 0.3, 0.5, 0.9)
];

/** GLSL `fract()`. */
export function fract(x: number): number {
  return x - Math.floor(x);
}

/**
 * Bounding box of the lemniscate in curve units, measured numerically over one
 * full period (2M samples). |x| peaks at t = 0.1079, |y| at t = 0.6662.
 *
 * The figure is 2.40 : 1 — much wider than it is tall — which is the whole
 * reason orientation matters here (see `SizeMode`).
 */
export const LEMNISCATE_MAX_X: number = 22.906480;
export const LEMNISCATE_MAX_Y: number = 9.540147;

/** Fraction of the viewport the figure may occupy when `SizeMode.FIT` clamps it. */
export const FIT_MARGIN: number = 0.90;

export enum SizeMode {
  /**
   * Exact shader behaviour: `scale = 0.000015 * height`.
   *
   * Note that the resulting *pixel* size depends only on `width * height`, not
   * on the aspect ratio: half-width = `0.000015 * W * H * 22.906`. So a
   * 1260x2720 phone renders the very same 2356 px wide figure it would in
   * 2720x1260 — but portrait only has 630 px of half-width to show it in, so
   * the figure overflows by 1.87x and you only ever see the middle of it.
   */
  SHADER = 0,
  /**
   * `SHADER` clamped so the figure always fits the viewport — never enlarges it,
   * only shrinks. In a viewport that already fits (most landscape windows) this
   * is bit-identical to `SHADER`. Default.
   */
  FIT = 1
}

/**
 * Maps the shader's normalised coordinate system onto canvas pixels.
 *
 *   uv  = gl_FragCoord.xy / resolution.xy            // y up, both in [0,1]
 *   pos = vec2(0.5, 0.5) - uv
 *   pos.y /= (resolution.x / resolution.y)           // aspect correction
 *
 * A curve point `S` expressed in pos-space therefore lands on the canvas at
 *
 *   x = W * (0.5 - S.x)
 *   y = H * 0.5 + W * S.y
 *
 * Two consequences worth knowing:
 *  - the X axis is mirrored (`pos.x = 0.5 - uv.x`), which reverses the travel
 *    direction of the trails relative to the raw lemniscate parameterisation;
 *  - one pos-space unit equals exactly `W` pixels on *both* axes, which is why
 *    the glow radius converts to pixels as `GLOW_RADIUS * W`.
 */
export class Viewport {
  width: number = 0;
  height: number = 0;
  /** Shader: `scale = 0.000015 * height` (possibly clamped, see `SizeMode`). */
  scale: number = 0;
  sizeMode: SizeMode = SizeMode.FIT;

  /**
   * The on-canvas half extents are `W * scale * MAX_X` and `W * scale * MAX_Y`,
   * so the largest scale that keeps the figure on screen is the smaller of the
   * two solved bounds. Taking `min` with the shader's own scale means `FIT`
   * can only ever shrink the figure, never blow it up.
   */
  private computeScale(): number {
    const shaderScale: number = SHAPE_SCALE * this.height;
    if (this.sizeMode === SizeMode.SHADER || this.width <= 0 || this.height <= 0) {
      return shaderScale;
    }
    const fitX: number = FIT_MARGIN * 0.5 / LEMNISCATE_MAX_X;
    const fitY: number = FIT_MARGIN * 0.5 * this.height / (this.width * LEMNISCATE_MAX_Y);
    return Math.min(shaderScale, fitX, fitY);
  }

  resize(width: number, height: number): void {
    this.width = width;
    this.height = height;
    this.scale = this.computeScale();
  }

  setSizeMode(mode: SizeMode): void {
    this.sizeMode = mode;
    this.scale = this.computeScale();
  }

  /** Figure half-width in canvas px — handy for logging and layout checks. */
  shapeHalfWidthPx(): number {
    return this.width * this.scale * LEMNISCATE_MAX_X;
  }

  /** Figure half-height in canvas px. */
  shapeHalfHeightPx(): number {
    return this.width * this.scale * LEMNISCATE_MAX_Y;
  }

  /** Curve-space X -> canvas X. */
  mapX(curveX: number): number {
    return this.width * (0.5 - this.scale * curveX);
  }

  /** Curve-space Y -> canvas Y. */
  mapY(curveY: number): number {
    return this.height * 0.5 + this.width * this.scale * curveY;
  }

  /** `radius = 0.02` pos-space units, converted to canvas pixels. */
  glowRadiusPx(): number {
    return GLOW_RADIUS * this.width;
  }
}

/**
 * Samples one trail and flattens it into the quadratic-Bezier chain the shader
 * walks in `getSegment()`.
 *
 * The shader emits, for i = 0..6, a quadratic Bezier
 * `mid(i-1,i) -> points[i] -> mid(i,i+1)`. At i = 0 the two endpoints collapse
 * onto `mid(0,1)`, producing a degenerate "spike" that shoots out to `points[0]`
 * and back. That is a bug in the original demo — it is visible as a sharp kink
 * near the tail of the magenta trail — so it is opt-in here via `includeSpike`.
 *
 * All instances are preallocated; `update()` performs no heap allocation, which
 * matters because it runs once per trail per frame.
 */
export class Trail {
  readonly spec: TrailSpec;
  /** Curve-space samples, POINT_COUNT entries. */
  private readonly pts: Vec2[] = [];
  /** Curve-space midpoints `(P[i] + P[i+1]) / 2`, POINT_COUNT-1 entries. */
  private readonly mids: Vec2[] = [];
  /** Canvas-space start of the chain. */
  readonly start: Vec2 = { x: 0, y: 0 };
  /** Canvas-space Bezier control points, POINT_COUNT-2 entries. */
  readonly ctrl: Vec2[] = [];
  /** Canvas-space Bezier end points, POINT_COUNT-2 entries. */
  readonly end: Vec2[] = [];
  /** Canvas-space control point of the optional degenerate spike. */
  readonly spikeCtrl: Vec2 = { x: 0, y: 0 };

  constructor(spec: TrailSpec) {
    this.spec = spec;
    for (let i = 0; i < POINT_COUNT; i++) {
      this.pts.push({ x: 0, y: 0 });
    }
    for (let i = 0; i < POINT_COUNT - 1; i++) {
      this.mids.push({ x: 0, y: 0 });
    }
    for (let i = 0; i < POINT_COUNT - 2; i++) {
      this.ctrl.push({ x: 0, y: 0 });
      this.end.push({ x: 0, y: 0 });
    }
  }

  /** Advances the phase for shader time `time` and re-projects into canvas space. */
  update(time: number, vp: Viewport): void {
    // fract(speed * t) * 6.28, plus the per-trail `offset` uniform.
    const phase: number = this.spec.offset + fract(SPEED * time) * PHASE_PERIOD;

    for (let i = 0; i < POINT_COUNT; i++) {
      const t: number = phase + i * SEG_LEN;
      const a: number = (1.0 + 0.5 + 0.5 * Math.sin(t)) * 15.0;
      const s: number = Math.sin(t);
      const c: number = Math.cos(t);
      const d: number = 1.0 + s * s;
      this.pts[i].x = (a * c) / d;
      this.pts[i].y = (a * s * c) / d;
    }

    for (let i = 0; i < POINT_COUNT - 1; i++) {
      this.mids[i].x = (this.pts[i].x + this.pts[i + 1].x) * 0.5;
      this.mids[i].y = (this.pts[i].y + this.pts[i + 1].y) * 0.5;
    }

    // Chain: mid(0,1) ->[ctrl P1]-> mid(1,2) ->[ctrl P2]-> ... ->[ctrl P6]-> mid(6,7)
    this.start.x = vp.mapX(this.mids[0].x);
    this.start.y = vp.mapY(this.mids[0].y);
    for (let k = 0; k < POINT_COUNT - 2; k++) {
      this.ctrl[k].x = vp.mapX(this.pts[k + 1].x);
      this.ctrl[k].y = vp.mapY(this.pts[k + 1].y);
      this.end[k].x = vp.mapX(this.mids[k + 1].x);
      this.end[k].y = vp.mapY(this.mids[k + 1].y);
    }
    this.spikeCtrl.x = vp.mapX(this.pts[0].x);
    this.spikeCtrl.y = vp.mapY(this.pts[0].y);
  }
}
