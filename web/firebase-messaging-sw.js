// web/firebase-messaging-sw.js
importScripts('https://www.gstatic.com/firebasejs/11.0.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/11.0.1/firebase-messaging-compat.js');

// Initialize the Firebase app in the service worker with the same credentials as the main app
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

// Background: show a toast for data-only messages
messaging.onBackgroundMessage((payload) => {
  const d = payload.data || {};
  const title = d.title || 'GraphGo';
  const body  = d.body  || 'You have a new message';
  const chatId = d.chatId || '';

  self.registration.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: { chatId },
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
          // Optionally tell the page which chat to open
          client.postMessage({ type: 'OPEN_CHAT', chatId });
          return client.focus();
        }
      }
      return clients.openWindow(url);
    })
  );
});
