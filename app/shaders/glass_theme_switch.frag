// Native distance-field renderer for the observed Glass Light Toggle optics.
// Visual reference: https://experiments.thisiswhitespace.com/glass-light-toggle
// Coordinates and optical equations are implemented for Flutter runtime effects.
#include <flutter/runtime_effect.glsl>
precision highp float;

uniform vec2 viewport;
uniform vec2 origin;
uniform float zoom;
uniform float displayRatio;
uniform vec2 handle;
uniform vec2 extent;
uniform float rounding;
uniform float daylight;
uniform float seconds;
uniform float energy;
uniform float raised;
uniform float orbitAngle;
uniform vec3 lamp;
uniform float refraction;
uniform float frost;
uniform float pixelGlow;
uniform float stripHalfAngle;
uniform sampler2D matrixImage;
uniform sampler2D diffuseImage;
out vec4 fragColor;

const vec2 trackExtent = vec2(216.0, 112.0);
const float trackRadius = 72.0;
const vec2 textureExtent = vec2(552.0, 344.0);

float roundedDistance(vec2 point, vec2 halfSize, float radius) {
  vec2 outside = abs(point) - halfSize + radius;
  return length(max(outside, 0.0)) + min(max(outside.x, outside.y), 0.0) - radius;
}

float handleDistance(vec2 point) {
  return roundedDistance(point - handle, extent, rounding);
}

float stripDistance(vec2 point) {
  vec2 offset = point - handle;
  float angularError = atan(sin(atan(offset.y, offset.x) - orbitAngle),
                            cos(atan(offset.y, offset.x) - orbitAngle));
  vec2 deviation = vec2(handleDistance(point) - 6.5,
                       max(abs(angularError) - stripHalfAngle, 0.0) * 104.0);
  return length(deviation) - 1.5;
}

vec3 illuminate(vec3 surface, float amount) {
  float coverage = min(0.88, 1.0 - exp(-amount * 1.3));
  vec3 tinted = mix(surface, lamp * 1.04 + 0.03, coverage);
  return mix(surface + lamp * amount, tinted, daylight);
}

float sampleMatrix(vec2 point, bool diffuse) {
  vec2 uv = point / textureExtent + 0.5;
  if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
    return 0.0;
  }
  return diffuse ? texture(diffuseImage, uv).a : texture(matrixImage, uv).a;
}

vec4 underneath(vec2 point, float softness, vec2 chromatic) {
  float shading = smoothstep(-14.0, 3.0,
      roundedDistance(point - vec2(0.0, 7.0), trackExtent, trackRadius));
  vec3 floorColor = vec3(mix(0.030, 0.900, daylight));
  floorColor *= 1.0 + point.y / trackExtent.y * mix(0.05, 0.012, daylight);
  floorColor = mix(floorColor * (1.0 - shading * 0.6),
                   floorColor - shading * 0.085, daylight);
  float distanceToLight = max(stripDistance(point), 0.0);
  float wash = (0.85 * exp(-distanceToLight / 14.0) +
                0.32 * exp(-distanceToLight / 55.0)) * energy;
  floorColor = illuminate(floorColor, wash * 0.55);

  vec3 sharp = vec3(sampleMatrix(point - chromatic, false),
                    sampleMatrix(point, false),
                    sampleMatrix(point + chromatic, false));
  vec3 soft = vec3(sampleMatrix(point - chromatic, true),
                   sampleMatrix(point, true),
                   sampleMatrix(point + chromatic, true));
  vec3 coverage = clamp(mix(sharp, soft * 1.35, softness), 0.0, 1.0);
  float brightFloor = smoothstep(0.40, 0.56, dot(floorColor, vec3(0.299, 0.587, 0.114)));
  vec3 ink = mix(vec3(1.0, 0.965, 0.925), vec3(0.11, 0.105, 0.10), brightFloor);
  ink += mix(lamp * wash * 0.9, vec3(0.25, 0.08, 0.0) * wash, daylight);
  vec3 result = mix(floorColor, ink, coverage);
  result += vec3(1.0, 0.78, 0.55) * sampleMatrix(point, true) * pixelGlow * (1.0 - daylight);
  return vec4(result, coverage.g);
}

float grain(vec2 point) {
  vec2 value = fract(point * vec2(443.897, 441.423));
  value += dot(value, value.yx + 19.19);
  return fract((value.x + value.y) * value.x);
}

