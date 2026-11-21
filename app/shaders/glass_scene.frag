#include <flutter/runtime_effect.glsl>
precision highp float;

uniform vec2 viewport;
uniform float daylight;
uniform float seconds;
uniform float displayRatio;
out vec4 fragColor;

float grain(vec2 point) {
  vec2 value = fract(point * vec2(443.897, 441.423));
  value += dot(value, value.yx + 19.19);
  return fract((value.x + value.y) * value.x);
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
  vec2 physicalPixel =
      vec2(screenPoint.x, viewport.y - screenPoint.y) * displayRatio;
  color += (grain(physicalPixel + fract(seconds) * 91.7) - 0.5) * 0.022;
  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
