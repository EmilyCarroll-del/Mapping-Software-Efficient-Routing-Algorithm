// functions/index.js
/* eslint-disable */
// 1) import the v2 Firestore trigger
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions");

// 2) firebase-admin (to read Firestore + send FCM)
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

// init admin SDK once
initializeApp();
const db = getFirestore();

/**
 * Trigger: whenever a new message doc is created at
 * chats/{chatId}/messages/{messageId}
 *
 * We will:
 * 1. read the parent chat (to know who is in this chat)
 * 2. figure out who the sender was
 * 3. for every *other* user in that chat, read their user doc
 * 4. grab their fcmToken
 * 5. send them a notification
 */
exports.sendChatNotification = onDocumentCreated(
    "chats/{chatId}/messages/{messageId}",
    async (event) => {
        // the message that was just written
        const snap = event.data;
        if (!snap) {
            logger.warn("No snapshot data on event");
            return;
        }

        const messageData = snap.data() || {};
        const chatId = event.params.chatId;

        const senderId = messageData.senderId || "";
        const text = (messageData.message || "").toString();

        // 1. get the parent chat
        const chatRef = db.collection("chats").doc(chatId);
        const chatDoc = await chatRef.get();
        if (!chatDoc.exists) {
            logger.warn(`Chat ${chatId} not found — aborting notification`);
            return;
        }

        const chat = chatDoc.data() || {};
        const users = Array.isArray(chat.users) ? chat.users : [];
        if (users.length === 0) {
            logger.info(`Chat ${chatId} has no users array — nothing to notify`);
            return;
        }

        // 2. find recipients (everyone except sender)
        const recipientIds = users.filter((uid) => uid !== senderId);

        if (recipientIds.length === 0) {
            logger.info("No recipients (maybe sender was the only one)");
            return;
        }

        // 3. load each recipient's user doc to get their FCM token
        const userDocs = await Promise.all(
            recipientIds.map((uid) => db.collection("users").doc(uid).get()),
        );

        const tokens = userDocs
            .map((doc) => (doc.exists ? doc.data().fcmToken : null))
            .filter((t) => typeof t === "string" && t.length > 0);

        if (tokens.length === 0) {
            logger.info("Recipients have no fcmToken — nothing to send");
            return;
        }

        // 4. build the notification
        const body =
      text.length > 80 ? text.substring(0, 80) + "…" : text || "New message";

        const multicast = {
            tokens,
            notification: {
                title: "New chat message",
                body,
            },
            data: {
                type: "CHAT_MESSAGE",
                chatId,
                senderId,
            },
        };

        // 5. send to FCM
        const res = await getMessaging().sendEachForMulticast(multicast);
        logger.info(
            `✅ sentChatNotification → ${res.successCount} sent, ${res.failureCount} failed`,
        );
    },
);
