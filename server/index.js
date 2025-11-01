// server/index.js
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import admin from "firebase-admin";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// 1. read service account
const serviceAccountPath = path.join(__dirname, "serviceAccount.json");
const raw = fs.readFileSync(serviceAccountPath, "utf8");
const serviceAccount = JSON.parse(raw);

// 2. init admin SDK
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: "graph-go-bd4f0", // <- keep this
});

const db = admin.firestore();
const fcm = admin.messaging();

// 👇 remember when this process started
const startedAt = Date.now();

console.log("🔥 notifier is running and connected to Firestore…");

// 3. listen to ALL messages in all chats
db.collectionGroup("messages").onSnapshot(
  (snapshot) => {
    snapshot.docChanges().forEach(async (change) => {
      if (change.type !== "added") return;

      const messageDoc = change.doc;
      const messageData = messageDoc.data();

      // messages should have something like:
      // { message: "...", senderId: "...", timestamp: FieldValue.serverTimestamp() }
      const ts = messageData.timestamp;

      // ⛔ 1) if no timestamp yet, skip (wait for the next update)
      if (!ts) {
        // console.log("⏭️ skipping message with no timestamp yet");
        return;
      }

      const messageTime = ts.toMillis ? ts.toMillis() : ts;

      // ⛔ 2) if this message is from BEFORE this server started → skip (old history)
      if (messageTime < startedAt) {
        // console.log("⏭️ skipping old message", messageDoc.ref.path);
        return;
      }

      const senderId = messageData.senderId;
      const text = messageData.message || "";

      // parent of messages/{doc} is chats/{chatId}
      const chatRef = messageDoc.ref.parent.parent;
      if (!chatRef) return;

      const chatSnap = await chatRef.get();
      const chatData = chatSnap.data() || {};
      const users = chatData.users || [];

      // everyone except sender
      const recipients = users.filter((u) => u !== senderId);

      for (const receiverId of recipients) {
        const userSnap = await db.collection("users").doc(receiverId).get();
        const userData = userSnap.data() || {};
        const token = userData.fcmToken;

        if (!token) {
          console.log("ℹ️ user", receiverId, "has no fcmToken — skipping");
          continue;
        }

        const payload = {
          token,
          notification: {
            title: "New message",
            body: text || "You have a new message",
          },
          data: {
            chatId: chatRef.id,
            senderId: senderId ?? "",
            type: "ADMIN_MESSAGE",
          },
        };

        try {
          const res = await fcm.send(payload);
          console.log("✅ Sent to", receiverId, messageDoc.ref.path, res);
        } catch (err) {
          console.error("❌ Error sending to", receiverId, err);
        }
      }
    });
  },
  (err) => {
    console.error("🔥 Firestore listener error:", err);
  }
);
