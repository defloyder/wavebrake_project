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

  // Sitewide breakwater backdrop — marketing pages only (.wb-public), never
  // the dashboard or auth screens, which stay calm and functional. Waves
  // ride the jagged rock silhouette and flare into foam; scrolling pumps
  // energy into the scene (harder scroll, harder break), which then decays
  // back to an ambient calm baseline.
  const bwCanvas = document.getElementById('wb-breakwater');
  if (bwCanvas && document.body.classList.contains('wb-public')) {
    const bwCtx = bwCanvas.getContext('2d');
    let bw = 0, bh = 0;
    const bwDpr = Math.min(window.devicePixelRatio || 1, 2);

    const bwResize = () => {
      bw = window.innerWidth;
      bh = window.innerHeight;
      bwCanvas.width = bw * bwDpr;
      bwCanvas.height = bh * bwDpr;
      bwCtx.setTransform(bwDpr, 0, 0, bwDpr, 0, 0);
    };
    window.addEventListener('resize', bwResize);
    bwResize();

    // Jagged rock profile, generated once so the silhouette stays put.
    const rockSeed = Array.from({ length: 28 }, () => 0.45 + Math.random() * 0.55);
    const rockY = (xFrac, baseY, jagH) => {
      const idx = xFrac * (rockSeed.length - 1);
      const i0 = Math.floor(idx);
      const i1 = Math.min(i0 + 1, rockSeed.length - 1);
      const t = idx - i0;
      const v = rockSeed[i0] * (1 - t) + rockSeed[i1] * t;
      return baseY - v * jagH;
    };

    let lastScrollY = window.scrollY;
    let energy = 0.12;
    window.addEventListener('scroll', () => {
      const dy = Math.abs(window.scrollY - lastScrollY);
      lastScrollY = window.scrollY;
      energy = Math.min(1, energy + dy * 0.0035);
    }, { passive: true });

    const foam = [];
    const spawnFoam = (x, y, count) => {
      for (let i = 0; i < count && foam.length < 160; i++) {
        foam.push({
          x: x + (Math.random() - 0.5) * 22,
          y,
          vx: (Math.random() - 0.5) * 0.5,
          vy: -Math.random() * 1.7 - 0.3,
          life: 1,
        });
      }
    };

    const bwDraw = (t) => {
      bwCtx.clearRect(0, 0, bw, bh);

      const atmosphere = bwCtx.createLinearGradient(0, 0, 0, bh);
      atmosphere.addColorStop(0, '#040a12');
      atmosphere.addColorStop(0.62, '#071624');
      atmosphere.addColorStop(1, '#01050a');
      bwCtx.fillStyle = atmosphere;
      bwCtx.fillRect(0, 0, bw, bh);

      const baseY = bh * 0.7;
      const jagH = Math.min(46, bh * 0.055);
      const step = Math.max(4, bw / 90);

      const layers = [
        { amp: 15, freq: 0.011, speed: 0.00058, color: 'rgba(109,244,255,.5)', width: 2 },
        { amp: 10, freq: 0.017, speed: 0.00088, color: 'rgba(24,217,242,.3)', width: 1.4 },
        { amp: 6, freq: 0.025, speed: -0.0007, color: 'rgba(191,242,238,.16)', width: 1 },
      ];

      layers.forEach((layer) => {
        bwCtx.beginPath();
        for (let x = 0; x <= bw; x += step) {
          const rock = rockY(x / bw, baseY, jagH);
          const y = rock - 16 + Math.sin(x * layer.freq + t * layer.speed) * layer.amp * (1 + energy * 1.7);
          x === 0 ? bwCtx.moveTo(x, y) : bwCtx.lineTo(x, y);
        }
        bwCtx.strokeStyle = layer.color;
        bwCtx.lineWidth = layer.width;
        bwCtx.stroke();
      });

      bwCtx.beginPath();
      bwCtx.moveTo(0, bh);
      for (let x = 0; x <= bw; x += step) {
        bwCtx.lineTo(x, rockY(x / bw, baseY, jagH));
      }
      bwCtx.lineTo(bw, bh);
      bwCtx.closePath();
      bwCtx.fillStyle = '#050b12';
      bwCtx.fill();

      bwCtx.beginPath();
      for (let x = 0; x <= bw; x += step) {
        const y = rockY(x / bw, baseY, jagH);
        x === 0 ? bwCtx.moveTo(x, y) : bwCtx.lineTo(x, y);
      }
      bwCtx.strokeStyle = 'rgba(109,244,255,.32)';
      bwCtx.lineWidth = 1.3;
      bwCtx.stroke();

      if (!reduceMotion && Math.random() < 0.12 + energy * 0.55) {
        const x = Math.random() * bw;
        spawnFoam(x, rockY(x / bw, baseY, jagH), 1 + Math.floor(energy * 4));
      }

      bwCtx.fillStyle = 'rgba(232,251,255,.85)';
      for (let i = foam.length - 1; i >= 0; i--) {
        const p = foam[i];
        p.x += p.vx;
        p.y += p.vy;
        p.vy += 0.045;
        p.life -= 0.02;
        if (p.life <= 0) { foam.splice(i, 1); continue; }
        bwCtx.globalAlpha = Math.max(0, p.life);
        bwCtx.beginPath();
        bwCtx.arc(p.x, p.y, 1.6, 0, Math.PI * 2);
        bwCtx.fill();
      }
      bwCtx.globalAlpha = 1;

      energy = Math.max(0.12, energy * 0.965);
    };

    if (reduceMotion) {
      bwDraw(0);
    } else {
      let bwRaf;
      const bwFrame = (t) => { bwDraw(t); bwRaf = requestAnimationFrame(bwFrame); };
      document.addEventListener('visibilitychange', () => {
        if (document.hidden) cancelAnimationFrame(bwRaf);
        else bwRaf = requestAnimationFrame(bwFrame);
      });
      bwRaf = requestAnimationFrame(bwFrame);
    }
  }
})();
