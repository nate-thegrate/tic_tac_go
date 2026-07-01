#include <flutter/runtime_effect.glsl>

// Graphite / pencil stroke: base color with HiDPI grain and slight alpha break-up.
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

  // Fine tip texture + coarser deposition variation along the stroke.
  float fine = hash12(floor(pix));
  float coarse = hash12(floor(pix * 0.37 + vec2(13.1, 7.7)));
  float grain = mix(fine, coarse, 0.35);

  // Pressure / graphite density variation.
  float density = mix(0.72, 1.12, grain);
  density = mix(1.0, density, uGrain);

  // Dry-media alpha chatter; occasional lighter skips (paper tooth).
  float alpha = uBaseColor.a * mix(0.78, 1.0, grain);
  float skip = step(0.93, hash12(floor(pix * 0.28 + 41.0)));
  alpha *= 1.0 - skip * 0.4 * uGrain;
  alpha = clamp(alpha, 0.0, 1.0);

  vec3 color = clamp(uBaseColor.rgb * density, 0.0, 1.0);
  fragColor = vec4(color, alpha);
}
