/* eslint-disable */
const { logger } = require("firebase-functions");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onUserCreated } = require("firebase-functions/v2/identity");

const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();

/**
 * PART A(1): Seed a full user profile on first account creation.
 * Writes to users/{uid}. Uses a structure that matches the shape you want.
 */
exports.seedUserProfileOnCreate = onUserCreated(async (event) => {
  const user = event.data;
  if (!user) return;

  const { uid, email, displayName, phoneNumber, providerData } = user;
  const provider = Array.isArray(providerData) && providerData.length
    ? providerData[0].providerId
    : "password";

  const now = new Date();

  const payload = {
    bio: "",
    company: "GraphGo ",
    companyCode: "",                   // optional – fill from app if you use codes
    createdAt: now,
    email: email || "",
    fcmToken: "",
    fcmTokenUpdatedAt: null,
    firstName: "",
    lastName: "",
    lastSignIn: now,
    last_sign_in: now,
    name: displayName || email || "Unknown User",
    phone: phoneNumber || "",
    profileImageUrl: "",
    provider: provider,
    role: "Driver",                    // you can change later to "Admin" in app/console
    updatedAt: now,
  };

  await db.collection("users").doc(uid).set(payload, { merge: true });
  logger.info(`Seeded user profile for uid=${uid}`);
});


/**
 * PART B: Send chat notifications only to recipients (not the sender).
 * Trigger: chats/{chatId}/messages/{messageId}
 * Requires parent chat doc to have: { users: [uid1, uid2] }
 * Each user doc must have: { fcmToken }
 */
exports.sendChatNotification = onDocumentCreated(
  "chats/{chatId}/messages/{messageId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const messageData = snap.data() || {};
    const { chatId } = event.params;

    const senderId = messageData.senderId || "";
    const text = (messageData.message || "").toString();

    // 1) Load chat doc to get the participants
    const chatRef = db.collection("chats").doc(chatId);
    const chatDoc = await chatRef.get();
    if (!chatDoc.exists) {
      logger.warn(`Chat ${chatId} not found — aborting notification`);
      return;
    }
    const chat = chatDoc.data() || {};
    const users = Array.isArray(chat.users) ? chat.users : [];
    const recipientIds = users.filter((u) => u !== senderId);

    if (recipientIds.length === 0) {
      logger.info(`No recipients for chat ${chatId}`);
      return;
    }

    // 2) Try to show sender's name in the notification title
    let senderName = "New message";
    try {
      const senderDoc = await db.collection("users").doc(senderId).get();
      if (senderDoc.exists) {
        const d = senderDoc.data() || {};
        senderName = d.name || d.email || senderName;
      }
    } catch (_) {}

    // 3) Collect recipient tokens
    const userDocs = await Promise.all(
      recipientIds.map((uid) => db.collection("users").doc(uid).get())
    );

    const tokens = userDocs
      .map((doc) => (doc.exists ? doc.data().fcmToken : null))
      .filter((t) => typeof t === "string" && t.length > 0);

    if (tokens.length === 0) {
      logger.info(`Recipients have no fcmToken — nothing to send`);
      return;
    }

    const body = text.length > 100 ? text.slice(0, 100) + "…" : (text || "New message");

    // 4) Build the notification
    // For web: we pass a link with the chatId as a query param so the app can open the right chat.
    const msg = {
      tokens,
      notification: { title: senderName, body },
      data: {
        type: "chat_message",
        chatId,
        senderId,
      },
      webpush: {
        fcmOptions: {
          // This will open your PWA to "/" and include ?openChat={chatId}
          link: `/#/?openChat=${encodeURIComponent(chatId)}`,
        },
      },
    };

    // 5) Send
    const res = await getMessaging().sendEachForMulticast(msg);
    logger.info(`✅ sendChatNotification → ${res.successCount} sent, ${res.failureCount} failed`);
  }
);
