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

  // Hero parallax: the brand square tilts gently toward the pointer.
  // Pure CSS custom properties, no layout thrash.
  if (!reduceMotion) {
    const scene = document.querySelector('.art-square-scene');
    if (scene && window.matchMedia('(hover: hover)').matches) {
      let raf = null;
      scene.addEventListener('pointermove', (event) => {
        const rect = scene.getBoundingClientRect();
        const x = (event.clientX - rect.left) / rect.width - 0.5;
        const y = (event.clientY - rect.top) / rect.height - 0.5;
        if (raf) cancelAnimationFrame(raf);
        raf = requestAnimationFrame(() => {
          scene.style.setProperty('--tiltX', `${(-y * 10).toFixed(2)}deg`);
          scene.style.setProperty('--tiltY', `${(x * 12).toFixed(2)}deg`);
          scene.style.setProperty('--glowX', `${(50 + x * 30).toFixed(1)}%`);
          scene.style.setProperty('--glowY', `${(50 + y * 30).toFixed(1)}%`);
        });
      });
      scene.addEventListener('pointerleave', () => {
        if (raf) cancelAnimationFrame(raf);
        scene.style.setProperty('--tiltX', '0deg');
        scene.style.setProperty('--tiltY', '0deg');
        scene.style.setProperty('--glowX', '50%');
        scene.style.setProperty('--glowY', '50%');
      });
    }
  }
})();
