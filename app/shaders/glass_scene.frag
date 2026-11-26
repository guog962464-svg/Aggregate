#include <flutter/runtime_effect.glsl>
precision highp float;

uniform vec2 viewport;
uniform float daylight;
uniform float seconds;
uniform float displayRatio;
uniform float hasEmitter;
uniform vec2 emitterCenter;
uniform float emitterScale;
uniform vec2 emitterHandle;
uniform vec2 emitterExtent;
uniform float emitterRounding;
uniform float emitterAngle;
uniform float emitterEnergy;
uniform vec3 emitterLamp;
uniform float emitterHalfAngle;
out vec4 fragColor;

float grain(vec2 point) {
  vec2 value = fract(point * vec2(443.897, 441.423));
  value += dot(value, value.yx + 19.19);
  return fract((value.x + value.y) * value.x);
}

float roundedDistance(vec2 point, vec2 halfSize, float radius) {
  vec2 outside = abs(point) - halfSize + radius;
  return length(max(outside, 0.0)) + min(max(outside.x, outside.y), 0.0) - radius;
}

float emitterStripDistance(vec2 offset) {
  float angularError = atan(
      sin(atan(offset.y, offset.x) - emitterAngle),
      cos(atan(offset.y, offset.x) - emitterAngle));
  vec2 deviation = vec2(
      roundedDistance(offset, emitterExtent, emitterRounding) - 6.5,
      max(abs(angularError) - emitterHalfAngle, 0.0) * 104.0);
  return length(deviation) - 1.5;
}

vec3 illuminate(vec3 surface, float amount) {
  float coverage = min(0.88, 1.0 - exp(-amount * 1.3));
  vec3 tinted = mix(surface, emitterLamp * 1.04 + 0.03, coverage);
  return mix(surface + emitterLamp * amount, tinted, daylight);
}

void main() {
  vec2 screenPoint = FlutterFragCoord().xy;
  vec2 screenUv = screenPoint / viewport;
  float sky = 1.0 - smoothstep(
      0.0,
      1.5,
      length((screenUv - vec2(0.92, -0.08)) * vec2(1.0, 1.25)));
  // Keep the window backdrop on the same optical field as the theme switch.
  // The switch still paints its own lens, but its surrounding canvas no
  // longer leaves a differently tinted rectangular patch on the page.
  float darkValue = mix(0.040, 0.120, sky);
  float lightValue = mix(0.800, 0.925, sky);
  vec3 color = vec3(mix(darkValue, lightValue, daylight));
  if (hasEmitter > 0.5) {
    vec2 emitterOffset =
        (screenPoint - emitterCenter) / emitterScale - emitterHandle;
    float distanceFromHandleBox = max(
        abs(emitterOffset.x) - emitterExtent.x,
        abs(emitterOffset.y) - emitterExtent.y);
    // At the reference energy, the remaining spill is below 0.015 here; skip
    // the angular and exponential work on distant full-window pixels.
    if (distanceFromHandleBox < 280.0) {
      float lightDistance = max(emitterStripDistance(emitterOffset), 0.0);
      float spill = (0.5 * exp(-lightDistance / 18.0) +
          0.34 * exp(-lightDistance / 85.0)) * emitterEnergy;
      color = illuminate(color, spill * 0.6);
    }
  }
  vec2 physicalPixel =
      vec2(screenPoint.x, viewport.y - screenPoint.y) * displayRatio;
  color += (grain(physicalPixel + fract(seconds) * 91.7) - 0.5) * 0.022;
  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
