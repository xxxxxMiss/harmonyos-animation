/*
 * GlowRenderer.ets
 *
 * Draws the lemniscate glow effect onto an ArkUI `Canvas` through
 * `@ohos.graphics.drawing` — i.e. straight onto the component's own Skia
 * surface, with no native code and no offscreen PixelMap round-trip.
 *
 * Why the `drawing` API rather than `CanvasRenderingContext2D`
 * -----------------------------------------------------------
 * `DrawingRenderingContext` (API 12) hands out a real `drawing.Canvas` that
 * paints into the Canvas component's surface. That unlocks:
 *   - `BlendMode.PLUS`  — true additive accumulation, the same maths as the
 *     shader's `col += ...` (all 29 BlendMode members are API 11);
 *   - `MaskFilter.createBlurMaskFilter()` — a real Gaussian on the stroke;
 *   - `Pen.setShaderEffect()` — a gradient *along the stroke*, which the
 *     declarative `Shape`/`Path` components cannot express (their `stroke()`
 *     takes a plain ResourceColor).
 * The official graphics overview also notes that the Canvas component's
 * CanvasRenderingContext2D wrapper "is not as close to the hardware as the
 * Native Drawing Canvas" and can cause frame drops under load.
 *
 * How the shader maps onto vector drawing
 * ---------------------------------------
 * Per pixel the shader does:
 *
 *   dist  = distance to the trail                    (SDF of a Bezier chain)
 *   col  += 10.0 * smoothstep(0.003, 0.001, dist)    // white-hot core
 *   col  += pow(radius/dist, 0.9) * glowColour       // coloured halo
 *   col   = 1.0 - exp(-col)                          // tone map
 *
 * There is no fragment shader here, so the halo is rebuilt from vector
 * primitives. The key observation is that **stroking a path with width `w`
 * covers exactly the set of points within `w/2` of the path** — a stroke *is* a
 * distance field. So N nested strokes of decreasing width reproduce any radial
 * falloff:
 *
 *   value(d) = SUM of the alphas of every stroke whose width/2 exceeds d
 *
 * Picking the alphas as successive differences of the tone-mapped target
 * profile therefore approximates `pow(R/d, 0.9)` — a very long-tailed curve that
 * a single Gaussian blur cannot match, since a Gaussian's tail dies far too
 * quickly. `GLOW_MODE_BLUR` is kept as a cheaper, softer alternative.
 */

import { drawing, common2D } from '@kit.ArkGraphics2D';
import {
  GLOW_RADIUS, POINT_COUNT, SizeMode, TRAILS, Trail, TrailSpec, Vec2, Viewport
} from './GlowCurve';

/** Shader: `float intensity = 0.9` — exponent of the glow falloff. */
export const GLOW_EXP: number = 0.9;

/** Outermost ring radius, in units of the glow radius R. */
export const RING_D_MAX: number = 6.0;
/** Innermost ring radius, in units of R. */
export const RING_D_MIN: number = 0.05;
/** Number of rings; more rings = smoother falloff, linearly more draw calls. */
export const RING_COUNT: number = 22;

export enum GlowMode {
  /** Blurred wide bands — smooth long tail, the default. */
  BLUR = 0,
  /** Nested additive strokes — distance-field exact, but bands visibly. */
  RINGS = 1
}

/** One nested stroke of the ring stack. */
export class GlowRing {
  /** Stroke width, in canvas px. */
  readonly width: number;
  /** Additive intensity, 0..1. */
  readonly alpha: number;

  constructor(width: number, alpha: number) {
    this.width = width;
    this.alpha = alpha;
  }
}

/** One blurred stroke of the fallback stack. */
export class BlurPass {
  readonly width: number;
  readonly sigmaFactor: number;
  readonly alpha: number;

  constructor(width: number, sigmaFactor: number, alpha: number) {
    this.width = width;
    this.sigmaFactor = sigmaFactor;
    this.alpha = alpha;
  }
}

