/**
 * Auralith Service Worker — Web Push handler
 */

self.addEventListener('install', function () {
    self.skipWaiting();
});

self.addEventListener('activate', function (event) {
    event.waitUntil(self.clients.claim());
});

self.addEventListener('push', function (event) {
    if (!event.data) return;

    let data = {};
    try {
        data = event.data.json();
    } catch (e) {
        data = { title: 'Auralith', body: event.data.text() };
    }

    const meta    = data.data || {};
    const title   = data.title  || 'Auralith';
    const options = {
        body:    data.body  || '',
        icon:    data.icon  || '/images/notification-icon.png',
        badge:   data.badge || '/images/notification-badge.png',
        tag:     'auralith-notification',
        renotify: true,
        data: {
            url: meta.url || data.url || '/profile',
            type: meta.type || data.type || 'info',
        },
    };

    event.waitUntil(
        self.registration.showNotification(title, options)
    );
});

self.addEventListener('notificationclick', function (event) {
    event.notification.close();

    const url = (event.notification.data && event.notification.data.url)
        ? event.notification.data.url
        : '/profile';

    event.waitUntil(
        clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (clientList) {
            for (const client of clientList) {
                if (client.url.includes(url) && 'focus' in client) {
                    return client.focus();
                }
            }
            if (clients.openWindow) {
                return clients.openWindow(url);
            }
        })
    );
});
// v4
