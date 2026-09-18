(() => {
  document.documentElement.classList.add('js');
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

  // Download page tide: a live break line running through the oversized
  // wordmark. Pointer movement changes its energy without moving layout.
  const tideCanvas = document.getElementById('download-tide');
  if (tideCanvas) {
    const tideCtx = tideCanvas.getContext('2d');
    const tideDpr = Math.min(window.devicePixelRatio || 1, 2);
    let tideW = 0;
    let tideH = 0;
    let pointerX = 0.56;
    let pointerY = 0.48;
    let energy = 0;

    const tideResize = () => {
      const rect = tideCanvas.getBoundingClientRect();
      tideW = rect.width;
      tideH = rect.height;
      tideCanvas.width = Math.round(tideW * tideDpr);
      tideCanvas.height = Math.round(tideH * tideDpr);
      tideCtx.setTransform(tideDpr, 0, 0, tideDpr, 0, 0);
    };

    const tideScene = tideCanvas.closest('.download-hero');
    if (tideScene && !reduceMotion && window.matchMedia('(hover: hover)').matches) {
      tideScene.addEventListener('pointermove', (event) => {
        const rect = tideScene.getBoundingClientRect();
        pointerX = (event.clientX - rect.left) / rect.width;
        pointerY = (event.clientY - rect.top) / rect.height;
        energy = 1;
      });
      tideScene.addEventListener('pointerleave', () => {
        pointerX = 0.56;
        pointerY = 0.48;
      });
    }

    window.addEventListener('resize', () => { tideResize(); if (reduceMotion) tideDraw(0); });
    tideResize();

    const tideLayers = [
      { offset: -34, amp: 36, speed: .00038, color: 'rgba(117, 239, 243, .19)', width: 1 },
      { offset: -11, amp: 27, speed: .00052, color: 'rgba(116, 185, 206, .34)', width: 1.25 },
      { offset: 0, amp: 42, speed: .00064, color: 'rgba(102, 241, 244, .92)', width: 2.1 },
      { offset: 23, amp: 22, speed: -.00048, color: 'rgba(56, 184, 223, .3)', width: 1.15 },
    ];

    const tideDraw = (time) => {
      tideCtx.clearRect(0, 0, tideW, tideH);
      energy += (0 - energy) * .018;
      const base = tideH * (.78 + (pointerY - .5) * .045);
      const phaseShift = (pointerX - .5) * 2.4;

      tideLayers.forEach((layer, layerIndex) => {
        tideCtx.beginPath();
        for (let x = -8; x <= tideW + 8; x += 5) {
          const normalized = x / Math.max(tideW, 1);
          const focus = Math.sin(normalized * Math.PI);
          const primary = Math.sin(normalized * 8.4 + time * layer.speed + phaseShift);
          const detail = Math.sin(normalized * 20.5 - time * layer.speed * .58) * .28;
          const surge = Math.exp(-Math.pow(normalized - pointerX, 2) / .018) * energy * 24;
          const y = base + layer.offset + (primary + detail) * layer.amp * (.34 + focus * .66) - surge;
          if (x === -8) tideCtx.moveTo(x, y);
          else tideCtx.lineTo(x, y);
        }
        tideCtx.strokeStyle = layer.color;
        tideCtx.lineWidth = layer.width;
        tideCtx.stroke();

        if (layerIndex === 2) {
          tideCtx.lineTo(tideW + 8, tideH);
          tideCtx.lineTo(-8, tideH);
          tideCtx.closePath();
          tideCtx.fillStyle = 'rgba(16, 105, 122, .055)';
          tideCtx.fill();
        }
      });

      const markerCount = tideW < 700 ? 5 : 9;
      for (let i = 0; i < markerCount; i += 1) {
        const progress = (i / markerCount + time * .000018) % 1;
        const x = progress * tideW;
        const y = base + Math.sin(progress * 8.4 + time * .00064 + phaseShift) * 42 * Math.sin(progress * Math.PI);
        tideCtx.fillStyle = i % 3 === 0 ? 'rgba(116, 185, 206, .7)' : 'rgba(112, 241, 244, .72)';
        tideCtx.fillRect(x - 1.5, y - 1.5, 3, 3);
      }
    };

    if (reduceMotion) {
      tideDraw(0);
    } else {
      let tideRaf = null;
      let onScreen = true;
      const tideFrame = (time) => {
        tideDraw(time);
        tideRaf = requestAnimationFrame(tideFrame);
      };
      const updateAnimation = () => {
        if (tideRaf !== null) cancelAnimationFrame(tideRaf);
        tideRaf = null;
        if (!document.hidden && onScreen) tideRaf = requestAnimationFrame(tideFrame);
      };
      document.addEventListener('visibilitychange', updateAnimation);
      if ('IntersectionObserver' in window) {
        new IntersectionObserver(([entry]) => {
          onScreen = entry.isIntersecting;
          updateAnimation();
        }).observe(tideCanvas);
      }
      updateAnimation();
    }
  }

  // Liquid-glass platform marker. It slowly scans the upcoming releases and
  // follows the pointer when the visitor explores the selector.
  const platformSwitch = document.querySelector('[data-platform-switch]');
  if (platformSwitch) {
    let platformIndex = 0;
    let platformTimer = null;
    const setPlatform = (index) => {
      platformIndex = Math.max(0, Math.min(2, index));
      platformSwitch.style.setProperty('--platform-index', platformIndex);
    };
    const startPlatformCycle = () => {
      if (reduceMotion || platformTimer) return;
      platformTimer = window.setInterval(() => setPlatform((platformIndex + 1) % 3), 2600);
    };
    const stopPlatformCycle = () => {
      if (!platformTimer) return;
      window.clearInterval(platformTimer);
      platformTimer = null;
    };

    platformSwitch.addEventListener('pointermove', (event) => {
      const rect = platformSwitch.getBoundingClientRect();
      const mobile = window.matchMedia('(max-width: 760px)').matches;
      const ratio = mobile
        ? (event.clientY - rect.top) / rect.height
        : (event.clientX - rect.left) / rect.width;
      stopPlatformCycle();
      setPlatform(Math.floor(ratio * 3));
    });
    platformSwitch.addEventListener('pointerleave', startPlatformCycle);
    startPlatformCycle();
  }

  const burger = document.getElementById('wb-burger');
  const panel = document.getElementById('wb-nav-panel');
  if (burger && panel) {
    const close = () => {
      panel.classList.remove('open');
      burger.setAttribute('aria-expanded', 'false');
      burger.setAttribute('aria-label', 'Открыть меню');
    };
    burger.addEventListener('click', () => {
      const open = panel.classList.toggle('open');
      burger.setAttribute('aria-expanded', String(open));
      burger.setAttribute('aria-label', open ? 'Закрыть меню' : 'Открыть меню');
      updateGlass();
    });
    panel.querySelectorAll('a').forEach(link => link.addEventListener('click', close));
    document.addEventListener('keydown', event => {
      if (event.key === 'Escape' && panel.classList.contains('open')) { close(); burger.focus(); }
    });
    document.addEventListener('click', event => {
      if (!event.target.closest('.wb-header')) close();
    });
    window.matchMedia('(min-width: 761px)').addEventListener('change', close);
  }

  const nav = document.querySelector('[data-glass-nav]');
  const activeLink = nav?.querySelector('[aria-current="page"]');
  const moveGlass = link => {
    if (!nav || !link || !link.offsetWidth) return;
    nav.style.setProperty('--glass-x', link.offsetLeft + 'px');
    nav.style.setProperty('--glass-width', link.offsetWidth + 'px');
    nav.classList.add('has-glass');
  };
  const updateGlass = () => {
    if (activeLink) moveGlass(activeLink);
    else nav?.classList.remove('has-glass');
  };
  nav?.querySelectorAll('a').forEach(link => {
    link.addEventListener('pointerenter', () => moveGlass(link));
    link.addEventListener('focus', () => moveGlass(link));
  });
  nav?.addEventListener('pointerleave', updateGlass);
  nav?.addEventListener('focusout', event => {
    if (!nav.contains(event.relatedTarget)) updateGlass();
  });
  window.addEventListener('resize', updateGlass);
  document.fonts?.ready.then(updateGlass);
  updateGlass();

})();
