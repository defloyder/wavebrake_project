// The user card. Anything with data-open-user opens it; every action in
// the card posts to UserDetailsController, which answers with the card
// re-rendered from Core (HTML) or a JSON notice/error. The page behind is
// reloaded on close if anything changed, so tables stay truthful.
(() => {
  const card = document.querySelector('[data-user-card]');
  if (!card) return;
  const body = card.querySelector('[data-user-card-body]');
  const errorBox = card.querySelector('[data-user-card-error]');
  const loading = body.innerHTML;
  let dirty = false;
  let currentUser = null;

  const showError = (message) => {
    errorBox.textContent = message || '';
    errorBox.hidden = !message;
    if (message) errorBox.scrollIntoView({ block: 'nearest' });
  };

  const handleFailure = (error) => {
    if (error.status === 401) { window.location.href = '/login'; return; }
    showError(error.message);
  };

  const render = (html) => {
    body.innerHTML = html;
    showError('');
  };

  const open = async (userId) => {
    currentUser = userId;
    showError('');
    body.innerHTML = loading;
    window.admModal.open('adm-user-card');
    try {
      render(await window.admRequest(`/users/${encodeURIComponent(userId)}/details`, { method: 'GET' }));
    } catch (error) {
      body.innerHTML = '';
      handleFailure(error);
    }
  };

  // Open from any row/feed item, but not when the click hit a control inside it.
  document.addEventListener('click', (event) => {
    const opener = event.target.closest('[data-open-user]');
    if (!opener || card.contains(opener)) return;
    if (event.target.closest('a, button, input, select, textarea, label') && event.target.closest('a, button, input, select, textarea, label') !== opener) return;
    open(opener.dataset.openUser);
  });

  card.addEventListener('adm:modal-closed', () => {
    currentUser = null;
    if (dirty) window.location.reload();
  });

  const run = async (trigger, url, init) => {
    if (trigger.dataset.confirm && !confirm(trigger.dataset.confirm)) return;
    const buttons = card.querySelectorAll('button');
    buttons.forEach((b) => { b.disabled = true; });
    trigger.classList.add('is-busy');
    try {
      const result = await window.admRequest(url, init);
      dirty = true;
      if (typeof result === 'string') {
        render(result);
        return;
      }
      if (result.removed) {
        window.admModal.close(card);
        return;
      }
      const notice = card.querySelector('[data-card-notice]');
      if (notice && result.message) { notice.textContent = result.message; notice.hidden = false; }
      showError('');
    } catch (error) {
      handleFailure(error);
    } finally {
      buttons.forEach((b) => { b.disabled = false; });
      trigger.classList.remove('is-busy');
    }
  };

  card.addEventListener('click', async (event) => {
    const toggle = event.target.closest('[data-toggle-panel]');
    if (toggle) {
      const panel = card.querySelector(`[data-panel="${toggle.dataset.togglePanel}"]`);
      if (panel) {
        panel.hidden = !panel.hidden;
        if (!panel.hidden) panel.querySelector('input:not([type=hidden]), select')?.focus();
      }
      return;
    }

    const action = event.target.closest('[data-action]');
    if (action) {
      run(action, action.dataset.action, {});
      return;
    }

    const copy = event.target.closest('[data-copy]');
    if (copy) {
      try {
        await navigator.clipboard.writeText(copy.dataset.copy);
        copy.classList.add('is-done');
        setTimeout(() => copy.classList.remove('is-done'), 1200);
      } catch { showError('Не удалось скопировать — браузер запретил доступ к буферу обмена.'); }
      return;
    }

    const qr = event.target.closest('[data-qr]');
    if (qr) {
      const target = card.querySelector('[data-qr-target]');
      if (!target) return;
      if (!target.hidden) { target.hidden = true; return; }
      try {
        await loadQrLibrary();
        target.innerHTML = '';
        const canvas = document.createElement('canvas');
        await window.QRCode.toCanvas(canvas, qr.dataset.qr, { width: 200, margin: 1 });
        target.appendChild(canvas);
        target.hidden = false;
      } catch { showError('Не удалось построить QR-код.'); }
    }
  });

  card.addEventListener('submit', (event) => {
    const form = event.target.closest('form[data-card-form]');
    if (!form) return;
    event.preventDefault();
    const trigger = form.querySelector('[type="submit"]') || form;
    if (form.dataset.confirm) trigger.dataset.confirm = form.dataset.confirm;
    run(trigger, form.action, { body: new FormData(form) });
  });

  // qrcode is only needed when an operator asks for a QR, so it's fetched lazily.
  let qrPromise = null;
  function loadQrLibrary() {
    if (window.QRCode) return Promise.resolve();
    qrPromise ??= new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = 'https://cdn.jsdelivr.net/npm/qrcode@1.5.3/build/qrcode.min.js';
      script.onload = resolve;
      script.onerror = () => { qrPromise = null; reject(new Error('qr')); };
      document.head.appendChild(script);
    });
    return qrPromise;
  }

  // /users?user=<id> opens the card directly (links from elsewhere).
  const deepLink = new URLSearchParams(window.location.search).get('user');
  if (deepLink) open(deepLink);
})();
