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

    // Jagged breakwater wall, spanning the full height. Two independent
    // seed arrays give the left (storm-facing) and right (harbor-facing)
    // edges different irregularity so it reads as a pile of rock, not a
    // clean bar. wallXAt returns the wall's centerline at a given height;
    // the wave split uses a single representative x since the wall barely
    // drifts across the band the waves occupy.
    const wallSeed = Array.from({ length: 22 }, () => (Math.random() - 0.5) * 2);
    const wallLeftSeed = Array.from({ length: 22 }, () => Math.random());
    const wallRightSeed = Array.from({ length: 22 }, () => Math.random());
    const sampleSeed = (seed, yFrac) => {
      const idx = yFrac * (seed.length - 1);
      const i0 = Math.floor(idx);
      const i1 = Math.min(i0 + 1, seed.length - 1);
      const f = idx - i0;
      return seed[i0] * (1 - f) + seed[i1] * f;
    };
    const wallXAt = (yFrac) => bw * (0.42 + yFrac * 0.07) + sampleSeed(wallSeed, yFrac) * 16;

    let lastScrollY = window.scrollY;
    let stormEnergy = 0.22;
    window.addEventListener('scroll', () => {
      const dy = Math.abs(window.scrollY - lastScrollY);
      lastScrollY = window.scrollY;
      stormEnergy = Math.min(1, stormEnergy + dy * 0.0035);
    }, { passive: true });

    const foam = [];
    const spawnFoam = (x, y, count) => {
      for (let i = 0; i < count && foam.length < 160; i++) {
        foam.push({
          x: x - Math.random() * 14,
          y: y + (Math.random() - 0.5) * 26,
          vx: -(Math.random() * 1.1 + 0.2),
          vy: -Math.random() * 1.6 - 0.3,
          life: 1,
        });
      }
    };

    const bwDraw = (t) => {
      bwCtx.clearRect(0, 0, bw, bh);

      const atmosphere = bwCtx.createLinearGradient(0, 0, 0, bh);
      atmosphere.addColorStop(0, '#050d16');
      atmosphere.addColorStop(0.55, '#0a2233');
      atmosphere.addColorStop(1, '#010305');
      bwCtx.fillStyle = atmosphere;
      bwCtx.fillRect(0, 0, bw, bh);

      const baseY = bh * 0.5;
      const splitX = wallXAt(baseY / bh);
      const step = Math.max(4, bw / 110);

      // Storm side: chaotic, multi-frequency, amplitude driven by scroll energy.
      const stormLayers = [
        { amp: 30, freq: 0.015, speed: 0.001, jitter: 9, color: 'rgba(150,238,255,.9)', width: 2.6 },
        { amp: 20, freq: 0.023, speed: 0.0015, jitter: 7, color: 'rgba(24,217,242,.6)', width: 1.9 },
        { amp: 13, freq: 0.033, speed: -0.0012, jitter: 6, color: 'rgba(191,242,238,.35)', width: 1.3 },
      ];
      stormLayers.forEach((layer) => {
        bwCtx.beginPath();
        let started = false;
        for (let x = 0; x <= splitX; x += step) {
          const chop = Math.sin(x * 0.045 + t * 0.0026) * layer.jitter * (0.5 + stormEnergy);
          const y = baseY + Math.sin(x * layer.freq + t * layer.speed) * layer.amp * (0.7 + stormEnergy * 1.6) + chop;
          if (!started) { bwCtx.moveTo(x, y); started = true; } else bwCtx.lineTo(x, y);
        }
        bwCtx.strokeStyle = layer.color;
        bwCtx.lineWidth = layer.width;
        bwCtx.stroke();
      });

      // Harbor side: near-flat, barely reacts to scroll — the whole point.
      const calmLayers = [
        { amp: 4, freq: 0.008, speed: 0.00035, color: 'rgba(150,238,255,.5)', width: 1.6 },
        { amp: 2.4, freq: 0.013, speed: 0.0005, color: 'rgba(24,217,242,.28)', width: 1 },
      ];
      calmLayers.forEach((layer) => {
        bwCtx.beginPath();
        let started = false;
        for (let x = splitX; x <= bw; x += step) {
          const y = baseY + Math.sin(x * layer.freq + t * layer.speed) * layer.amp * (1 + stormEnergy * 0.12);
          if (!started) { bwCtx.moveTo(x, y); started = true; } else bwCtx.lineTo(x, y);
        }
        bwCtx.strokeStyle = layer.color;
        bwCtx.lineWidth = layer.width;
        bwCtx.stroke();
      });

      // The wall itself, drawn over the wave endpoints so both sides look
      // like they terminate against solid rock. Bright, saturated fill —
      // it needs to read as a solid mass at a glance, not blend into the
      // atmosphere like the water does.
      const rows = 26;
      const wallLeftPts = [];
      const wallRightPts = [];
      for (let i = 0; i <= rows; i++) {
        const yFrac = i / rows;
        const y = yFrac * bh;
        wallLeftPts.push([wallXAt(yFrac) - (16 + sampleSeed(wallLeftSeed, yFrac) * 22), y]);
        wallRightPts.push([wallXAt(yFrac) + (16 + sampleSeed(wallRightSeed, yFrac) * 22), y]);
      }

      bwCtx.beginPath();
      wallLeftPts.forEach(([x, y], i) => (i === 0 ? bwCtx.moveTo(x, y) : bwCtx.lineTo(x, y)));
      for (let i = wallRightPts.length - 1; i >= 0; i--) bwCtx.lineTo(wallRightPts[i][0], wallRightPts[i][1]);
      bwCtx.closePath();
      bwCtx.fillStyle = '#5c7d95';
      bwCtx.fill();

      // Banding within the rock, darker than the flat fill — reads as
      // texture instead of a smooth blob.
      for (let i = 0; i < rows; i += 2) {
        const a = wallLeftPts[i];
        const b = wallLeftPts[Math.min(i + 1, rows)];
        const c = wallRightPts[rows - Math.min(i + 1, rows)];
        const d = wallRightPts[rows - i];
        bwCtx.beginPath();
        bwCtx.moveTo(a[0], a[1]);
        bwCtx.lineTo(b[0], b[1]);
        bwCtx.lineTo(c[0], c[1]);
        bwCtx.lineTo(d[0], d[1]);
        bwCtx.closePath();
        bwCtx.fillStyle = i % 4 === 0 ? 'rgba(15,30,42,.35)' : 'rgba(255,255,255,.05)';
        bwCtx.fill();
      }

      // Bright rim on the storm-facing edge (spray-lit), a dim one on the
      // harbor-facing edge — the asymmetry itself sells which side is which.
      bwCtx.shadowColor = 'rgba(150,238,255,.7)';
      bwCtx.shadowBlur = 14;
      bwCtx.strokeStyle = 'rgba(190,248,255,.9)';
      bwCtx.lineWidth = 2;
      bwCtx.beginPath();
      wallLeftPts.forEach(([x, y], i) => (i === 0 ? bwCtx.moveTo(x, y) : bwCtx.lineTo(x, y)));
      bwCtx.stroke();
      bwCtx.shadowBlur = 0;

      bwCtx.strokeStyle = 'rgba(120,190,210,.3)';
      bwCtx.lineWidth = 1.2;
      bwCtx.beginPath();
      wallRightPts.forEach(([x, y], i) => (i === 0 ? bwCtx.moveTo(x, y) : bwCtx.lineTo(x, y)));
      bwCtx.stroke();

      if (!reduceMotion && Math.random() < 0.2 + stormEnergy * 0.6) {
        const yFrac = Math.random();
        const half = 16 + sampleSeed(wallLeftSeed, yFrac) * 22;
        spawnFoam(wallXAt(yFrac) - half, yFrac * bh, 1 + Math.floor(stormEnergy * 4));
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

      stormEnergy = Math.max(0.22, stormEnergy * 0.965);
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
