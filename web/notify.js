// web/notify.js
async function showBrowserNotification(title, body, url) {
  try {
    // Use the SW so clicks behave the same as background pushes.
    const reg = await navigator.serviceWorker.getRegistration();
    if (!reg) return;

    await reg.showNotification(title || "Update", {
      body: body || "",
      icon: "/icons/Icon-192.png",
      data: { url: url || "/" },  // keep a URL for click-through
      requireInteraction: false,  // set to true if you want it to stay until clicked
    });
  } catch (e) {
    // Fallback: use the page Notification API
    if (Notification && Notification.permission === "granted") {
      new Notification(title || "Update", { body: body || "" });
    }
  }
}
