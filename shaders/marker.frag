#include <flutter/runtime_effect.glsl>

// Felt-tip marker: mostly opaque ink with visible fiber grain and soft pooling.
uniform vec2 uSize;
uniform vec4 uBaseColor;
uniform float uDpr;
uniform float uGrain;

out vec4 fragColor;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float valueNoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash12(i);
  float b = hash12(i + vec2(1.0, 0.0));
  float c = hash12(i + vec2(0.0, 1.0));
  float d = hash12(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * valueNoise(p);
    p = p * 2.07 + vec2(11.7, 7.3);
    a *= 0.5;
  }
  return v;
}

void main() {
  vec2 pix = FlutterFragCoord().xy * uDpr;
  float g = clamp(uGrain, 0.0, 2.0);

  float fiber = mix(
    valueNoise(pix * vec2(0.4, 2.2)),
    valueNoise(pix * vec2(2.0, 0.45) + 17.0),
    0.5
  );
  float pool = fbm(pix * 0.055 + vec2(3.0, 8.0));
  float speck = hash12(floor(pix));

  float grain = pool * 0.5 + fiber * 0.35 + speck * 0.15;
  grain = mix(0.5, grain, g);

  // Shade swing is stronger on dark inks (grid) where mottling reads clearly.
  float luma = dot(uBaseColor.rgb, vec3(0.299, 0.587, 0.114));
  float shadeRange = mix(0.22, 0.14, smoothstep(0.0, 0.5, luma));
  float shade = mix(1.0 - shadeRange, 1.0 + shadeRange * 0.7, smoothstep(0.2, 0.85, grain));
  vec3 base = uBaseColor.rgb;
  vec3 color = mix(vec3(luma), base, mix(0.9, 1.08, fiber));
  color = clamp(color * shade + (speck - 0.5) * 0.08 * g, 0.0, 1.0);

  float alpha = uBaseColor.a * mix(0.8, 1.0, smoothstep(0.12, 0.8, grain));
  alpha *= mix(1.0, step(0.035, speck), 0.1 * g);
  alpha = clamp(alpha, 0.0, 1.0);

  fragColor = vec4(color, alpha);
}
