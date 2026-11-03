'use strict';

async function clearFlutterCaches() {
  const names = await caches.keys();
  await Promise.all(
    names
      .filter((name) => name.startsWith('flutter-'))
      .map((name) => caches.delete(name)),
  );
}

self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      await clearFlutterCaches();
      await self.clients.claim();
      const clients = await self.clients.matchAll({
        type: 'window',
        includeUncontrolled: true,
      });
      await self.registration.unregister();
      await Promise.all(
        clients.map(async (client) => {
          if (client.url && 'navigate' in client) {
            await client.navigate(client.url);
          }
        }),
      );
    })(),
  );
});
