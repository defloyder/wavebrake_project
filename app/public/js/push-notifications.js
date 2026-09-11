/**
 * Auralith Web Push Notifications
 */

(function () {
    'use strict';

    var deferredInstallPrompt = null;

    function $(id) {
        return document.getElementById(id);
    }

    function urlBase64ToUint8Array(base64String) {
        var padding = '='.repeat((4 - (base64String.length % 4)) % 4);
        var base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
        var raw = window.atob(base64);
        var output = new Uint8Array(raw.length);

        for (var i = 0; i < raw.length; ++i) {
            output[i] = raw.charCodeAt(i);
        }

        return output;
    }

    function arrayBufferToBase64Url(buffer) {
        var bytes = new Uint8Array(buffer);
        var binary = '';

        for (var i = 0; i < bytes.byteLength; i++) {
            binary += String.fromCharCode(bytes[i]);
        }

        return window.btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    }

    function isIos() {
        return /iphone|ipad|ipod/i.test(navigator.userAgent);
    }

    function isStandalone() {
        return window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;
    }

    function setPushUi(state, details) {
        var toggle = $('push-toggle-btn');
        var stateBox = $('push-summary-state');
        var stateText = $('push-status-text');
        var note = $('push-status-note');

        if (!toggle || !stateBox || !stateText || !note) return;

        stateBox.classList.remove('is-on', 'is-blocked');
        toggle.disabled = false;
        toggle.hidden = false;

        if (state === 'on') {
            stateBox.classList.add('is-on');
            stateText.textContent = 'Включены';
            note.textContent = 'Этот браузер подписан на уведомления Auralith.';
            toggle.textContent = 'Выключить';
            toggle.classList.add('push-toggle--on');
            return;
        }

        toggle.classList.remove('push-toggle--on');

        if (state === 'blocked') {
            stateBox.classList.add('is-blocked');
            stateText.textContent = 'Запрещены в браузере';
            note.textContent = 'Разрешите уведомления в настройках браузера или системы, затем обновите страницу.';
            toggle.textContent = 'Недоступно';
            toggle.disabled = true;
            return;
        }

        if (state === 'unsupported') {
            stateBox.classList.add('is-blocked');
            stateText.textContent = 'Не поддерживаются';
            note.textContent = details || 'Этот браузер не умеет получать Web Push уведомления.';
            toggle.textContent = 'Недоступно';
            toggle.disabled = true;
            return;
        }

        stateText.textContent = 'Не включены';
        note.textContent = details || 'После включения уведомления будут приходить даже при закрытой вкладке.';
        toggle.textContent = 'Включить';
    }

    function updateInstallUi() {
        var installBtn = $('install-app-btn');
        var overviewInstallBtn = $('overview-install-app-btn');
        var note = $('pwa-install-note');
        var overviewNote = $('overview-pwa-install-note');

        if (!installBtn && !overviewInstallBtn) return;

        function setInstallHidden(hidden) {
            if (installBtn) installBtn.hidden = hidden;
            if (overviewInstallBtn) overviewInstallBtn.disabled = hidden;
        }

        function setInstallNote(text) {
            if (note) note.textContent = text;
            if (overviewNote) overviewNote.textContent = text;
        }

        if (isStandalone()) {
            setInstallNote('Auralith открыт как приложение.');
            setInstallHidden(true);
            return;
        }

        if (deferredInstallPrompt) {
            setInstallNote('Можно установить Auralith как приложение.');
            setInstallHidden(false);
            return;
        }

        setInstallHidden(true);

        if (isIos()) {
            setInstallNote('Safari: «Поделиться» → «На экран Домой».');
        } else {
            setInstallNote('Добавьте Auralith как приложение.');
        }
    }

    async function registerServiceWorker() {
        if (!('serviceWorker' in navigator)) return null;

        try {
            return await navigator.serviceWorker.register('/sw.js?v=4', { scope: '/' });
        } catch (e) {
            console.warn('[Push] Service worker registration failed:', e);
            return null;
        }
    }

    async function saveSubscription(subscription) {
        var key = subscription.getKey('p256dh');
        var auth = subscription.getKey('auth');
        var supportedEncodings = window.PushManager && PushManager.supportedContentEncodings
            ? PushManager.supportedContentEncodings
            : ['aes128gcm'];

        var response = await fetch(window.PUSH_SUBSCRIBE_URL, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'X-CSRF-TOKEN': window.CSRF_TOKEN,
            },
            credentials: 'same-origin',
            body: JSON.stringify({
                endpoint: subscription.endpoint,
                p256dh: arrayBufferToBase64Url(key),
                auth: arrayBufferToBase64Url(auth),
                content_encoding: supportedEncodings[0] || 'aes128gcm',
            }),
        });

        return response.ok;
    }

    async function removeSubscription(subscription) {
        await fetch(window.PUSH_UNSUBSCRIBE_URL, {
            method: 'DELETE',
            headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'X-CSRF-TOKEN': window.CSRF_TOKEN,
            },
            credentials: 'same-origin',
            body: JSON.stringify({ endpoint: subscription.endpoint }),
        });
    }

    async function subscribe(registration) {
        var applicationServerKey = urlBase64ToUint8Array(window.PUSH_VAPID_PUBLIC_KEY);

        try {
            var subscription = await registration.pushManager.subscribe({
                userVisibleOnly: true,
                applicationServerKey: applicationServerKey,
            });

            var saved = await saveSubscription(subscription);
            return saved ? subscription : null;
        } catch (e) {
            console.warn('[Push] Subscribe failed:', e);
            return null;
        }
    }

    async function refreshPushState() {
        if (!('Notification' in window) || !('serviceWorker' in navigator) || !('PushManager' in window)) {
            setPushUi('unsupported', isIos()
                ? 'На iPhone уведомления доступны в web app, добавленном на экран Домой.'
                : 'Этот браузер не поддерживает Web Push.');
            return null;
        }

        if (!window.PUSH_VAPID_PUBLIC_KEY) {
            setPushUi('unsupported', 'Уведомления временно недоступны: ключи VAPID не настроены.');
            return null;
        }

        if (Notification.permission === 'denied') {
            setPushUi('blocked');
            return null;
        }

        var registration = await registerServiceWorker();
        if (!registration) {
            setPushUi('unsupported', 'Не удалось зарегистрировать service worker. Обновите страницу и попробуйте снова.');
            return null;
        }

        var subscription = await registration.pushManager.getSubscription();

        if (subscription) {
            await saveSubscription(subscription);
            setPushUi('on');
            return subscription;
        }

        setPushUi('off');
        return null;
    }

    async function requestAndSubscribe() {
        if (!('Notification' in window)) {
            setPushUi('unsupported');
            return;
        }

        var permission = await Notification.requestPermission();
        if (permission === 'denied') {
            setPushUi('blocked');
            return;
        }

        if (permission !== 'granted') {
            setPushUi('off', 'Разрешение не выдано. Нажмите «Включить», когда будете готовы.');
            return;
        }

        var registration = await registerServiceWorker();
        if (!registration) {
            setPushUi('unsupported', 'Не удалось подготовить браузер к получению уведомлений.');
            return;
        }

        var subscription = await subscribe(registration);
        setPushUi(subscription ? 'on' : 'off', subscription ? null : 'Подписка не сохранилась. Обновите страницу и попробуйте снова.');
    }

    window.togglePushNotifications = async function () {
        if (!('serviceWorker' in navigator)) {
            setPushUi('unsupported');
            return;
        }

        if (window.profileShowLoader) {
            window.profileShowLoader('Настраиваем уведомления', 'Обновляем подписку браузера.');
        }

        try {
            var registration = await navigator.serviceWorker.ready;
            var subscription = await registration.pushManager.getSubscription();

            if (subscription) {
                await removeSubscription(subscription);
                await subscription.unsubscribe();
                setPushUi('off');
                return;
            }

            await requestAndSubscribe();
        } finally {
            if (window.profileHideLoader) {
                window.profileHideLoader();
            }
        }
    };

    window.addEventListener('beforeinstallprompt', function (event) {
        event.preventDefault();
        deferredInstallPrompt = event;
        updateInstallUi();
    });

    window.addEventListener('appinstalled', function () {
        deferredInstallPrompt = null;
        updateInstallUi();
    });

    document.addEventListener('DOMContentLoaded', function () {
        var installBtn = $('install-app-btn');
        var overviewInstallBtn = $('overview-install-app-btn');

        function bindInstall(button) {
            if (!button) return;
            button.addEventListener('click', async function () {
                if (!deferredInstallPrompt) return;

                if (window.profileShowLoader) {
                    window.profileShowLoader('Открываем установку', 'Браузер готовит системное окно.');
                }
                try {
                    deferredInstallPrompt.prompt();
                    await deferredInstallPrompt.userChoice;
                } finally {
                    if (window.profileHideLoader) {
                        window.profileHideLoader();
                    }
                }
                deferredInstallPrompt = null;
                updateInstallUi();
            });
        }

        bindInstall(installBtn);
        bindInstall(overviewInstallBtn);

        updateInstallUi();
        refreshPushState();
    });

    if (document.readyState !== 'loading') {
        updateInstallUi();
        refreshPushState();
    }
})();
