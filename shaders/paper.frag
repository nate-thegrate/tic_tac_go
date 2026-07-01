#include <flutter/runtime_effect.glsl>

// Paper fill: base color + HiDPI-aware grain.
// FlutterFragCoord is logical pixels; multiply by uDpr for physical-pixel detail.
uniform vec2 uSize;
uniform vec4 uBaseColor;
uniform float uGrain;
uniform float uScale;
uniform float uDpr;

out vec4 fragColor;

// Higher-quality 2D hashes (less lattice / axial streaking than sin-dot hashes).
float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

// Gradient noise with random per-cell gradients (less "tiled grid" than value noise).
float gradientNoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);

  vec2 u = f * f * (3.0 - 2.0 * f);

  float a = dot(hash22(i + vec2(0.0, 0.0)) * 2.0 - 1.0, f - vec2(0.0, 0.0));
  float b = dot(hash22(i + vec2(1.0, 0.0)) * 2.0 - 1.0, f - vec2(1.0, 0.0));
  float c = dot(hash22(i + vec2(0.0, 1.0)) * 2.0 - 1.0, f - vec2(0.0, 1.0));
  float d = dot(hash22(i + vec2(1.0, 1.0)) * 2.0 - 1.0, f - vec2(1.0, 1.0));

  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Rotate domain between octaves (golden-angle-ish) to break axis-aligned patterns.
vec2 rotate(vec2 p, float a) {
  float s = sin(a);
  float c = cos(a);
  return mat2(c, -s, s, c) * p;
}

float fbm(vec2 p) {
  float v = 0.0;
  float amp = 0.5;
  // Irrational-ish angle so octaves don't reinforce a single lattice.
  const float ang = 2.399963229728653; // ~golden angle in radians
  for (int i = 0; i < 4; i++) {
    v += amp * gradientNoise(p);
    p = rotate(p * 2.07, ang);
    amp *= 0.5;
  }
  return v;
}

void main() {
  // Physical-pixel coords so grain is not blocky when logical size is upscaled.
  vec2 pix = FlutterFragCoord().xy * uDpr;

  // Uncorrelated per-pixel speckles (paper pulp / film grain) — no grid interpolation.
  float speck = hash12(floor(pix) + vec2(17.13, 9.71));
  // A second independent field at a slight offset avoids mono-chrome "bit" look.
  float speck2 = hash12(floor(pix * 1.37 + vec2(91.2, 47.5)));
  float white = (speck + speck2) * 0.5;

  // Soft, large-scale unevenness without repeating lattice artifacts.
  float soft = fbm(pix * uScale * 0.08);

  // Map soft (~[-1,1]-ish from gradient noise fbm) and white ([0,1]) to grain.
  float grain = ((white - 0.5) * 1.35 + soft * 0.35) * uGrain;

  vec3 color = clamp(uBaseColor.rgb + grain, 0.0, 1.0);
  fragColor = vec4(color, uBaseColor.a);
}
