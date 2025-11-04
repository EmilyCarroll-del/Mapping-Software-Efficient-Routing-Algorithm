importScripts("https://www.gstatic.com/firebasejs/11.0.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/11.0.1/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyByWSG8ewS_QX2jLfsmO5YsnbKE7HH8HRE",
  authDomain: "graph-go-bd4f0.firebaseapp.com",
  projectId: "graph-go-bd4f0",
  storageBucket: "graph-go-bd4f0.firebasestorage.app",
  messagingSenderId: "627645762372",
  appId: "1:627645762372:web:45d648b5ef756be6f2a511",
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const data = payload?.data || {};
  const title = (payload?.notification && payload.notification.title) || data.title || "GraphGo";
  const body  = (payload?.notification && payload.notification.body)  || data.body  || "New message";

  self.registration.showNotification(title, {
    body,
    icon: "/icons/Icon-192.png",
    data, // keep chatId, type, etc.
  });
});

// Open/focus the app on the chat screen
self.addEventListener("notificationclick", (event) => {
  const data = event.notification?.data || {};
  event.notification.close();

  const url = `/?openChat=${encodeURIComponent(data.chatId || "")}`;
  event.waitUntil((async () => {
    const allClients = await clients.matchAll({ type: "window", includeUncontrolled: true });
    // Try to focus an existing tab
    for (const client of allClients) {
      const u = new URL(client.url);
      if (u.origin === self.location.origin) {
        client.postMessage({ type: "OPEN_CHAT", chatId: data.chatId || "" });
        return client.focus();
      }
    }
    // Or open a new one
    return clients.openWindow(url);
  })());
});
