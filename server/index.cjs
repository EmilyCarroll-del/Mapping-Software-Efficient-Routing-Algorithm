// server/index.cjs  (CommonJS)
// Run with:  node server/index.cjs


const admin = require("firebase-admin");
const path = require("path");


// ---- Admin init with explicit service account (local run) ----
const serviceAccountPath = path.resolve(__dirname, "serviceAccount.json");
const serviceAccount = require(serviceAccountPath);


if (!admin.apps.length) {
 admin.initializeApp({
   credential: admin.credential.cert(serviceAccount),
   projectId: serviceAccount.project_id, // ensures project is detected
 });
}


const db = admin.firestore();
const messaging = admin.messaging();
const FieldValue = admin.firestore.FieldValue;


console.log("🔥 notifier listening for new chat messages…");


// To avoid duplicate sends when the listener reconnects,
// keep a small in-memory set of processed message IDs.
const processed = new Set();
const MAX_SEEN = 500;


function remember(id) {
 processed.add(id);
 if (processed.size > MAX_SEEN) {
   // trim roughly (not critical)
   const first = processed.values().next().value;
   processed.delete(first);
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
     if (processed.has(msgId)) continue;


     // message data
     const data = change.doc.data() || {};
     const senderId = data.senderId || "";
     const text = (data.message || "").toString();


     // locate the parent chat (…/chats/{chatId}/messages/{messageId})
     const chatRef = msgRef.parent.parent;
     if (!chatRef) continue;


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


       // Load recipient user docs to get tokens
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


       const body = text.length > 80 ? text.slice(0, 80) + "…" : text || "New message";


       const multicast = {
         tokens,
         notification: {
           title: "New chat message",
           body,
         },
         data: {
           type: "CHAT_MESSAGE",
           chatId: chatRef.id,
           senderId,
         },
         // optional webpush click action (works even if your localhost port changes)
         webpush: {
           fcmOptions: {
             // Your web client code should handle location.openURL if desired
             link: "/", // safe default; your app can route to inbox then open the chat
           },
         },
       };


       const res = await messaging.sendEachForMulticast(multicast);


       // --- Clean up invalid tokens (your requested block) ---
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
       // ------------------------------------------------------


       console.log(
         `✅ Sent to ${tokens.length} token(s) →`,
         msgRef.path
       );
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
