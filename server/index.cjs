// server/index.cjs (CommonJS)
// Run with: node server/index.cjs

const admin = require("firebase-admin");
const path = require("path");

const serviceAccountPath = path.resolve(__dirname, "serviceAccount.json");
const serviceAccount = require(serviceAccountPath);

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: serviceAccount.project_id,
  });
}

const db = admin.firestore();
const messaging = admin.messaging();
const FieldValue = admin.firestore.FieldValue;

console.log("🔥 notifier listening for new chat messages…");

// Only notify for docs created AFTER this process starts
const SERVER_STARTED_AT = admin.firestore.Timestamp.now();

// Small de-dupe for reconnects
const processed = new Set();
const MAX_SEEN = 500;
function remember(id) {
  processed.add(id);
  if (processed.size > MAX_SEEN) {
    processed.delete(processed.values().next().value);
  }
}

function getOtherParticipants(usersArr, senderId) {
  return Array.isArray(usersArr) ? usersArr.filter((u) => u !== senderId) : [];
}

// Listen across all chats' messages
db.collectionGroup("messages").onSnapshot(
  async (snap) => {
    for (const change of snap.docChanges()) {
      if (change.type !== "added") continue;

      const msgRef = change.doc.ref;
      const msgId = change.doc.id;

      // Skip messages created before listener started
      const createdAt = change.doc.createTime;
      if (createdAt && createdAt.toMillis() <= SERVER_STARTED_AT.toMillis()) {
        continue;
      }

      if (processed.has(msgId)) continue;

      const data = change.doc.data() || {};
      const senderId = (data.senderId || "").toString();
      const text = (data.message || "").toString();

      // parent chat (/chats/{chatId})
      const chatRef = msgRef.parent.parent;
      if (!chatRef) {
        remember(msgId);
        continue;
      }

      try {
        const chatSnap = await chatRef.get();
        if (!chatSnap.exists) {
          console.warn("Chat not found for message:", msgRef.path);
          remember(msgId);
          continue;
        }

        const chat = chatSnap.data() || {};
        const recipients = getOtherParticipants(chat.users, senderId);
        if (recipients.length === 0) {
          remember(msgId);
          continue;
        }

        // Look up recipient tokens
        const userDocs = await Promise.all(
          recipients.map((uid) => db.collection("users").doc(uid).get())
        );
        const tokens = userDocs
          .map((d) => (d.exists ? d.data().fcmToken : null))
          .filter((t) => typeof t === "string" && t.length > 0);

        if (tokens.length === 0) {
          remember(msgId);
          continue;
        }

        // Fetch sender's display name (fallback to email or 'Someone')
        let senderName = "Someone";
        try {
          const senderDoc = await db.collection("users").doc(senderId).get();
          const u = senderDoc.exists ? (senderDoc.data() || {}) : {};
          senderName = u.displayName || u.name || u.email || "Someone";
        } catch (_) {
          // keep default
        }

        // Build human-readable strings
        const title = `${senderName} sent you a message`;
        const body = text
          ? text.length > 80
            ? text.slice(0, 80) + "…"
            : text
          : "New message";

        // For mobile, we want order info if you store it on the chat
        const orderId = (chat.orderId || "").toString();
        const orderTitle = (chat.orderTitle || "").toString();

        // ✅ Payload that works for BOTH:
        //   - Web SW (uses data.type = CHAT_MESSAGE, chatId, senderId, title, body)
        //   - Mobile app (uses notification + data.conversationId, otherUserId, otherUserName, etc.)
        const multicast = {
          tokens,
          notification: {
            // Android / iOS system notification (mobile)
            title,
            body,
          },
          data: {
            // For existing web service worker:
            type: "CHAT_MESSAGE",
            chatId: chatRef.id,
            senderId,
            title,
            body,

            // Extra keys for mobile NotificationService:
            conversationId: chatRef.id,
            otherUserId: senderId,
            otherUserName: senderName,
            orderId,
            orderTitle,
            isOldFormat: "false",
          },
          webpush: { fcmOptions: { link: "/" } },
          android: { priority: "high" },
          apns: { headers: { "apns-priority": "10" } },
        };

        const res = await messaging.sendEachForMulticast(multicast);

        // Clean up invalid tokens
        const failedTokens = [];
        res.responses.forEach((r, i) => {
          if (!r.success) {
            const code = r.error?.code || "";
            if (code.includes("registration-token-not-registered")) {
              failedTokens.push(tokens[i]);
            }
          }
        });

        if (failedTokens.length > 0) {
          console.log("🧹 Removing invalid tokens:", failedTokens);
          const batch = db.batch();
          userDocs.forEach((doc) => {
            const u = doc.data() || {};
            if (failedTokens.includes(u.fcmToken)) {
              batch.update(doc.ref, { fcmToken: FieldValue.delete() });
            }
          });
          await batch.commit();
        }

        console.log(`✅ Sent to ${tokens.length} token(s) →`, msgRef.path);
      } catch (err) {
        console.error("Listener error while processing", msgRef.path, err);
      } finally {
        remember(msgId);
      }
    }
  },
  (err) => {
    console.error("Listener error:", err);
    process.exitCode = 1;
  }
);
