function profileShowLoader(title, detail) {
  const modal = document.getElementById("profile-loader-modal");
  const titleEl = document.getElementById("profile-loader-title");
  const detailEl = document.getElementById("profile-loader-detail");
  if (!modal) return;

  if (titleEl) titleEl.textContent = title || "Загружаем";
  if (detailEl) detailEl.textContent = detail || "Пожалуйста, подождите несколько секунд.";
  modal.hidden = false;
  document.body.classList.add("profile-action-loading");
}

function profileHideLoader() {
  const modal = document.getElementById("profile-loader-modal");
  if (!modal) return;

  modal.hidden = true;
  document.body.classList.remove("profile-action-loading");
}

window.profileShowLoader = profileShowLoader;
window.profileHideLoader = profileHideLoader;

function releaseInitialProfileLoader() {
  setTimeout(() => {
    document.body.classList.remove("is-loading");
    profileHideLoader();
  }, 450);
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", releaseInitialProfileLoader, { once: true });
} else {
  releaseInitialProfileLoader();
}

window.addEventListener("load", releaseInitialProfileLoader, { once: true });
setTimeout(releaseInitialProfileLoader, 2400);

document.addEventListener("submit", function(event) {
  const form = event.target.closest("form");
  if (!form || form.dataset.noLoader === "1") return;

  setTimeout(function() {
    if (event.defaultPrevented) return;
    const method = (form.getAttribute("method") || "GET").toUpperCase();
    profileShowLoader(
      form.dataset.loaderTitle || (method === "GET" ? "Загружаем данные" : "Выполняем действие"),
      form.dataset.loaderDetail || "Запрос уже ушёл на сервер."
    );
  }, 0);
});

document.addEventListener("click", function(event) {
  const link = event.target.closest("a[href]");
  if (!link || link.dataset.noLoader === "1") return;
  if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
  if (link.target && link.target !== "_self") return;
  if (link.hasAttribute("download")) return;

  const href = link.getAttribute("href") || "";
  if (!href || href.startsWith("#") || href.startsWith("javascript:") || href.startsWith("mailto:") || href.startsWith("tel:")) return;

  const url = new URL(link.href, window.location.href);
  if (url.origin !== window.location.origin) return;

  profileShowLoader(
    link.dataset.loaderTitle || "Открываем страницу",
    link.dataset.loaderDetail || "Готовим данные кабинета."
  );
});

const planData = {
  1:  { name: "1 месяц",  price: "169 ₽",  days: "30 дней" },
  3:  { name: "3 месяца", price: "449 ₽",  days: "90 дней" },
  12: { name: "1 год",    price: "1490 ₽", days: "365 дней" },
};

function openSubscribeModal() {
  document.getElementById("subscribeModal").classList.add("active");
  document.body.style.overflow = "hidden";
}

function closeSubscribeModal(e) {
  if (e && e.target !== document.getElementById("subscribeModal")) return;
  document.getElementById("subscribeModal").classList.remove("active");
  document.body.style.overflow = "";
  goToStep1();
}

function goToStep2() {
  const selected = document.querySelector('input[name="modal_plan"]:checked');
  if (!selected) return;
  const plan = planData[selected.value];
  document.getElementById("summaryPlan").textContent  = plan.name;
  document.getElementById("summaryPrice").textContent = plan.price;
  document.getElementById("summaryDays").textContent  = plan.days;
  document.getElementById("formPlanId").value = selected.value;
  document.getElementById("modalStep1").classList.add("hidden");
  document.getElementById("modalStep2").classList.remove("hidden");
}

function goToStep1() {
  document.getElementById("modalStep2").classList.add("hidden");
  document.getElementById("modalStep1").classList.remove("hidden");
}

// Highlight selected plan card
document.addEventListener("change", function(e) {
  if (e.target.name === "modal_plan") {
    document.querySelectorAll(".modal-plan-card").forEach(c => c.style.borderColor = "");
    e.target.closest(".modal-plan-card").style.borderColor = "rgba(107,147,192,.8)";
  }
});

function profileEscapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function detectProfilePlatform() {
  const ua = navigator.userAgent || "";
  const platform = navigator.userAgentData?.platform || navigator.platform || "";
  const touchMac = /Mac/i.test(platform) && navigator.maxTouchPoints > 1;

  if (/Android/i.test(ua)) {
    return { key: "android", label: "Android", action: "Открыть мастер", hint: "Откроем мастер подключения и предложим импорт через приложение." };
  }
  if (/iPhone|iPad|iPod/i.test(ua) || touchMac) {
    return { key: "ios", label: "iPhone или iPad", action: "Показать QR", hint: "На iOS удобнее открыть QR-код или мастер импорта." };
  }
  if (/Win/i.test(platform) || /Windows/i.test(ua)) {
    return { key: "windows", label: "Windows", action: "Открыть мастер", hint: "Можно скачать клиент Windows или открыть мастер подключения." };
  }
  if (/Mac/i.test(platform) || /Mac OS X/i.test(ua)) {
    return { key: "macos", label: "macOS", action: "Открыть мастер", hint: "Мастер подскажет совместимый клиент и ручной импорт." };
  }
  if (/Linux/i.test(platform) || /Linux/i.test(ua)) {
    return { key: "linux", label: "Linux", action: "Копировать ссылку", hint: "Для Linux чаще всего удобна ручная настройка по ссылке." };
  }

  return { key: "unknown", label: "Неизвестная платформа", action: "Открыть мастер", hint: "Если мастер не откроет клиент, используйте QR-код или ссылку." };
}

