const yearEl = document.getElementById("year");

if (yearEl) {
  yearEl.textContent = new Date().getFullYear();
}

function initTerminalTyping() {
  const terminals = Array.from(document.querySelectorAll(".terminal code"));
  if (!terminals.length) return;

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (reduceMotion) {
    terminals.forEach((code) => {
      code.closest(".terminal")?.classList.add("terminal--typed");
    });
    return;
  }

  const typeCode = (code) => {
    if (code.dataset.typed === "1") return;

    const terminal = code.closest(".terminal");
    const pre = code.closest("pre");
    const text = code.textContent;
    const speed = Number(code.dataset.typeSpeed || 18);

    code.dataset.typed = "1";
    if (pre) pre.style.minHeight = `${pre.offsetHeight}px`;
    code.textContent = "";
    terminal?.classList.add("terminal--typing");

    let index = 0;
    const tick = () => {
      code.textContent = text.slice(0, index);
      index += 1;

      if (index <= text.length) {
        const char = text.charAt(index - 2);
        const delay = char === "\n" ? speed * 7 : speed;
        window.setTimeout(tick, delay);
        return;
      }

      terminal?.classList.remove("terminal--typing");
      terminal?.classList.add("terminal--typed");
    };

    window.setTimeout(tick, 260);
  };

  if (!("IntersectionObserver" in window)) {
    terminals.forEach(typeCode);
    return;
  }

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        const code = entry.target.querySelector("code");
        if (code) typeCode(code);
        observer.unobserve(entry.target);
      });
    },
    { threshold: 0.35 }
  );

  terminals.forEach((code) => {
    observer.observe(code.closest(".terminal") || code);
  });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initTerminalTyping);
} else {
  initTerminalTyping();
}

function initHomePresentation() {
  const presentationPage =
    document.body.classList.contains("home-apple") ||
    document.body.classList.contains("b2b-page");
  if (!presentationPage) return;

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const revealTargets = Array.from(
    document.querySelectorAll(
      ".home-story-card, .access-section, .pricing-section, .b2b-bridge, #services, .faq-section, .seo-section, .site-footer"
      + ", .b2b-capabilities, .b2b-pricing-section, .b2b-process-section, .b2b-seo"
    )
  );

  revealTargets.forEach((target) => target.classList.add("reveal-on-scroll"));

  if (reduceMotion || !("IntersectionObserver" in window)) {
    revealTargets.forEach((target) => target.classList.add("is-visible"));
    return;
  }

  const revealObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-visible");
        revealObserver.unobserve(entry.target);
      });
    },
    { rootMargin: "0px 0px -12% 0px", threshold: 0.12 }
  );

  revealTargets.forEach((target) => revealObserver.observe(target));

}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initHomePresentation);
} else {
  initHomePresentation();
}
