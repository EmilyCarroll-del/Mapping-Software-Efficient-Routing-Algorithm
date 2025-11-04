// server/index.js
/* eslint-disable */
require('dotenv').config();
const admin = require('firebase-admin');

// 1) Initialize Admin SDK (uses GOOGLE_APPLICATION_CREDENTIALS if set)
if (admin.apps.length === 0) {
  admin.initializeApp({
    // If running on your machine and GOOGLE_APPLICATION_CREDENTIALS is set,
    // you don’t need to pass any options here.
    projectId: process.env.FIREBASE_PROJECT_ID, // optional but nice for logs
  });
}

const db = admin.firestore();
const messaging = admin.messaging();

// Utility: safe truncate for notification body
const truncate = (s, n = 80) => (s && s.length > n ? s.slice(0, n) + '…' : (s || ''));

// MAIN: watch all new messages in all chats
(async function main() {
  console.log('🔥 notifier is running and connected to Firestore…');

  db.collectionGroup('messages')
    .onSnapshot(async (snap) => {
      // We get initial snapshot with existing docs; only handle *added* changes
      for (const change of snap.docChanges()) {
        if (change.type !== 'added') continue;

        const messageRef = change.doc.ref;
        const message = change.doc.data() || {};
        const chatId = messageRef.parent.parent.id;

        const senderId = message.senderId || '';
        const text = String(message.message || 'New message');

        // Load the chat doc to get participants
        const chatDoc = await db.collection('chats').doc(chatId).get();
        if (!chatDoc.exists) {
          console.log(`⚠️ chat ${chatId} not found`);
          continue;
        }

        const chat = chatDoc.data() || {};
        const users = Array.isArray(chat.users) ? chat.users : [];
        if (users.length === 0) {
          console.log(`ℹ️ chat ${chatId} has no users`);
          continue;
        }

        // Recipients = everyone except sender
        const recipientIds = users.filter((u) => u !== senderId);
        if (recipientIds.length === 0) {
          console.log(`ℹ️ no recipients for chat ${chatId} (sender-only?)`);
          continue;
        }

        // Pull user docs to get tokens
        const userDocs = await Promise.all(
          recipientIds.map((uid) => db.collection('users').doc(uid).get())
        );

        // Collect tokens, keeping a map uid -> token for cleanup
        const tokenMap = new Map(); // uid -> token
        for (let i = 0; i < userDocs.length; i++) {
          const doc = userDocs[i];
          if (!doc.exists) continue;
          const { fcmToken } = doc.data() || {};
          if (typeof fcmToken === 'string' && fcmToken.length > 0) {
            tokenMap.set(doc.id, fcmToken);
          }
        }

        const tokens = [...tokenMap.values()];
        if (tokens.length === 0) {
          console.log(`ℹ️ recipients have no fcmToken (chat ${chatId})`);
          continue;
        }

        const body = truncate(text);

        const payload = {
          tokens,
          notification: {
            title: 'New chat message',
            body,
          },
          data: {
            type: 'CHAT_MESSAGE',
            chatId,
            senderId,
            body, // handy on web SW
          },
        };

        try {
          const res = await messaging.sendEachForMulticast(payload);

          // Log delivery
          console.log(
            `✅ Sent to ${res.successCount}/${tokens.length} | chat=${chatId} path=${messageRef.path}`
          );

          // Clean up any dead tokens
          res.responses.forEach(async (r, idx) => {
            if (r.success) return;
            const err = r.error;
            const badToken = tokens[idx];

            const isDead =
              err?.code === 'messaging/registration-token-not-registered' ||
              err?.code === 'messaging/invalid-registration-token';

            if (isDead) {
              // find which uid had this token
              for (const [uid, tk] of tokenMap.entries()) {
                if (tk === badToken) {
                  console.log(`🧹 removing dead token for uid=${uid}`);
                  await db.collection('users').doc(uid).update({ fcmToken: admin.firestore.FieldValue.delete() }).catch(() => {});
                  break;
                }
              }
            } else {
              console.log(`⚠️ FCM error for one token:`, err?.code, err?.message);
            }
          });
        } catch (e) {
          console.error('❌ FCM send failed', e);
        }
      }
    }, (err) => {
      console.error('❌ Firestore watch error', err);
      process.exitCode = 1;
    });
})();
