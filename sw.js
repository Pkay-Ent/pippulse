/* PipPulse Web Push service worker */
self.addEventListener("push", event => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (_) {}
  const title = String(data.title || "PipPulse Gold Signals").slice(0, 80);
  const options = {
    body: String(data.body || "A new trading signal is available. Open PipPulse to view it.").slice(0, 180),
    icon: "/icon-192.png",
    badge: "/icon-192.png",
    tag: data.tag || "pippulse-signal",
    renotify: true,
    data: { url: data.url || "/" }
  };
  event.waitUntil(self.registration.showNotification(title, options));
});
self.addEventListener("notificationclick", event => {
  event.notification.close();
  const target = new URL(event.notification.data?.url || "/", self.location.origin).href;
  event.waitUntil((async () => {
    const clientsList = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const client of clientsList) {
      if (new URL(client.url).origin === self.location.origin) {
        await client.focus();
        if ("navigate" in client) await client.navigate(target);
        return;
      }
    }
    await self.clients.openWindow(target);
  })());
});