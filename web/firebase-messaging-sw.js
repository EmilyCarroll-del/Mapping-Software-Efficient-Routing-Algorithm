// web/firebase-messaging-sw.js
/* eslint-disable no-restricted-globals */
importScripts('https://www.gstatic.com/firebasejs/11.0.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/11.0.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyByWSG8ewS_QX2jLfsmO5YsnbKE7HH8HRE",
  appId: "1:627645762372:web:45d648b5ef756be6f2a511",
  messagingSenderId: "627645762372",
  projectId: "graph-go-bd4f0",
  authDomain: "graph-go-bd4f0.firebaseapp.com",
  storageBucket: "graph-go-bd4f0.firebasestorage.app",
  measurementId: "G-DW8MH83H28",
});

const messaging = firebase.messaging();

/**
 * Helpful: if you run the app on different localhost ports while developing,
 * you can end up with multiple service workers. This makes duplicates more likely.
 * After updating this file, do a hard reload and consider "Unregister" old SWs
 * in chrome://serviceworker-internals (or DevTools > Application > Service Workers).
 */

/**
 * Build a deterministic notification "tag" so the browser replaces the
 * previous one instead of stacking duplicates. We try the most specific ID
 * first, but fall back gracefully if fields aren’t present.
 */
function buildTag(d) {
  return (
    d.nid ||                   // explicit id if your sender provides one
    d.messageId ||             // message doc id (if provided)
    (d.chatId && d.senderId ? `chat:${d.chatId}|from:${d.senderId}` : null) ||
    (d.chatId ? `chat:${d.chatId}` : null) ||
    `${(d.title||'')}|${(d.body||'')}`     // worst-case fallback
  );
}

/**
 * Only show a notification if there isn't already one with the same tag.
 * If one exists, we replace it (same tag) so you never get 2–4 copies.
 */
async function showOnce(title, options) {
  const tag = options.tag;
  if (tag) {
    const existing = await self.registration.getNotifications({ tag });
    // If you want to REPLACE, close old and show new:
    existing.forEach(n => n.close());
  }
  return self.registration.showNotification(title, options);
}

messaging.onBackgroundMessage(async (payload) => {
  const d = payload?.data || {};
  const title = d.title || 'GraphGo';
  const body  = d.body  || 'You have a new message';
  const chatId = d.chatId || '';
  const tag = buildTag(d);              // <— deterministic, collapses dupes

  await showOnce(title, {
    body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag,                                // <— key piece
    renotify: false,                    // don’t buzz if we’re just replacing
    data: { chatId, ...d },
  });
});

// Clicking the toast → focus an open tab or open a new one
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const chatId = event.notification?.data?.chatId || '';
  const url = chatId
    ? `${self.location.origin}/#/map?chatId=${chatId}`
    : `${self.location.origin}/#/map`;

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) {
          client.postMessage({ type: 'OPEN_CHAT', chatId });
          return client.focus();
        }
      }
      return clients.openWindow(url);
    })
  );
});