/**
 * Blurred-band pass table.
 *
 * A stroke of width `w` blurred with sigma `s` is a box convolved with a
 * Gaussian: flat at `alpha` for `d < w/2 - 2s`, rolling off across the edge, and
 * gone by `d ~ w/2 + 2s`.
 *
 * THE CRITICAL CONSTRAINT: `sigma` must be at least as large as the gap to the
 * next band's edge. If it is not, every band ends in a near-step and the halo
 * reads as a stack of concentric shells. That was the bug in the first revision
 * (`sigma` 0.9 / 1.8 / 3.0 against band gaps of 1.5 / 3.0 / 4.5) and it is what
 * "光晕和模糊太大" looked like on device: flat plateaus joined by hard contour
 * lines, instead of a decaying falloff.
 *
 * The table below is a non-negative least-squares fit of
 * `SUM alpha_k * profile_k(d)` to the shader's tone-mapped halo
 * `T(d) = 1 - exp(-(R/d)^0.9)`, with alpha clamped to [0, 1]:
 *
 *   d/R    0.5    1     1.5    2     3     5     8     10    14
 *   T      0.845  0.632 0.501  0.415 0.311 0.209 0.143 0.118 0.089
 *   fit    0.815  0.732 0.562  0.406 0.288 0.217 0.146 0.119 0.074
 *
 * The worst error sits at `d <= 1R` (25/255), which is underneath the white
 * core; from `2R` outward it is within 6/255. The largest step between adjacent
 * samples is 4.7/255 — smooth, so there are no contour lines.
 *
 * `width` and `sigmaFactor` are multiples of the glow radius `R = GLOW_RADIUS * W`.
 */
export const BLUR_PASSES: BlurPass[] = [
  new BlurPass(1.6, 0.8, 1.000),   // inner   -> rolls off to ~2.4R
  new BlurPass(2.7, 1.7, 0.077),   //         -> rolls off to ~6R
  new BlurPass(4.8, 3.0, 0.319),   //         -> rolls off to ~11R
  new BlurPass(12.8, 8.0, 0.325)   // ambient -> rolls off to ~22R
];

/**
 * White-hot core, as a fraction of canvas width.
 *
 * The shader's `10.0 * smoothstep(0.003, 0.001, dist)` is expressed in pos-space
 * units, and one pos-space unit is `W` pixels — so the core's width is
 * proportional to the canvas width, NOT a fixed pixel count. The white term
 * stays above 1.0 (and therefore saturates to pure white) out to `dist ~ 0.0026`,
 * i.e. a full width of about `0.0052 * W`.
 *
 * The first revision hardcoded 3.4 px, which was tuned at W = 900 and is less
 * than half the correct width on a 1216 px phone — that is why the line looked
 * too thin on device.
 *
 * Drawn as two strokes rather than one: `smoothstep` gives the core a soft
 * shoulder, and a single antialiased stroke would have a hard edge.
 */
export const CORE_WIDTH_FACTOR: number = 0.0035;
export const CORE_HALO_WIDTH_FACTOR: number = 0.0075;
export const CORE_HALO_ALPHA: number = 0.45;

/**
 * Tone-map compensation — the pass that actually makes the line look like it is
 * *emitting* light rather than merely painted white.
 *
 * The shader finishes with `col = 1.0 - exp(-col)`. That is a SOFT clipper: near
 * the line the coloured glow is 5–25x over unity, so after tone mapping even the
 * low channel (green, coefficient 0.3) is pushed up to ~0.6 and the whole
 * neighbourhood reads as near-white. The white-looking region therefore extends
 * far beyond the geometric white stroke — out to roughly `0.5R`.
 *
 * `BlendMode.PLUS` clamps at 1.0 instead — a HARD clipper — so without help the
 * port keeps a saturated purple right up to the core and the line looks thin and
 * flat. Adding one soft white band lifts every channel together, which is exactly
 * what the tone map does, and desaturates the near field toward white.
 *
 * Grid-searched against the shader's true per-channel output: one extra stroke of
 * `width = 0.70R`, `sigma = 0.20R`, `alpha = 0.55` cuts the RMS colour error over
 * `0..60 px` from 23.0/255 to 9.5/255, and the error at `d = 2 px` from 73/255 to
 * 1/255.
 */
