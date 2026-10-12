/* A real rotating sphere, drawn in one WebGL pass. Texture: NASA Blue Marble.
 * No framework, remote requests or animation work while outside the viewport. */
(() => {
  const motion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const vertex = `attribute vec2 position; varying vec2 uv;
    void main() { uv = position; gl_Position = vec4(position, 0., 1.); }`;
  const fragment = `precision mediump float;
    varying vec2 uv; uniform sampler2D earth; uniform float angle; uniform float hologram;
    const float PI = 3.14159265;
    void main() {
      vec2 p = uv * 1.12;
      float r = length(p);
      vec3 cyan = vec3(.24, .82, .95);
      if (r > 1.) {
        float glow = exp(-(r - 1.) * 49.) * .38;
        gl_FragColor = vec4(cyan, glow * (1. - smoothstep(1.02, 1.12, r)));
        return;
      }
      vec3 n = vec3(p, sqrt(max(0., 1. - dot(p, p))));
      // Tilt the axis, then rotate longitude rather than the flat image.
      float tilt = -.22;
      vec3 t = vec3(n.x * cos(tilt) - n.y * sin(tilt), n.x * sin(tilt) + n.y * cos(tilt), n.z);
      float lon = atan(t.x, t.z) + angle;
      float lat = asin(t.y);
      vec2 coord = vec2(fract(lon / (2. * PI) + .5), .5 - lat / PI);
      vec3 map = texture2D(earth, coord).rgb;
      float light = max(dot(n, normalize(vec3(-.65, .8, 1.1))), 0.);
      float rim = pow(1. - n.z, 3.5);
      vec3 natural = map * vec3(.66, .94, 1.16) * (.11 + .86 * light);
      natural += cyan * rim * .38;
      float terrain = dot(map, vec3(.3, .59, .11));
      float meridian = 1. - smoothstep(.006, .014, abs(sin(lon * 12.)));
      float parallel = 1. - smoothstep(.006, .014, abs(sin(lat * 12.)));
      vec3 digital = vec3(.015, .09, .15) + cyan * terrain * .78;
      digital += cyan * max(meridian, parallel) * .18;
      digital *= .45 + .55 * light;
      digital += cyan * rim * .7;
      gl_FragColor = vec4(mix(natural, digital, hologram), 1.);
    }`;

  const textures = new Map();
  function getImage(src) {
    if (!textures.has(src)) textures.set(src, new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = reject;
      img.src = src;
    }));
    return textures.get(src);
  }

  document.querySelectorAll('[data-earth]').forEach(canvas => {
    const gl = canvas.getContext('webgl', { alpha: true, premultipliedAlpha: false, antialias: false, depth: false, powerPreference: 'low-power' });
    if (!gl) return; // The styled fallback remains visible with JS/WebGL disabled.
    let program;
    try {
      const shader = (kind, source) => {
        const result = gl.createShader(kind);
        gl.shaderSource(result, source);
        gl.compileShader(result);
        if (!gl.getShaderParameter(result, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(result));
        return result;
      };
      program = gl.createProgram();
      gl.attachShader(program, shader(gl.VERTEX_SHADER, vertex));
      gl.attachShader(program, shader(gl.FRAGMENT_SHADER, fragment));
      gl.linkProgram(program);
      if (!gl.getProgramParameter(program, gl.LINK_STATUS)) return;
      gl.useProgram(program);
      const buffer = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 1,-1, -1,1, -1,1, 1,-1, 1,1]), gl.STATIC_DRAW);
      const position = gl.getAttribLocation(program, 'position');
      gl.enableVertexAttribArray(position);
      gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);
      gl.uniform1f(gl.getUniformLocation(program, 'hologram'), canvas.dataset.hologram ? 1 : 0);
    } catch (_) { return; }

    let loaded = false, visible = false, frame = null, last = 0, rotation = .35;
    const angle = gl.getUniformLocation(program, 'angle');
    const draw = () => {
      if (!loaded || gl.isContextLost()) return;
      const size = Math.max(1, Math.round(canvas.clientWidth * Math.min(devicePixelRatio || 1, 1.5)));
      if (canvas.width !== size || canvas.height !== size) {
        canvas.width = canvas.height = size;
        gl.viewport(0, 0, size, size);
      }
      gl.uniform1f(angle, rotation);
      gl.drawArrays(gl.TRIANGLES, 0, 6);
    };
    const tick = time => {
      frame = requestAnimationFrame(tick);
      if (time - last < 32) return; // 30 fps is enough for a slowly turning planet.
      rotation += Math.min(time - last, 64) * .000045;
      last = time;
      draw();
    };
    const update = () => {
      if (frame !== null) cancelAnimationFrame(frame);
      frame = null;
      if (!loaded || !visible || document.hidden || gl.isContextLost()) return;
      draw();
      if (!motion.matches) { last = performance.now(); frame = requestAnimationFrame(tick); }
    };
    let textureStarted = false;
    const loadTexture = () => {
      if (textureStarted) return;
      textureStarted = true;
      getImage(canvas.dataset.texture).then(img => {
        if (gl.isContextLost()) return;
        const texture = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, gl.RGB, gl.UNSIGNED_BYTE, img);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        loaded = true;
        canvas.parentElement.classList.add('earth-ready');
        update();
      }).catch(() => {});
    };
    if ('IntersectionObserver' in window) {
      new IntersectionObserver(([entry]) => {
        visible = entry.isIntersecting;
        if (visible) loadTexture();
        update();
      }, { rootMargin: '100px' }).observe(canvas);
    } else { visible = true; loadTexture(); }
    new ResizeObserver(() => { if (visible) draw(); }).observe(canvas);
    document.addEventListener('visibilitychange', update);
    motion.addEventListener('change', update);
    canvas.addEventListener('webglcontextlost', () => {
      if (frame !== null) cancelAnimationFrame(frame);
      canvas.parentElement.classList.remove('earth-ready');
    });
  });
})();
