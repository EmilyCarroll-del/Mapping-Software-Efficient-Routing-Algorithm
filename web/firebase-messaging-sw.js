/* web/firebase-messaging-sw.js */
// Import the compat builds so we can init in a SW
importScripts('https://www.gstatic.com/firebasejs/11.0.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/11.0.0/firebase-messaging-compat.js');

// IMPORTANT: paste your web app's Firebase config here
firebase.initializeApp({
  apiKey: "AIzaSyByWSG8ewS_QX2jLfsmO5YsnbKE7HH8HRE",
  authDomain: "YOUR_PROJECT.firebaseapp.com",
  projectId: "graph-go-bd4f0",
  messagingSenderId: "627645762372",
  appId: "1:627645762372:web:951f0e05232e1b23f2a511"
});

const messaging = firebase.messaging();

// Show a notification when a background push arrives (data-only or notification payloads)
messaging.onBackgroundMessage(({ notification, data }) => {
  const title = notification?.title || data?.title || "Update";
  const options = {
    body: notification?.body || data?.body || "Tap to open",
    icon: "/icons/Icon-192.png",
    data
  };
  self.registration.showNotification(title, options);
});

// Click → open admin page/route
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = event.notification?.data?.url || '/';
  event.waitUntil(clients.openWindow(url));
});