export const TONE_LIFT_WIDTH_FACTOR: number = 0.70;
export const TONE_LIFT_SIGMA_FACTOR: number = 0.20;
export const TONE_LIFT_ALPHA: number = 0.55;

/** Reproduces the original demo's degenerate first Bezier segment (the kink). */
export const INCLUDE_SPIKE: boolean = false;

export class GlowRenderer {
  private readonly vp: Viewport = new Viewport();
  private readonly trails: Trail[] = [];
  private readonly path: drawing.Path = new drawing.Path();

  /** One pen per trail per technique, so the tint is set once per pass. */
  private readonly glowPens: drawing.Pen[] = [];
  private readonly corePens: drawing.Pen[] = [];
  private readonly coreHaloPens: drawing.Pen[] = [];
  private readonly liftPens: drawing.Pen[] = [];
  private readonly blurPens: drawing.Pen[] = [];

  private readonly black: common2D.Color = { alpha: 255, red: 0, green: 0, blue: 0 };

  /** Ring table in *radius factors*; widths are computed per frame from R. */
  private readonly ringRadius: number[] = [];
  private readonly ringAlpha: number[] = [];

  private mode: GlowMode = GlowMode.BLUR;
  private ready: boolean = false;

  constructor() {
    const specs: TrailSpec[] = TRAILS;
    for (let i = 0; i < specs.length; i++) {
      this.trails.push(new Trail(specs[i]));

      const glow: drawing.Pen = new drawing.Pen();
      glow.setAntiAlias(true);
      glow.setCapStyle(drawing.CapStyle.ROUND_CAP);
      glow.setJoinStyle(drawing.JoinStyle.ROUND_JOIN);
      glow.setBlendMode(drawing.BlendMode.PLUS);
      this.glowPens.push(glow);

      const blur: drawing.Pen = new drawing.Pen();
      blur.setAntiAlias(true);
      blur.setCapStyle(drawing.CapStyle.ROUND_CAP);
      blur.setJoinStyle(drawing.JoinStyle.ROUND_JOIN);
      blur.setBlendMode(drawing.BlendMode.PLUS);
      this.blurPens.push(blur);

      const core: drawing.Pen = new drawing.Pen();
      core.setColor(255, 255, 255, 255);
      core.setAntiAlias(true);
      core.setCapStyle(drawing.CapStyle.ROUND_CAP);
      core.setJoinStyle(drawing.JoinStyle.ROUND_JOIN);
      core.setBlendMode(drawing.BlendMode.PLUS);
      this.corePens.push(core);

      const coreHalo: drawing.Pen = new drawing.Pen();
      coreHalo.setColor(Math.round(CORE_HALO_ALPHA * 255), 255, 255, 255);
      coreHalo.setAntiAlias(true);
      coreHalo.setCapStyle(drawing.CapStyle.ROUND_CAP);
      coreHalo.setJoinStyle(drawing.JoinStyle.ROUND_JOIN);
      coreHalo.setBlendMode(drawing.BlendMode.PLUS);
      this.coreHaloPens.push(coreHalo);

      // Tone-map compensation: soft white, sized in units of the glow radius.
      const lift: drawing.Pen = new drawing.Pen();
      lift.setColor(Math.round(TONE_LIFT_ALPHA * 255), 255, 255, 255);
      lift.setAntiAlias(true);
      lift.setCapStyle(drawing.CapStyle.ROUND_CAP);
      lift.setJoinStyle(drawing.JoinStyle.ROUND_JOIN);
      lift.setBlendMode(drawing.BlendMode.PLUS);
      this.liftPens.push(lift);
    }
    this.buildRingTable(RING_COUNT);
  }

