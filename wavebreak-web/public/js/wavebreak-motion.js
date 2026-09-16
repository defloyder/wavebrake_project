(() => {
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Scroll reveal: anything marked [data-reveal] fades and rises into place
  // once, the first time it crosses into view.
  const revealTargets = document.querySelectorAll('[data-reveal]');
  if (revealTargets.length) {
    if (reduceMotion || !('IntersectionObserver' in window)) {
      revealTargets.forEach((el) => el.classList.add('is-visible'));
    } else {
      const io = new IntersectionObserver(
        (entries) => {
          entries.forEach((entry) => {
            if (!entry.isIntersecting) return;
            const el = entry.target;
            const delay = el.getAttribute('data-reveal-delay');
            if (delay) el.style.transitionDelay = `${delay}ms`;
            el.classList.add('is-visible');
            io.unobserve(el);
          });
        },
        // Positive bottom margin: start the reveal while the section is
        // still below the fold, so it's already settled by the time a
        // normal (non-instant) scroll actually brings it into frame.
        { threshold: 0.01, rootMargin: '0px 0px 20% 0px' }
      );
      revealTargets.forEach((el) => io.observe(el));
    }
  }

  // Hero parallax: the glow over the wave panel drifts toward the pointer.
  // Pure CSS custom properties, no layout thrash.
  if (!reduceMotion) {
    const scene = document.querySelector('.art-wave-scene');
    if (scene && window.matchMedia('(hover: hover)').matches) {
      let raf = null;
      scene.addEventListener('pointermove', (event) => {
        const rect = scene.getBoundingClientRect();
        const x = (event.clientX - rect.left) / rect.width;
        const y = (event.clientY - rect.top) / rect.height;
        if (raf) cancelAnimationFrame(raf);
        raf = requestAnimationFrame(() => {
          scene.style.setProperty('--glowX', `${(x * 100).toFixed(1)}%`);
          scene.style.setProperty('--glowY', `${(y * 100).toFixed(1)}%`);
        });
      });
      scene.addEventListener('pointerleave', () => {
        if (raf) cancelAnimationFrame(raf);
        scene.style.setProperty('--glowX', '82%');
        scene.style.setProperty('--glowY', '8%');
      });
    }
  }

  // Hero wave: the breakwater motif, rendered live instead of a static
  // gradient — three offset sine layers, amplitude tapered at the edges.
  const waveCanvas = document.getElementById('wb-wave');
  if (waveCanvas) {
    const ctx = waveCanvas.getContext('2d');
    let w = 0, h = 0;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);

    const resize = () => {
      const rect = waveCanvas.getBoundingClientRect();
      w = rect.width;
      h = rect.height;
      waveCanvas.width = w * dpr;
      waveCanvas.height = h * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    window.addEventListener('resize', resize);
    resize();

    const layers = [
      { amp: 20, freq: 0.011, speed: 0.00055, color: 'rgba(109, 244, 255, .85)', width: 2.2, base: 0.42 },
      { amp: 14, freq: 0.017, speed: 0.00085, color: 'rgba(24, 217, 242, .4)', width: 1.5, base: 0.6 },
      { amp: 9, freq: 0.025, speed: -0.0007, color: 'rgba(191, 242, 238, .2)', width: 1.1, base: 0.75 },
    ];

    const draw = (t) => {
      ctx.clearRect(0, 0, w, h);
      layers.forEach((layer) => {
        ctx.beginPath();
        for (let x = 0; x <= w; x += 4) {
          const taper = Math.sin((x / w) * Math.PI);
          const y = h * layer.base + Math.sin(x * layer.freq + t * layer.speed) * layer.amp * taper;
          x === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
        }
        ctx.strokeStyle = layer.color;
        ctx.lineWidth = layer.width;
        ctx.stroke();
      });
    };

    if (reduceMotion) {
      draw(0);
    } else {
      const frame = (t) => { draw(t); requestAnimationFrame(frame); };
      requestAnimationFrame(frame);
    }
  }
})();
