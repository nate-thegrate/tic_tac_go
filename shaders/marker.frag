#include <flutter/runtime_effect.glsl>

// Felt-tip / marker stroke: saturated base color with subtle ink variation.
// FlutterFragCoord is logical pixels; multiply by uDpr for physical-pixel detail.
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

void main() {
  vec2 pix = FlutterFragCoord().xy * uDpr;

  // Soft fiber texture — markers sit more evenly than graphite.
  float fine = hash12(floor(pix));
  float coarse = hash12(floor(pix * 0.22 + vec2(9.3, 5.1)));
  float grain = mix(fine, coarse, 0.25);

  // Mild saturation/brightness chatter from ink flow, not dry-media skips.
  float flow = mix(0.94, 1.06, grain);
  flow = mix(1.0, flow, uGrain * 0.55);

  // Markers stay largely opaque with only slight edge transparency.
  float alpha = uBaseColor.a * mix(0.92, 1.0, grain);
  alpha = clamp(alpha, 0.0, 1.0);

  vec3 color = clamp(uBaseColor.rgb * flow, 0.0, 1.0);
  fragColor = vec4(color, alpha);
}