void main() {
  vec2 screenPoint = FlutterFragCoord().xy;
  vec2 point = (screenPoint - origin) / zoom;
  vec2 screenUv = screenPoint / viewport;
  float sky = smoothstep(1.5, 0.0,
      length((screenUv - vec2(0.92, -0.08)) * vec2(1.0, 1.25)));
  vec3 color = mix(vec3(mix(0.040, 0.120, sky)),
                   vec3(mix(0.800, 0.925, sky)), daylight);
  float trackDistance = roundedDistance(point, trackExtent, trackRadius);

  float shadow = 1.0 - smoothstep(-10.0, 34.0,
      roundedDistance(point - vec2(0.0, 14.0), trackExtent, trackRadius));
  color *= 1.0 - shadow * mix(0.5, 0.17, daylight);
  float contact = 1.0 - smoothstep(-2.0, 4.0,
      roundedDistance(point - vec2(0.0, 1.5), trackExtent, trackRadius));
  color *= 1.0 - contact * mix(0.3, 0.08, daylight);
  float lampDistance = max(stripDistance(point), 0.0);
  color = illuminate(color, (0.5 * exp(-lampDistance / 18.0) +
      0.34 * exp(-lampDistance / 85.0)) * energy * 0.6);

  if (trackDistance < 2.0) {
    vec3 floorColor = underneath(point, 0.0, vec2(0.0)).rgb;
    float underHandle = roundedDistance(
        point - handle - vec2(0.0, 7.0 + raised * 5.0), extent, rounding);
    floorColor *= 1.0 - (1.0 - smoothstep(-8.0, 20.0 + raised * 8.0, underHandle))
        * mix(0.6, 0.2, daylight);
    float rim = 1.0 - smoothstep(0.0, 1.3, abs(trackDistance + 0.75));
    float lower = smoothstep(-67.2, 112.0, point.y);
    floorColor += rim * mix(mix(0.035, 0.09, lower), mix(-0.07, 0.07, lower), daylight);
    color = mix(floorColor, color, smoothstep(-0.6, 0.6, trackDistance));
  }

  float glassDistance = handleDistance(point);
  if (glassDistance < 2.0) {
    vec2 normal = vec2(
        handleDistance(point + vec2(0.5, 0.0)) - handleDistance(point - vec2(0.5, 0.0)),
        handleDistance(point + vec2(0.0, 0.5)) - handleDistance(point - vec2(0.0, 0.5)));
    normal /= max(length(normal), 0.0001);
    float depth = max(-glassDistance, 0.0);
    float bevel = pow(1.0 - clamp(depth / 26.0, 0.0, 1.0), 2.6);
    vec2 insetPoint = point - normal * bevel * refraction - (point - handle) * 0.055;
    vec4 content = underneath(insetPoint, 0.06 + frost * bevel,
        normal * bevel * 3.2 + (point - handle) * 0.006);
    float vertical = clamp((point.y - handle.y + extent.y) / (2.0 * extent.y), 0.0, 1.0);
    vec3 shadedGlass = content.rgb * 0.84 + 0.135 * (1.0 - vertical * 0.55);
    vec3 paleGlass = mix(content.rgb, vec3(0.99), 0.5 * (1.0 - content.a * 0.8));
    vec3 glassColor = mix(shadedGlass, paleGlass, daylight);
    float glowDistance = max(stripDistance(point), 0.0);
    float scattering = (exp(-glowDistance / 24.0) * 0.8 + exp(-glowDistance / 64.0) * 0.2) * energy;
    glassColor = illuminate(glassColor, scattering * 0.8);
    glassColor = illuminate(glassColor, exp(-depth / 2.2) * exp(-glowDistance / 40.0) * energy * 1.3);
    float lighting = dot(normal, normalize(vec2(-0.35, -1.0)));
    glassColor += pow(max(lighting, 0.0), 2.0) * exp(-depth / 1.25) * mix(0.42, 0.7, daylight);
    glassColor += max(lighting, 0.0) * bevel * mix(0.07, 0.16, daylight);
    glassColor *= 1.0 - max(-lighting, 0.0) * bevel * mix(0.28, 0.07, daylight);
    glassColor += exp(-depth / 0.7) * mix(0.07, 0.12, daylight);
    color = mix(glassColor, color, smoothstep(-0.7, 0.7, glassDistance));
  }

  float emitterDistance = stripDistance(point);
  float emitterMask = 1.0 - smoothstep(-0.6, 0.6, emitterDistance);
  vec3 hotLamp = mix(lamp * 1.05, mix(lamp, vec3(1.0), 0.65),
      smoothstep(-0.2, -1.4, emitterDistance));
  color = mix(color, hotLamp * (0.8 + 0.35 * energy), emitterMask);
  color = illuminate(color, exp(-max(emitterDistance, 0.0) / 4.5) * 0.55 * energy * (1.0 - emitterMask));
  vec2 physicalPixel = vec2(screenPoint.x, viewport.y - screenPoint.y) * displayRatio;
  color += (grain(physicalPixel + fract(seconds) * 91.7) - 0.5) * 0.022;
  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
