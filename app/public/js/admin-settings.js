(function () {
    const config = window.ADMIN_SETTINGS || {};
    const pushSwitch = document.getElementById('adminPushSwitch');
    const pushStatus = document.getElementById('adminPushStatus');
    const testPushButton = document.getElementById('adminTestPush');
    const sendDigestNowButton = document.getElementById('adminSendDigestNow');
    const webauthnStatus = document.getElementById('adminWebAuthnStatus');
    const webauthnRegisterButton = document.getElementById('adminWebAuthnRegister');
    const webauthnReplaceButton = document.getElementById('adminWebAuthnReplace');
    const webauthnDeleteButton = document.getElementById('adminWebAuthnDelete');
    const installButton = document.getElementById('adminInstallApp');
    const installStatus = document.getElementById('adminInstallStatus');
    let deferredInstallPrompt = null;

    function showLoader(title, detail) {
        if (window.admShowLoader) window.admShowLoader(title, detail);
    }

    function hideLoader() {
        if (window.admHideLoader) window.admHideLoader();
    }

    function setPushStatus(message) {
        if (pushStatus) pushStatus.textContent = message;
    }

    function setWebAuthnStatus(message) {
        if (webauthnStatus) webauthnStatus.textContent = message;
    }

    function base64ToBuffer(base64) {
        const normalized = base64.replace(/-/g, '+').replace(/_/g, '/');
        const raw = window.atob(normalized);
        const buffer = new Uint8Array(raw.length);

        for (let i = 0; i < raw.length; i++) {
            buffer[i] = raw.charCodeAt(i);
        }

        return buffer.buffer;
    }

    function bufferToBase64(buffer) {
        if (!buffer) return '';

        const bytes = new Uint8Array(buffer);
        let raw = '';

        for (const byte of bytes) {
            raw += String.fromCharCode(byte);
        }

        return window.btoa(raw).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
    }

    function base64ToUint8Array(base64String) {
        const padding = '='.repeat((4 - base64String.length % 4) % 4);
        const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
        const rawData = window.atob(base64);
        const outputArray = new Uint8Array(rawData.length);

        for (let i = 0; i < rawData.length; ++i) {
            outputArray[i] = rawData.charCodeAt(i);
        }

        return outputArray;
    }

    async function registration() {
        if (!('serviceWorker' in navigator)) {
            throw new Error('Service Worker не поддерживается');
        }

        const probe = await fetch('/sw.js', {
            cache: 'no-store',
            credentials: 'same-origin',
            headers: { 'Accept': 'application/javascript,text/javascript,*/*' },
        });

        if (!probe.ok) {
            throw new Error('Service Worker не найден: /sw.js вернул ' + probe.status);
        }

        const type = probe.headers.get('content-type') || '';
        if (type && !type.includes('javascript') && !type.includes('text/plain')) {
            throw new Error('Service Worker отдан не как JavaScript: ' + type);
        }

        const reg = await navigator.serviceWorker.register('/sw.js?v=4', {
            scope: '/',
            updateViaCache: 'none',
        });
        await navigator.serviceWorker.ready;

        return reg;
    }

    async function currentSubscription() {
        const reg = await registration();
        return reg.pushManager.getSubscription();
    }

    async function enablePush() {
        if (!('Notification' in window) || !('PushManager' in window)) {
            throw new Error('Браузер не поддерживает push-уведомления');
        }

        if (!config.vapidPublicKey) {
            throw new Error('VAPID ключ не настроен');
        }

        const permission = await Notification.requestPermission();
        if (permission !== 'granted') {
            throw new Error('Разрешение на уведомления не выдано');
        }

        const reg = await registration();
        let subscription = await reg.pushManager.getSubscription();

        if (!subscription) {
            subscription = await reg.pushManager.subscribe({
                userVisibleOnly: true,
                applicationServerKey: base64ToUint8Array(config.vapidPublicKey),
            });
        }

        const data = subscription.toJSON();
        const response = await fetch(config.pushSubscribeUrl, {
            method: 'POST',
            credentials: 'same-origin',
            headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'X-CSRF-TOKEN': config.csrfToken,
            },
            body: JSON.stringify({
                endpoint: data.endpoint,
                p256dh: data.keys && data.keys.p256dh,
                auth: data.keys && data.keys.auth,
                content_encoding: 'aes128gcm',
            }),
        });

        if (!response.ok) {
            throw new Error('Сервер не сохранил подписку');
        }
    }

    async function disablePush() {
        const subscription = await currentSubscription();

        if (subscription) {
            await fetch(config.pushUnsubscribeUrl, {
                method: 'DELETE',
                credentials: 'same-origin',
                headers: {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                    'X-CSRF-TOKEN': config.csrfToken,
                },
                body: JSON.stringify({ endpoint: subscription.endpoint }),
            });
        }
    }

    async function refreshPushStatus() {
        if (!pushSwitch) return;

        try {
            const response = await fetch(config.pushStatusUrl, {
                headers: { 'Accept': 'application/json' },
                credentials: 'same-origin',
            });
            const data = await response.json();
            pushSwitch.checked = !!data.subscribed;
            if (testPushButton) testPushButton.disabled = !data.subscribed;
            setPushStatus(data.subscribed ? 'Уведомления включены' : 'Уведомления выключены');
        } catch (e) {}
    }

    if (pushSwitch) {
        pushSwitch.addEventListener('change', async function () {
            pushSwitch.disabled = true;
            showLoader(
                pushSwitch.checked ? 'Включаем push' : 'Выключаем push',
                pushSwitch.checked ? 'Регистрируем устройство и сохраняем подписку.' : 'Отписываем это устройство от уведомлений.'
            );
            setPushStatus(pushSwitch.checked ? 'Включаем уведомления...' : 'Выключаем уведомления...');

            try {
                if (pushSwitch.checked) {
                    await enablePush();
                    setPushStatus('Уведомления включены');
                } else {
                    await disablePush();
                    setPushStatus('Уведомления выключены');
                }
            } catch (e) {
                pushSwitch.checked = !pushSwitch.checked;
                setPushStatus(e.message || 'Не удалось изменить настройку');
            } finally {
                pushSwitch.disabled = false;
                await refreshPushStatus();
                hideLoader();
            }
        });

        refreshPushStatus();
    }

    if (testPushButton) {
        testPushButton.addEventListener('click', async function () {
            testPushButton.disabled = true;
            showLoader('Отправляем тест', 'Проверяем доставку push-уведомления на это устройство.');
            setPushStatus('Отправляем тестовое уведомление...');

            try {
                const response = await fetch(config.pushTestUrl, {
                    method: 'POST',
                    credentials: 'same-origin',
                    headers: {
                        'Accept': 'application/json',
                        'X-CSRF-TOKEN': config.csrfToken,
                    },
                });
                const data = await response.json().catch(() => ({}));

                if (!response.ok || !data.ok) {
                    throw new Error(data.message || 'Не удалось отправить тест');
                }

                setPushStatus(data.message || 'Тестовое уведомление отправлено');
            } catch (e) {
                setPushStatus(e.message || 'Не удалось отправить тест');
            } finally {
                await refreshPushStatus();
                hideLoader();
            }
        });
    }

    if (sendDigestNowButton) {
        sendDigestNowButton.addEventListener('click', async function () {
            sendDigestNowButton.disabled = true;
            showLoader('Отправляем дайджест', 'Собираем состояние системы и отправляем уведомление администраторам.');
            const oldText = sendDigestNowButton.textContent;
            sendDigestNowButton.textContent = 'Отправляем...';

            try {
                const response = await fetch(config.digestSendNowUrl, {
                    method: 'POST',
                    credentials: 'same-origin',
                    headers: {
                        'Accept': 'application/json',
                        'X-CSRF-TOKEN': config.csrfToken,
                    },
                });
                const data = await response.json().catch(() => ({}));
                sendDigestNowButton.textContent = data.message || (response.ok ? 'Отправлено' : 'Ошибка отправки');
            } catch (e) {
                sendDigestNowButton.textContent = 'Ошибка отправки';
            } finally {
                setTimeout(function () {
                    sendDigestNowButton.disabled = false;
                    sendDigestNowButton.textContent = oldText;
                }, 3500);
                hideLoader();
            }
        });
    }

    async function registerWebAuthnFromSettings() {
        if (!window.PublicKeyCredential || !navigator.credentials) {
            throw new Error('Браузер не поддерживает вход по отпечатку / Face ID');
        }

        const available = await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable()
            .catch(() => false);

        if (!available) {
            throw new Error('На этом устройстве не найден доступный отпечаток / Face ID');
        }

        const challengeResponse = await fetch(config.webauthnRegisterChallengeUrl, {
            method: 'POST',
            credentials: 'same-origin',
            headers: {
                'Accept': 'application/json',
                'X-CSRF-TOKEN': config.csrfToken,
            },
        });
        const options = await challengeResponse.json().catch(() => ({}));

        if (!challengeResponse.ok) {
            throw new Error(options.error || 'Не удалось начать привязку');
        }

        const credential = await navigator.credentials.create({
            publicKey: {
                challenge: base64ToBuffer(options.challenge),
                rp: options.rp,
                user: {
                    id: base64ToBuffer(options.user.id),
                    name: options.user.name,
                    displayName: options.user.displayName,
                },
                pubKeyCredParams: options.pubKeyCredParams,
                timeout: options.timeout,
                authenticatorSelection: options.authenticatorSelection,
                attestation: options.attestation,
            },
        });

        const deviceName = /iPhone|iPad/.test(navigator.userAgent) ? 'iPhone/iPad'
            : /Android/.test(navigator.userAgent) ? 'Android'
            : 'Desktop';

        const verifyResponse = await fetch(config.webauthnRegisterVerifyUrl, {
            method: 'POST',
            credentials: 'same-origin',
            headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'X-CSRF-TOKEN': config.csrfToken,
            },
            body: JSON.stringify({
                credential_id: bufferToBase64(credential.rawId),
                public_key: bufferToBase64(credential.response.attestationObject),
                device_name: deviceName,
            }),
        });
        const result = await verifyResponse.json().catch(() => ({}));

        if (!verifyResponse.ok || !result.ok) {
            throw new Error(result.error || 'Сервер не сохранил отпечаток / Face ID');
        }

        localStorage.setItem('webauthn_registered_' + config.adminId, '1');
        localStorage.removeItem('webauthn_dismissed_' + config.adminId);
    }

    async function deleteWebAuthnFromSettings() {
        if (!config.webauthnDeleteUrl) {
            throw new Error('Привязка уже не найдена');
        }

        const response = await fetch(config.webauthnDeleteUrl, {
            method: 'DELETE',
            credentials: 'same-origin',
            headers: {
                'Accept': 'application/json',
                'X-CSRF-TOKEN': config.csrfToken,
            },
        });
        const result = await response.json().catch(() => ({}));

        if (!response.ok || !result.ok) {
            throw new Error(result.error || 'Не удалось удалить отпечаток / Face ID');
        }

        localStorage.removeItem('webauthn_registered_' + config.adminId);
        localStorage.removeItem('webauthn_dismissed_' + config.adminId);
    }

    async function handleWebAuthnRegister(button) {
        if (button) button.disabled = true;
        showLoader('Добавляем вход', 'Подтвердите отпечаток или Face ID на устройстве.');
        setWebAuthnStatus('Ожидаем подтверждение устройства...');

        try {
            await registerWebAuthnFromSettings();
            setWebAuthnStatus('Отпечаток / Face ID добавлены');
            window.location.reload();
        } catch (e) {
            setWebAuthnStatus(e.message || 'Не удалось добавить отпечаток / Face ID');
        } finally {
            if (button) button.disabled = false;
            hideLoader();
        }
    }

    async function handleWebAuthnDelete(button, shouldRegisterAgain) {
        if (!window.confirm('Удалить текущую привязку отпечатка / Face ID?')) return;

        if (button) button.disabled = true;
        showLoader('Удаляем привязку', 'Отключаем вход по отпечатку / Face ID для этого аккаунта.');
        setWebAuthnStatus('Удаляем текущую привязку...');

        try {
            await deleteWebAuthnFromSettings();

            if (shouldRegisterAgain) {
                setWebAuthnStatus('Старая привязка удалена. Добавляем новую...');
                await registerWebAuthnFromSettings();
                setWebAuthnStatus('Новая привязка добавлена');
            } else {
                setWebAuthnStatus('Отпечаток / Face ID удалены');
            }

            window.location.reload();
        } catch (e) {
            setWebAuthnStatus(e.message || 'Не удалось изменить привязку');
        } finally {
            if (button) button.disabled = false;
            hideLoader();
        }
    }

    if (webauthnRegisterButton) {
        webauthnRegisterButton.addEventListener('click', function () {
            handleWebAuthnRegister(webauthnRegisterButton);
        });
    }

    if (webauthnReplaceButton) {
        webauthnReplaceButton.addEventListener('click', function () {
            handleWebAuthnDelete(webauthnReplaceButton, true);
        });
    }

    if (webauthnDeleteButton) {
        webauthnDeleteButton.addEventListener('click', function () {
            handleWebAuthnDelete(webauthnDeleteButton, false);
        });
    }

    function isIos() {
        return /iphone|ipad|ipod/i.test(navigator.userAgent)
            || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    }

    function isStandalone() {
        return window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;
    }

    async function prepareWebAppInstall() {
        if (!installStatus || isStandalone()) return;

        try {
            await registration();
            if (!deferredInstallPrompt && !isIos()) {
                installStatus.textContent = 'Готовим установку. Если кнопка не сработает, обновите страницу через несколько секунд.';
            }
        } catch (e) {
            installStatus.textContent = e.message || 'Не удалось подготовить установку приложения';
        }
    }

    if (installStatus && isStandalone()) {
        installStatus.textContent = 'Приложение уже установлено';
        if (installButton) installButton.disabled = true;
    } else if (installStatus && isIos()) {
        installStatus.textContent = 'На iPhone установка доступна через меню Safari: Поделиться → На экран Домой';
    }

    window.addEventListener('beforeinstallprompt', function (event) {
        event.preventDefault();
        deferredInstallPrompt = event;
        if (installStatus) installStatus.textContent = 'Можно установить как приложение';
        if (installButton) installButton.disabled = false;
    });

    if (installButton) {
        installButton.addEventListener('click', async function () {
            if (isIos()) {
                if (installStatus) installStatus.textContent = 'Откройте Safari: Поделиться → На экран Домой';
                return;
            }

            if (!deferredInstallPrompt) {
                if (installStatus) installStatus.textContent = 'Браузер пока не дал prompt. Откройте меню браузера и выберите установку приложения.';
                return;
            }

            deferredInstallPrompt.prompt();
            const choice = await deferredInstallPrompt.userChoice;
            deferredInstallPrompt = null;
            if (installStatus) {
                installStatus.textContent = choice.outcome === 'accepted'
                    ? 'Приложение установлено'
                    : 'Установка отменена';
            }
        });
    }
})();
