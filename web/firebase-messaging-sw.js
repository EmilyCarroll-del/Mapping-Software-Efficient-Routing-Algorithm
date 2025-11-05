// web/firebase-messaging-sw.js
importScripts('https://www.gstatic.com/firebasejs/11.0.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/11.0.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyByWSG8ewS_QX2jLfsmO5YsnbKE7HH8HRE",
  authDomain: "graph-go-bd4f0.firebaseapp.com",
  projectId: "graph-go-bd4f0",
  storageBucket: "graph-go-bd4f0.firebasestorage.app",
  messagingSenderId: "627645762372",
  appId: "1:627645762372:web:45d648b5ef756be6f2a511",
});

const messaging = firebase.messaging();

// Show notification for data-only messages
messaging.onBackgroundMessage((payload) => {
  const data = payload.data || {};
  const title = data.title || 'GraphGo';
  const body = data.body || 'You have a new message';
  self.registration.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
    data,
  });
});

// Handle clicks → focus an open tab or open a new one
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = self.location.origin + '/#/map'; // open app
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow(url);
    })
  );
});
