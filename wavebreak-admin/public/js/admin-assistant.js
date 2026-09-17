(() => {
  const launcher = document.getElementById('adm-assistant-launcher');
  const panel = document.getElementById('adm-assistant');
  const close = document.getElementById('adm-assistant-close');
  const form = document.getElementById('adm-assistant-form');
  const input = document.getElementById('adm-assistant-input');
  const messages = document.getElementById('adm-assistant-messages');
  const suggestions = document.getElementById('adm-assistant-suggestions');
  if (!launcher || !panel || !form || !input || !messages || !suggestions) return;

  const csrf = document.querySelector('meta[name="csrf-token"]')?.content || '';
  let busy = false;

  function setOpen(open) {
    panel.classList.toggle('open', open);
    panel.setAttribute('aria-hidden', String(!open));
    launcher.setAttribute('aria-expanded', String(open));
    if (open) {
      launcher.classList.remove('has-update');
      setTimeout(() => input.focus(), 120);
    }
  }

  function addMessage(role, payload) {
    const item = document.createElement('div');
    item.className = `adm-assistant-message is-${role}${payload.level ? ` is-${payload.level}` : ''}`;
    const body = document.createElement('p');
    body.textContent = payload.text || payload.error || 'Нет ответа.';
    item.appendChild(body);

    if (Array.isArray(payload.facts)) {
      const facts = document.createElement('div');
      facts.className = 'adm-assistant-facts';
      payload.facts.forEach((fact) => {
        const cell = document.createElement('span');
        const label = document.createElement('small');
        const value = document.createElement('strong');
        label.textContent = fact.label;
        value.textContent = fact.value;
        cell.append(label, value);
        facts.appendChild(cell);
      });
      item.appendChild(facts);
    }

    if (payload.link?.href) {
      const link = document.createElement('a');
      link.href = payload.link.href;
      link.textContent = payload.link.label || 'Открыть';
      item.appendChild(link);
    }

    if (payload.confirmation?.token) {
      const box = document.createElement('div');
      box.className = 'adm-assistant-confirm';
      const label = document.createElement('span');
      label.textContent = payload.confirmation.label;
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = 'Подтвердить';
      button.addEventListener('click', () => confirmAction(payload.confirmation.token, button));
      box.append(label, button);
      item.appendChild(box);
    }

    messages.appendChild(item);
    messages.scrollTop = messages.scrollHeight;
    renderSuggestions(payload.suggestions || []);
    if (!panel.classList.contains('open') && role === 'assistant') launcher.classList.add('has-update');
  }

  function renderSuggestions(items) {
    suggestions.replaceChildren();
    items.forEach((label) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = label;
      button.addEventListener('click', () => send(label));
      suggestions.appendChild(button);
    });
  }

  async function request(url, payload) {
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'X-CSRF-TOKEN': csrf },
      body: JSON.stringify(payload),
    });
    const json = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(json.error || (response.status === 401 ? 'Сессия истекла. Обновите страницу.' : 'Запрос не выполнен.'));
    return json;
  }

  async function send(text) {
    const value = String(text || '').trim();
    if (!value || busy) return;
    busy = true;
    input.value = '';
    addMessage('user', { text: value });
    const pending = document.createElement('div');
    pending.className = 'adm-assistant-typing';
    pending.innerHTML = '<i></i><i></i><i></i>';
    messages.appendChild(pending);
    messages.scrollTop = messages.scrollHeight;
    try {
      const reply = await request('/assistant/message', { message: value });
      pending.remove();
      addMessage('assistant', reply);
    } catch (error) {
      pending.remove();
      addMessage('assistant', { text: error.message, level: 'error' });
    } finally {
      busy = false;
      input.focus();
    }
  }

  async function confirmAction(token, button) {
    if (busy) return;
    busy = true;
    button.disabled = true;
    button.textContent = 'Выполняю...';
    try {
      const reply = await request('/assistant/confirm', { token });
      button.closest('.adm-assistant-confirm')?.remove();
      addMessage('assistant', reply);
    } catch (error) {
      button.textContent = 'Повторить';
      button.disabled = false;
      addMessage('assistant', { text: error.message, level: 'error' });
    } finally {
      busy = false;
    }
  }

  launcher.addEventListener('click', () => setOpen(!panel.classList.contains('open')));
  close?.addEventListener('click', () => setOpen(false));
  form.addEventListener('submit', (event) => { event.preventDefault(); send(input.value); });
  input.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' && !event.shiftKey) { event.preventDefault(); form.requestSubmit(); }
  });

  addMessage('assistant', {
    text: 'Здравствуйте. Я покажу состояние системы, найду пользователя или подписку и помогу выполнить действие. Напишите «найди», «создай подписку» или «приостанови». Изменения выполняются только после подтверждения.',
    suggestions: ['Сводка', 'Найди', 'Создай подписку', 'Приостанови'],
  });
})();