  /**
   * Core stroke widths follow the canvas width, exactly as the shader's
   * `smoothstep(0.003, 0.001, dist)` does — see `CORE_WIDTH_FACTOR`.
   */
  private applyCoreWidths(): void {
    const coreWidth: number = CORE_WIDTH_FACTOR * this.vp.width;
    const haloWidth: number = CORE_HALO_WIDTH_FACTOR * this.vp.width;
    const radius: number = this.vp.glowRadiusPx();
    const liftWidth: number = TONE_LIFT_WIDTH_FACTOR * radius;
    const liftSigma: number = TONE_LIFT_SIGMA_FACTOR * radius;
    for (let i = 0; i < this.corePens.length; i++) {
      this.corePens[i].setStrokeWidth(coreWidth);
      this.coreHaloPens[i].setStrokeWidth(haloWidth);
      this.liftPens[i].setStrokeWidth(liftWidth);
      this.liftPens[i].setMaskFilter(
        drawing.MaskFilter.createBlurMaskFilter(drawing.BlurType.NORMAL, liftSigma));
    }
  }

  /** `GlowMode.RINGS` (default) or `GlowMode.BLUR`. */
  setMode(mode: GlowMode): void {
    this.mode = mode;
  }

  /**
   * `SizeMode.FIT` (default) keeps the whole figure on screen in any aspect
   * ratio — portrait included. `SizeMode.SHADER` restores the exact WebGL
   * behaviour, which overflows narrow viewports by ~1.9x.
   */
  setSizeMode(mode: SizeMode): void {
    this.vp.setSizeMode(mode);
  }

  /** Read-only view of the current projection, for logging. */
  get viewport(): Viewport {
    return this.vp;
  }

  /** Shader halo profile, tone-mapped: `1 - exp(-(R/d)^0.9)`. */
  private static targetProfile(dOverR: number): number {
    if (dOverR <= 0) {
      return 1;
    }
    return 1 - Math.exp(-Math.pow(1 / dOverR, GLOW_EXP));
  }

  /**
   * Fills `ringRadius` / `ringAlpha`. Radii are spaced geometrically from
   * `RING_D_MAX` down to `RING_D_MIN` (descending); each ring's alpha is the
   * difference between the target profile at its own radius and at the previous
   * (larger) one, so the running sum tracks the profile.
   */
  private buildRingTable(count: number): void {
    this.ringRadius.length = 0;
    this.ringAlpha.length = 0;
    if (count <= 0) {
      return;
    }
    const ratio: number = RING_D_MIN / RING_D_MAX;
    let prev: number = 0;
    for (let k = 0; k < count; k++) {
      const u: number = count === 1 ? 0 : k / (count - 1);
      const radius: number = RING_D_MAX * Math.pow(ratio, u);
      const cur: number = GlowRenderer.targetProfile(radius);
      this.ringRadius.push(radius);
      this.ringAlpha.push(cur - prev);
      prev = cur;
    }
  }

  /** Call whenever the Canvas component is (re)sized. Sizes are in canvas px. */
  resize(width: number, height: number): void {
    this.vp.resize(width, height);
    this.applyCoreWidths();
    this.ready = width > 0 && height > 0;
  }

  /** Writes one trail into the shared reusable `drawing.Path`. */
  private buildPath(trail: Trail): void {
    this.path.reset();
    this.path.moveTo(trail.start.x, trail.start.y);
    const n: number = POINT_COUNT - 2;
    for (let k = 0; k < n; k++) {
      const c: Vec2 = trail.ctrl[k];
      const e: Vec2 = trail.end[k];
      this.path.quadTo(c.x, c.y, e.x, e.y);
    }
    if (INCLUDE_SPIKE) {
      this.path.moveTo(trail.start.x, trail.start.y);
      this.path.quadTo(trail.spikeCtrl.x, trail.spikeCtrl.y, trail.start.x, trail.start.y);
    }
  }

