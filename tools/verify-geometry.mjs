/*
 * verify-geometry.mjs
 *
 * Numerical proof that the quadratic-Bezier chain built by GlowCurve.ets is the
 * same chain the original GLSL walks in getSegment().
 *
 * The GLSL is transcribed verbatim below (sdBezier, getLemniscatePosition, the
 * getSegment loop) and used as the reference. The "port" side reproduces what
 * Trail.update() + GlowRenderer.buildPath() feed into drawing.Path:
 *
 *     moveTo(mid(0,1))
 *     quadTo(P1, mid(1,2)) ... quadTo(P6, mid(6,7))
 *
 * Run: node tools/verify-geometry.mjs
 */

// ---------------------------------------------------------------------------
// Reference: verbatim port of the GLSL from the original script.js
// ---------------------------------------------------------------------------
const POINT_COUNT = 8;
const SEG_LEN = 0.25;
const SPEED = -0.7;
const PHASE_PERIOD = 6.28;

const fract = (x) => x - Math.floor(x);

function sdBezier(pos, A, B, C) {
  const ax = B.x - A.x, ay = B.y - A.y;
  const bx = A.x - 2 * B.x + C.x, by = A.y - 2 * B.y + C.y;
  const cx = ax * 2, cy = ay * 2;
  const dx = A.x - pos.x, dy = A.y - pos.y;

  const kk = 1.0 / (bx * bx + by * by);
  const kx = kk * (ax * bx + ay * by);
  const ky = kk * (2 * (ax * ax + ay * ay) + (dx * bx + dy * by)) / 3.0;
  const kz = kk * (dx * ax + dy * ay);

  const p = ky - kx * kx;
  const p3 = p * p * p;
  const q = kx * (2 * kx * kx - 3 * ky) + kz;
  const h = q * q + 4 * p3;

  let res = 0;
  if (h >= 0) {
    const sh = Math.sqrt(h);
    const xs = [(sh - q) / 2, (-sh - q) / 2];
    const uv = xs.map((x) => Math.sign(x) * Math.pow(Math.abs(x), 1 / 3));
    let t = uv[0] + uv[1] - kx;
    t = Math.min(1, Math.max(0, t));
    const qx = dx + (cx + bx * t) * t;
    const qy = dy + (cy + by * t) * t;
    res = Math.hypot(qx, qy);
  } else {
    const z = Math.sqrt(-p);
    const v = Math.acos(q / (p * z * 2)) / 3;
    const m = Math.cos(v);
    const n = Math.sin(v) * 1.732050808;
    const ts = [m + m, -n - m, n - m].map((t) => Math.min(1, Math.max(0, t * z - kx)));
    res = Infinity;
    for (const t of ts) {
      const qx = dx + (cx + bx * t) * t;
      const qy = dy + (cy + by * t) * t;
      res = Math.min(res, qx * qx + qy * qy);
    }
    res = Math.sqrt(res);
  }
  return res;
}

function getLemniscatePosition(t) {
  const a = (1.0 + 0.5 + 0.5 * Math.sin(t)) * 15.0;
  const s = Math.sin(t), c = Math.cos(t);
  return {
    x: (a * c) / (1.0 + s * s),
    y: (a * s * c) / (1.0 + s * s)
  };
}

/** Reference: the GLSL getSegment() loop, including the degenerate i = 0 pass. */
function getSegmentGLSL(time, offset, scale, pos) {
  const phase = offset + fract(SPEED * time) * PHASE_PERIOD;
  const points = [];
  for (let i = 0; i < POINT_COUNT; i++) {
    points.push(getLemniscatePosition(phase + i * SEG_LEN));
  }
  let c = {
    x: (points[0].x + points[1].x) / 2,
    y: (points[0].y + points[1].y) / 2
  };
  let dist = 10000;
  for (let i = 0; i < POINT_COUNT - 1; i++) {
    const cPrev = c;
    c = {
      x: (points[i].x + points[i + 1].x) / 2,
      y: (points[i].y + points[i + 1].y) / 2
    };
    dist = Math.min(dist, sdBezier(pos,
      { x: scale * cPrev.x, y: scale * cPrev.y },
      { x: scale * points[i].x, y: scale * points[i].y },
      { x: scale * c.x, y: scale * c.y }));
  }
  return Math.max(0, dist);
}

