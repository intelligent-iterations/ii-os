'use strict';

function notificationPayload(event) {
  try {
    return event.data ? event.data.json() : {};
  } catch (_) {
    return {};
  }
}

self.addEventListener('push', (event) => {
  const payload = notificationPayload(event);
  const notification = payload.notification || {};
  const data = payload.data || {};
  const deepLink = data.deepLink || '/';
  const title = notification.title || 'Generation ready';
  event.waitUntil(
    self.registration.showNotification(title, {
      body: notification.body || 'Tap to view the finished generation.',
      icon: '/icons/Icon-192.png',
      badge: '/icons/notification-badge-96.png',
      tag: data.notificationId
        ? `ii-os-generation-${data.notificationId}`
        : 'ii-os-generation',
      data: { deepLink },
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  let target = new URL(
    event.notification.data?.deepLink || '/',
    self.location.origin,
  );
  if (target.origin !== self.location.origin) {
    target = new URL('/', self.location.origin);
  }
  event.waitUntil(
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then(async (clients) => {
        for (const client of clients) {
          if (new URL(client.url).origin !== target.origin) continue;
          if ('navigate' in client) await client.navigate(target.href);
          return client.focus();
        }
        return self.clients.openWindow(target.href);
      }),
  );
});