  /**
   * Draws one frame. `canvas` comes from `DrawingRenderingContext.canvas`;
   * `time` is the shader's `time` uniform.
   *
   * The caller must call `DrawingRenderingContext.invalidate()` afterwards to
   * make the component repaint.
   */
  render(canvas: drawing.Canvas, time: number): void {
    if (!this.ready) {
      return;
    }

    // Clear to black — the shader writes an opaque colour, it never blends.
    canvas.drawColor(this.black, drawing.BlendMode.SRC);

    for (let i = 0; i < this.trails.length; i++) {
      this.trails[i].update(time, this.vp);
    }

    const radius: number = this.vp.glowRadiusPx();
    if (this.mode === GlowMode.RINGS) {
      // Widest ring first: with additive blending the order does not matter for
      // the result, but drawing the huge strokes first keeps the small ones on
      // top of an already-saturated background, which hides any stair-stepping.
      for (let k = this.ringRadius.length - 1; k >= 0; k--) {
        const width: number = 2 * this.ringRadius[k] * radius;
        const a: number = Math.round(this.ringAlpha[k] * 255);
        if (a <= 0) {
          continue;
        }
        for (let i = 0; i < this.trails.length; i++) {
          const pen: drawing.Pen = this.glowPens[i];
          const spec: TrailSpec = this.trails[i].spec;
          pen.setColor(a, Math.round(spec.glowR * 255), Math.round(spec.glowG * 255),
            Math.round(spec.glowB * 255));
          pen.setStrokeWidth(width);

          this.buildPath(this.trails[i]);
          canvas.attachPen(pen);
          canvas.drawPath(this.path);
          canvas.detachPen();
        }
      }
    } else {
      for (let p = 0; p < BLUR_PASSES.length; p++) {
        const pass: BlurPass = BLUR_PASSES[p];
        const a: number = Math.round(pass.alpha * 255);
        for (let i = 0; i < this.trails.length; i++) {
          const pen: drawing.Pen = this.blurPens[i];
          const spec: TrailSpec = this.trails[i].spec;
          pen.setColor(a, Math.round(spec.glowR * 255), Math.round(spec.glowG * 255),
            Math.round(spec.glowB * 255));
          pen.setStrokeWidth(pass.width * radius);
          // NORMAL is the blur the pass table was fitted against: it convolves
          // the whole stroke, so the band's profile is exactly
          // `Q(d - w/2) - Q(d + w/2)` — a box convolved with a Gaussian.
          // SOLID would keep full alpha right up to the band edge and only
          // soften outward, which shifts every band and re-introduces steps.
          pen.setMaskFilter(drawing.MaskFilter.createBlurMaskFilter(drawing.BlurType.NORMAL,
            radius * pass.sigmaFactor));

          this.buildPath(this.trails[i]);
          canvas.attachPen(pen);
          canvas.drawPath(this.path);
          canvas.detachPen();

          // Drop the native blur filter again as soon as it is unused.
          pen.setMaskFilter(null);
        }
      }
    }

    // Additive white on top of the already-saturated coloured halo.
    //
    // Order matters visually even though PLUS is commutative: the lift opens the
    // near field up toward white (emulating the shader's tone map), then the
    // shoulder and the solid core finish it. Because the halo underneath is
    // saturated, `min(1 + colour, 1)` lands on pure white in the centre — which
    // is why the core must be drawn with PLUS and not `source-over`.
    for (let i = 0; i < this.trails.length; i++) {
      const trail: Trail = this.trails[i];
      this.buildPath(trail);
      this.strokeWith(canvas, this.liftPens[i]);
      this.strokeWith(canvas, this.coreHaloPens[i]);
      this.strokeWith(canvas, this.corePens[i]);
    }
  }

  /** `attachPen` -> `drawPath` -> `detachPen` against the already-built path. */
  private strokeWith(canvas: drawing.Canvas, pen: drawing.Pen): void {
    canvas.attachPen(pen);
    canvas.drawPath(this.path);
    canvas.detachPen();
  }
}
