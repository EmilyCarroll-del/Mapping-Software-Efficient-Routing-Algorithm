// web/firebase-messaging-sw.js
/* eslint-disable no-restricted-globals */
importScripts('https://www.gstatic.com/firebasejs/11.0.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/11.0.1/firebase-messaging-compat.js');


// 👉 Option B: take control immediately so Chrome doesn't show
// "This site has been updated in the background."
self.skipWaiting();
self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});


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

// ---- helper for data-only notifs (non-chat) ----
function buildTag(d) {
  return (
    d.nid ||
    d.messageId ||
    (d.chatId && d.senderId ? `chat:${d.chatId}|from:${d.senderId}` : null) ||
    (d.chatId ? `chat:${d.chatId}` : null) ||
    `${(d.title || '')}|${(d.body || '')}`
  );
}

async function showOnce(title, options) {
  const tag = options.tag;
  if (tag) {
    const existing = await self.registration.getNotifications({ tag });
    existing.forEach(n => n.close());
  }
  return self.registration.showNotification(title, options);
}

// ---- background handler ----
messaging.onBackgroundMessage(async (payload) => {
  const d = (payload && payload.data) || {};

  // Chat messages now come from Node with BOTH:
  //   data.type === "CHAT_MESSAGE" AND payload.notification present.
  // Chrome/FCM already shows the toast from payload.notification,
  // so we do NOTHING here to avoid duplicates.
  if (d.type === 'CHAT_MESSAGE' && payload && payload.notification) {
    return;
  }

  // For other pure data messages, we still show manually.
  const title = d.title || 'GraphGo';
  const body  = d.body  || 'You have a new message';
  const chatId = d.chatId || '';
  const tag = buildTag(d);

  await showOnce(title, {
    body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag,
    renotify: false,
    data: { chatId, ...d },
  });
});

// ---- click handler for BOTH FCM + manual notifs ----
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const raw = event.notification && event.notification.data ? event.notification.data : {};

  const chatId =
    raw.chatId ||                                      // for our manual notifs
    (raw.FCM_MSG && raw.FCM_MSG.data && raw.FCM_MSG.data.chatId) || // auto FCM notifs
    '';

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