function updateConnectDeviceHint() {
  const title = document.getElementById("connectDeviceTitle");
  const text = document.getElementById("connectDeviceText");
  const action = document.getElementById("connectDeviceAction");
  const detected = detectProfilePlatform();
  if (!title || !text || !action) return;

  title.textContent = detected.label;
  text.textContent = detected.hint;
  action.textContent = detected.action;
  action.dataset.platform = detected.key;

  if (detected.key === "ios") {
    action.onclick = function() {
      const qrButton = document.querySelector(".connect-panel__actions .connect-action:not(.connect-action--primary)");
      if (qrButton) qrButton.click();
    };
  } else if (detected.key === "linux") {
    action.onclick = function() {
      const copyButton = document.querySelector(".connect-panel__actions [data-copy]");
      if (copyButton) copyButton.click();
    };
  }
}

function profileFmtBytes(bytes) {
  const n = Number(bytes);
  if (!Number.isFinite(n) || n <= 0) return "0 Б";
  const units = ["Б", "КБ", "МБ", "ГБ", "ТБ"];
  let value = n;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value >= 10 || unit === 0 ? value.toFixed(0) : value.toFixed(1)} ${units[unit]}`;
}

function profileFormatLastSeen(value) {
  if (!value) return "ещё не было";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return date.toLocaleString("ru-RU", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" });
}

function profilePlatformLabel(value) {
  const platform = String(value || "unknown").toLowerCase();
  if (platform.includes("win")) return "Windows";
  if (platform.includes("ios") || platform.includes("iphone") || platform.includes("ipad")) return "iOS";
  if (platform.includes("android")) return "Android";
  if (platform.includes("mac")) return "macOS";
  if (platform.includes("linux")) return "Linux";
  return value || "unknown";
}

function renderProfileDevices(devices) {
  const summary = document.getElementById("profileDevicesSummary");
  const list = document.getElementById("profileDevicesList");
  const more = document.getElementById("profileDevicesMore");
  const root = document.getElementById("profileDevices");
  if (!summary || !list) return;

  const items = Array.isArray(devices) ? devices : [];
  const activeCount = items.filter(device => !!device.is_active).length;
  const expanded = root?.dataset.expanded === "1";
  const visibleLimit = 4;
  const visibleItems = expanded ? items : items.slice(0, visibleLimit);
  summary.textContent = items.length
    ? `${activeCount} активн. из ${items.length}. ${expanded || items.length <= visibleLimit ? "Показан весь список." : `Показаны последние ${visibleItems.length}.`}`
    : "Устройств пока нет. Подключите первое устройство через мастер или QR-код.";

  if (!items.length) {
    list.innerHTML = "";
    if (more) more.hidden = true;
    return;
  }

  const detected = detectProfilePlatform();
  list.innerHTML = visibleItems.map(device => {
    const platform = profilePlatformLabel(device.platform);
    const isSamePlatform = detected.key !== "unknown" && platform.toLowerCase().includes(detected.key.replace("macos", "mac"));
    const status = device.is_active ? "Активно" : "Отключено";
    return `
      <article class="profile-device-row profile-device-card ${device.is_active ? "is-active" : "is-disabled"}">
        <div class="profile-device-row__main">
          <strong>${profileEscapeHtml(device.display_name || "Устройство")}</strong>
          <span>${profileEscapeHtml(platform)}${device.app_version ? ` · v${profileEscapeHtml(device.app_version)}` : ""}${isSamePlatform ? " · это устройство" : ""}</span>
        </div>
        <span class="profile-device-row__seen">${profileEscapeHtml(profileFormatLastSeen(device.last_seen))}</span>
        <span class="profile-device-row__traffic">${profileEscapeHtml(profileFmtBytes(device.traffic_bytes))}</span>
        <span class="profile-device-row__status">${status}</span>
      </article>
    `;
  }).join("");

  if (more) {
    more.hidden = items.length <= visibleLimit;
    more.textContent = expanded ? "Свернуть список" : `Показать все ${items.length}`;
  }
}

function toggleProfileDevicesList() {
  const root = document.getElementById("profileDevices");
  if (!root || !window.profileDevicesCache) return;

  root.dataset.expanded = root.dataset.expanded === "1" ? "0" : "1";
  renderProfileDevices(window.profileDevicesCache);
}

function loadProfileDevices(force) {
  const root = document.getElementById("profileDevices");
  const summary = document.getElementById("profileDevicesSummary");
  if (!root || (!force && root.dataset.loaded === "1")) return;

  const url = root.dataset.devicesUrl;
  if (!url) return;

  root.dataset.loaded = "1";
  root.dataset.expanded = "0";
  if (summary) summary.textContent = "Загружаем список из Core...";

  fetch(url, { headers: { Accept: "application/json" } })
    .then(response => response.json().then(data => ({ ok: response.ok, data })))
    .then(({ ok, data }) => {
      if (!ok || !data.ok) throw new Error(data.error || "Core не вернул устройства");
      window.profileDevicesCache = data.devices || [];
      renderProfileDevices(data.devices || []);
    })
    .catch(error => {
      if (window.console && error?.message) console.warn("Profile devices unavailable:", error.message);
      if (summary) summary.textContent = "Не удалось загрузить устройства. Подключение всё равно доступно выше.";
      const list = document.getElementById("profileDevicesList");
      if (list) list.innerHTML = "";
    });
}

window.loadProfileDevices = loadProfileDevices;
window.toggleProfileDevicesList = toggleProfileDevicesList;

document.addEventListener("DOMContentLoaded", function() {
  updateConnectDeviceHint();
  loadProfileDevices(false);
});
