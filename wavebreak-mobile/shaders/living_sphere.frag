// WAVEBREAK "living sphere": an equirectangular Earth texture projected
// onto a real sphere and rotated by longitude (the surface moves across
// the visible hemisphere; the picture itself is never just slid sideways).
//
// uMode 0 — the red glass connect core: desaturated texture through a
//           crimson tint, meridians/parallels, moving surface currents,
//           top-left highlight and bottom-right shadow.
// uMode 1 — the natural night Earth of the sign-in scene: cold surface,
//           city lights, blue atmosphere.
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;      // canvas size in px
uniform float uTime;     // seconds, drives the currents
uniform float uRot;      // longitude offset, radians
uniform float uEnergy;   // 0 idle .. 1 connected (glow, contrast)
uniform float uPulse;    // 0..1 transient pulse (connecting / success)
uniform float uMode;     // 0 red core, 1 natural earth
uniform float uWarn;     // 0..1 amber error tint
uniform sampler2D uTex;

out vec4 fragColor;

const float PI = 3.14159265;

// 1 at x <= a, 0 at x >= b. smoothstep() with edge0 > edge1 is undefined
// in GLSL and renders garbage on some mobile GPUs, so never call it that way.
float falloff(float a, float b, float x) {
  return 1.0 - smoothstep(a, b, x);
}

float lineMask(float v, float width) {
  float d = abs(fract(v) - 0.5);
  return falloff(0.0, width, 0.5 - d);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 c = uSize * 0.5;
  float radius = min(uSize.x, uSize.y) * 0.5 * (uMode > 0.5 ? 0.98 : 0.90);
  vec2 p = (frag - c) / radius;
  p.y = -p.y;
  float r2 = dot(p, p);

  // Atmosphere / outer glow ring, outside the disc.
  if (r2 > 1.0) {
    float r = sqrt(r2);
    float halo = falloff(1.0, 1.16, r);
    if (uMode > 0.5) {
      vec3 atm = vec3(0.30, 0.78, 1.0) * (0.55 + 0.15 * sin(uTime * 0.6));
      fragColor = vec4(atm * halo * 0.65, halo * 0.65);
    } else {
      vec3 glow = mix(vec3(1.0, 0.20, 0.30), vec3(1.0, 0.62, 0.20), uWarn);
      float a = halo * (0.30 + 0.45 * uEnergy + 0.35 * uPulse);
      fragColor = vec4(glow * a, a);
    }
    return;
  }

  float z = sqrt(1.0 - r2);
  vec3 n = vec3(p.x, p.y, z);

  // Axial tilt: rotate the sampling normal around X.
  float tilt = 0.32;
  vec3 m = vec3(n.x, n.y * cos(tilt) - n.z * sin(tilt), n.y * sin(tilt) + n.z * cos(tilt));
  float lat = asin(clamp(m.y, -1.0, 1.0));
  float lon = atan(m.x, m.z) + uRot;
  vec2 uv = vec2(fract(lon / (2.0 * PI) + 0.5), 0.5 - lat / PI);
  vec3 tex = texture(uTex, uv).rgb;

  vec3 light = normalize(vec3(-0.55, 0.62, 0.58));
  float diff = clamp(dot(n, light), 0.0, 1.0);
  float rim = pow(1.0 - z, 2.2);
  float spec = pow(clamp(dot(reflect(-light, n), vec3(0.0, 0.0, 1.0)), 0.0, 1.0), 22.0);

  vec3 col;
  float alpha = 1.0;
  if (uMode > 0.5) {
    // Natural night Earth, shaded like the V5 mockup (wave-scene-v5.js):
    // a cold surface (red pulled down, blue kept), lit from the upper
    // left, darker towards the bottom, a cyan limb with a slow pulse and
    // warm city lights only where the texture is bright on the night side.
    float lum = dot(tex, vec3(0.299, 0.587, 0.114));
    float coldLight = 0.22 + 0.5 * max(0.0, dot(n, vec3(-0.32, 0.58, 0.56)));
    vec3 surface = tex * coldLight * vec3(0.48, 0.80, 1.03);
    float cities = smoothstep(0.62, 0.9, lum) * (1.0 - diff);
    col = surface + vec3(1.0, 0.82, 0.52) * cities * 0.18;
    float limb = pow(1.0 - z, 5.0) * (0.68 + 0.15 * sin(uTime * 0.6 + p.x * 3.0));
    col += vec3(0.11, 0.62, 0.75) * limb;
    col += vec3(0.8, 0.95, 1.0) * spec * 0.08;
  } else {
    // Red glass core.
    float lum = dot(tex, vec3(0.299, 0.587, 0.114));
    vec3 crimsonDeep = mix(vec3(0.20, 0.015, 0.04), vec3(0.20, 0.09, 0.0), uWarn);
    vec3 crimson = mix(vec3(1.0, 0.20, 0.31), vec3(1.0, 0.62, 0.18), uWarn);
    float detail = smoothstep(0.05, 0.75, lum);
    col = mix(crimsonDeep, crimson, 0.30 + 0.55 * detail * (0.55 + 0.45 * diff));
    col *= 0.55 + 0.30 * uEnergy + 0.55 * diff;

    // Meridians (13) and parallels (7), front hemisphere only by construction.
    float mer = lineMask(lon / (2.0 * PI) * 13.0, 0.035 / max(z, 0.25));
    float par = lineMask(lat / PI * 7.0 + 0.5, 0.03);
    col += vec3(1.0, 0.72, 0.76) * (mer + par) * (0.10 + 0.10 * uEnergy) * (0.4 + 0.6 * z);

    // Surface currents: latitude bands that wave along longitude and time.
    float currents = 0.0;
    for (int i = 0; i < 9; i++) {
      float fi = float(i);
      float band = -0.9 + fi * 0.22 + 0.10 * sin(lon * 2.0 + uTime * (0.45 + 0.05 * fi) + fi * 1.7);
      currents += falloff(0.0, 0.022, abs(lat - band)) * (0.35 + 0.65 * fract(fi * 0.37));
    }
    col += vec3(1.0, 0.55, 0.62) * currents * (0.10 + 0.22 * uEnergy + 0.25 * uPulse) * z;

    // Glass: rim light, top-left highlight, bottom-right shadow.
    col += crimson * rim * (0.55 + 0.35 * uEnergy + 0.4 * uPulse);
    col += vec3(1.0, 0.92, 0.94) * spec * 0.55;
    float shadow = smoothstep(-0.2, 1.1, p.x * 0.7 - p.y * 0.7);
    col *= 1.0 - 0.45 * shadow;
    col += vec3(1.0, 0.85, 0.88) * falloff(0.0, 0.55, length(p - vec2(-0.42, 0.48))) * 0.18;
  }

  // Soft anti-aliased edge.
  float edge = falloff(0.985, 1.0, sqrt(r2));
  fragColor = vec4(col * edge, alpha * edge);
}