// ---------------------------------------------------------------------------
// Port side: exactly what GlowCurve.Trail + GlowRenderer.buildPath produce
// ---------------------------------------------------------------------------
function getSegmentPort(time, offset, scale, pos, includeSpike) {
  const phase = offset + fract(SPEED * time) * PHASE_PERIOD;
  const P = [];
  for (let i = 0; i < POINT_COUNT; i++) {
    P.push(getLemniscatePosition(phase + i * SEG_LEN));
  }
  const M = [];
  for (let i = 0; i < POINT_COUNT - 1; i++) {
    M.push({ x: (P[i].x + P[i + 1].x) / 2, y: (P[i].y + P[i + 1].y) / 2 });
  }
  // Chain: mid(0,1) -[P1]-> mid(1,2) -[P2]-> ... -[P6]-> mid(6,7)
  let dist = 10000;
  for (let k = 0; k < POINT_COUNT - 2; k++) {
    dist = Math.min(dist, sdBezier(pos,
      { x: scale * M[k].x, y: scale * M[k].y },
      { x: scale * P[k + 1].x, y: scale * P[k + 1].y },
      { x: scale * M[k + 1].x, y: scale * M[k + 1].y }));
  }
  if (includeSpike) {
    // The original's i = 0 pass: sdBezier(mid01, P0, mid01)
    dist = Math.min(dist, sdBezier(pos,
      { x: scale * M[0].x, y: scale * M[0].y },
      { x: scale * P[0].x, y: scale * P[0].y },
      { x: scale * M[0].x, y: scale * M[0].y }));
  }
  return Math.max(0, dist);
}

// ---------------------------------------------------------------------------
// Compare
// ---------------------------------------------------------------------------
const W = 900, H = 700;
const scale = 0.000015 * H;
const N = 400;

let worstClean = 0, worstSpike = 0, mismatchClean = 0, mismatchSpike = 0;

for (const time of [0.0, 0.9, 2.5, 4.1, 7.7]) {
  for (const offset of [0.0, 3.7]) {
    for (let iy = 0; iy < N; iy++) {
      for (let ix = 0; ix < N; ix++) {
        // Sample the shader's pos-space directly, covering the figure-eight.
        const pos = {
          x: -0.30 + 0.60 * (ix / (N - 1)),
          y: -0.16 + 0.32 * (iy / (N - 1))
        };
        const ref = getSegmentGLSL(time, offset, scale, pos);
        const clean = getSegmentPort(time, offset, scale, pos, false);
        const spike = getSegmentPort(time, offset, scale, pos, true);

        const dClean = Math.abs(ref - clean);
        const dSpike = Math.abs(ref - spike);
        if (dClean > 1e-12) mismatchClean++;
        if (dSpike > 1e-12) mismatchSpike++;
        worstClean = Math.max(worstClean, dClean);
        worstSpike = Math.max(worstSpike, dSpike);
      }
    }
  }
}

console.log(`samples compared : ${5 * 2 * N * N}`);
console.log(`WITHOUT the original's degenerate i=0 segment:`);
console.log(`  mismatching    : ${mismatchClean}`);
console.log(`  max |ref-port| : ${worstClean.toExponential(3)}`);
console.log(`WITH the degenerate i=0 segment (INCLUDE_SPIKE = true):`);
console.log(`  mismatching    : ${mismatchSpike}`);
console.log(`  max |ref-port| : ${worstSpike.toExponential(3)}`);
console.log('');

const ok = worstSpike < 1e-12;
console.log(ok
  ? 'PASS — the ported Bezier chain is numerically identical to the GLSL.'
  : 'FAIL — the ported chain diverges from the GLSL.');
process.exit(ok ? 0 : 1);
