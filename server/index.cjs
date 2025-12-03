// server/index.cjs
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
console.log("🔥 notifier listening for order assignments…");

// Only notify for docs created/updated AFTER this process starts
const SERVER_STARTED_AT = admin.firestore.Timestamp.now();

// Small de-dupe for reconnects (for chat messages)
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

// --- generic helper to get participants from different chat doc shapes ---
// - chats/{chatId}:      users: [uid1, uid2]
// - conversations/{id}:  participants: [uid1, uid2]
// - (future) orders:     driverIds + adminId
function getParticipants(chat) {
  if (Array.isArray(chat.users) && chat.users.length > 0) {
    return chat.users;
  }
  if (Array.isArray(chat.participants) && chat.participants.length > 0) {
    return chat.participants;
  }

  const arr = [];
  if (Array.isArray(chat.driverIds)) {
    arr.push(...chat.driverIds);
  }
  if (chat.adminId) {
    arr.push(chat.adminId);
  }
  return arr;
}

// -----------------------------------------------------------------------------
//  CHAT MESSAGE LISTENER (existing behavior, extended for conversations)
// -----------------------------------------------------------------------------
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
      const senderId = String(data.senderId || "");
      const text = String(data.message || "");

      // parent chat (e.g. /chats/{chatId} or /conversations/{conversationId})
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

        const participants = getParticipants(chat);
        const recipients = getOtherParticipants(participants, senderId);
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

        // Sender display name
        let senderName = "Someone";
        try {
          const senderDoc = await db.collection("users").doc(senderId).get();
          const u = senderDoc.exists ? senderDoc.data() || {} : {};
          senderName = u.displayName || u.name || u.email || "Someone";
        } catch (_) {
          // ignore
        }

        const title = `${senderName} sent you a message`;
        const body = text
          ? text.length > 80
            ? text.slice(0, 80) + "…"
            : text
          : "New message";

        const conversationId = chatRef.id;

        // Payload for BOTH web + mobile
        const multicast = {
          tokens,

          notification: {
            title,
            body,
          },

          data: {
            type: "CHAT_MESSAGE", // used by web SW
            mobileType: "chat",   // used by mobile

            chatId: conversationId,
            conversationId: conversationId,
            senderId,
            otherUserId: senderId,
            otherUserName: senderName,

            dataTitle: title,
            dataBody: body,
            isOldFormat: "false",
          },

          webpush: {
            fcmOptions: { link: "/" },
          },

          android: {
            priority: "high",
            notification: {
              priority: "high",
            },
          },

          apns: {
            headers: { "apns-priority": "10" },
            payload: {
              aps: {
                alert: { title, body },
                sound: "default",
              },
            },
          },
        };

        console.log("📤 Sending multicast:", {
          tokensCount: tokens.length,
          to: msgRef.path,
          type: "CHAT_MESSAGE",
        });

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
    console.error("Listener error (messages):", err);
    process.exitCode = 1;
  }
);

// -----------------------------------------------------------------------------
//  ORDER ASSIGNMENT / STATUS PUSHES
//  A) addresses collection  (kept from previous version, now with logs)
//  B) orders collection     (NEW — main source for assignment pushes)
// -----------------------------------------------------------------------------

// ---------- A) ADDRESSES (mostly for extra safety / debugging) ----------

const addressState = new Map(); // key: doc.id, value: { driverId, status }

// Helper to build a human-readable address (matches Dart helper)
function formatAddress(data) {
  const street = (data.streetAddress || "").toString();
  const city = (data.city || "").toString();
  const state = (data.state || "").toString();
  const zip = (data.zipCode || "").toString();
  const full = `${street}, ${city}, ${state} ${zip}`.trim();
  return full === "," ? "this address" : full;
}

db.collection("addresses").onSnapshot(
  async (snap) => {
    for (const change of snap.docChanges()) {
      const doc = change.doc;
      const data = doc.data() || {};

      // Seed on startup without sending notifications
      const updateTime = doc.updateTime || doc.createTime;
      if (
        updateTime &&
        updateTime.toMillis() <= SERVER_STARTED_AT.toMillis() &&
        !addressState.has(doc.id)
      ) {
        addressState.set(doc.id, {
          driverId: data.driverId ? String(data.driverId) : null,
          status: data.status ? String(data.status) : null,
        });
        console.log("🧊 Seed existing address (no notify):", {
          docId: doc.id,
          driverId: data.driverId || null,
          status: data.status || null,
        });
        continue;
      }

      const driverId = data.driverId ? String(data.driverId) : null;
      const status = data.status ? String(data.status) : "assigned";
      const address = formatAddress(data);

      const prev = addressState.get(doc.id) || { driverId: null, status: null };

      console.log("📦 [addresses change]", {
        changeType: change.type,
        docId: doc.id,
        prevDriverId: prev.driverId,
        newDriverId: driverId,
        prevStatus: prev.status,
        newStatus: status,
      });

      addressState.set(doc.id, { driverId, status });

      if (!driverId) {
        console.log("ℹ️ No driverId on address, skipping push:", doc.id);
        continue;
      }

      const isNewAssignment = !prev.driverId && driverId;
      const driverChanged =
        prev.driverId && driverId && prev.driverId !== driverId;
      const statusChanged =
        prev.status && status && prev.status !== status;

      // Only notify when something meaningful changes
      if (!isNewAssignment && !driverChanged && !statusChanged) {
        console.log("ℹ️ No meaningful assignment/status change for", doc.id);
        continue;
      }

      let title;
      let body;
      let orderEvent;

      if (isNewAssignment || driverChanged) {
        title = "New Order Assigned";
        body = `You have been assigned a new order: ${address}`;
        orderEvent = "assignment";
      } else {
        title = "Order Status Updated";
        body = `Order status is now ${status.toUpperCase()} for: ${address}`;
        orderEvent = "status_change";
      }

      console.log("🧮 Prepared order notification (addresses):", {
        docId: doc.id,
        driverId,
        event: orderEvent,
      });

      try {
        // Look up the driver's token
        const userDoc = await db.collection("users").doc(driverId).get();
        if (!userDoc.exists) {
          console.warn("⚠️ Driver user doc not found:", driverId);
          continue;
        }
        const u = userDoc.data() || {};
        const token = u.fcmToken;
        if (!token) {
          console.warn("⚠️ No fcmToken for driver:", driverId);
          continue;
        }

        const tokens = [token];

        const multicast = {
          tokens,

          notification: {
            title,
            body,
          },

          data: {
            type: "assigned_orders", // mobile + NotificationService
            mobileType: "assigned_orders",

            orderId: doc.id,
            orderTitle: address,
            orderStatus: status,
            orderEvent,

            dataTitle: title,
            dataBody: body,
          },

          webpush: {
            fcmOptions: { link: "/" },
          },

          android: {
            priority: "high",
            notification: {
              priority: "high",
            },
          },

          apns: {
            headers: { "apns-priority": "10" },
            payload: {
              aps: {
                alert: { title, body },
                sound: "default",
              },
            },
          },
        };

        console.log("📤 Sending order notification (addresses):", {
          toDriver: driverId,
          orderId: doc.id,
          event: orderEvent,
        });

        const res = await messaging.sendEachForMulticast(multicast);

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
          console.log("🧹 Removing invalid tokens (orders/addresses):", failedTokens);
          const batch = db.batch();
          if (failedTokens.includes(token)) {
            batch.update(userDoc.ref, { fcmToken: FieldValue.delete() });
          }
          await batch.commit();
        }

        console.log(
          `✅ Order push (addresses) sent to driver ${driverId} for address ${doc.id}`
        );
      } catch (err) {
        console.error(
          "Listener error while processing order assignment (addresses)",
          doc.ref.path,
          err
        );
      }
    }
  },
  (err) => {
    console.error("Listener error (addresses):", err);
    process.exitCode = 1;
  }
);

// ---------- B) ORDERS (main driver-assignment push source) ----------

const orderState = new Map(); // key: orderId, value: { driverIds: Set<string>, status: string }

db.collection("orders").onSnapshot(
  async (snap) => {
    for (const change of snap.docChanges()) {
      const doc = change.doc;
      const data = doc.data() || {};

      // Normalize driverIds + status
      const driverIdsArr = Array.isArray(data.driverIds)
        ? data.driverIds.map((d) => String(d))
        : [];
      const status = data.status ? String(data.status) : "assigned";

      const updateTime = doc.updateTime || doc.createTime;
      if (
        updateTime &&
        updateTime.toMillis() <= SERVER_STARTED_AT.toMillis() &&
        !orderState.has(doc.id)
      ) {
        orderState.set(doc.id, {
          driverIds: new Set(driverIdsArr),
          status,
        });
        console.log("🧊 Seed existing order (no notify):", {
          orderId: doc.id,
          driverIds: driverIdsArr,
          status,
        });
        continue;
      }

      const prev = orderState.get(doc.id) || {
        driverIds: new Set(),
        status: null,
      };
      const prevDrivers = prev.driverIds || new Set();

      const newDriversSet = new Set(driverIdsArr);
      orderState.set(doc.id, {
        driverIds: new Set(newDriversSet),
        status,
      });

      // Which drivers are newly added?
      const addedDrivers = driverIdsArr.filter((id) => !prevDrivers.has(id));
      const statusChanged = prev.status && prev.status !== status;

      console.log("📦 [orders change]", {
        changeType: change.type,
        orderId: doc.id,
        prevDrivers: Array.from(prevDrivers),
        newDrivers: driverIdsArr,
        addedDrivers,
        prevStatus: prev.status,
        newStatus: status,
      });

      // If no new drivers and status didn't change, skip
      if (addedDrivers.length === 0 && !statusChanged) {
        console.log("ℹ️ No new drivers or status change for order", doc.id);
        continue;
      }

      // We'll send:
      // - "New Order Assigned" to each newly-added driver
      // - (optionally) a status-change push to existing drivers
      // For now we'll focus on NEW assignments which you asked for.

      const addressSummary =
        (data.addressSummary || data.pickupAddress || data.title || "").toString() ||
        `Order ${doc.id}`;

      // 1. New driver assignments
      for (const driverId of addedDrivers) {
        try {
          const userDoc = await db.collection("users").doc(driverId).get();
          if (!userDoc.exists) {
            console.warn("⚠️ Driver user doc not found (orders):", driverId);
            continue;
          }
          const u = userDoc.data() || {};
          const token = u.fcmToken;
          if (!token) {
            console.warn("⚠️ No fcmToken for driver (orders):", driverId);
            continue;
          }

          const title = "New Order Assigned";
          const body = `You have been assigned a new order: ${addressSummary}`;

          const multicast = {
            tokens: [token],
            notification: { title, body },
            data: {
              type: "assigned_orders",
              mobileType: "assigned_orders",

              orderId: doc.id,
              orderTitle: addressSummary,
              orderStatus: status,
              orderEvent: "assignment",

              dataTitle: title,
              dataBody: body,
            },
            webpush: { fcmOptions: { link: "/" } },
            android: {
              priority: "high",
              notification: { priority: "high" },
            },
            apns: {
              headers: { "apns-priority": "10" },
              payload: {
                aps: {
                  alert: { title, body },
                  sound: "default",
                },
              },
            },
          };

          console.log("📤 Sending order notification (orders):", {
            toDriver: driverId,
            orderId: doc.id,
            event: "assignment",
          });

          const res = await messaging.sendEachForMulticast(multicast);

          const failedTokens = [];
          res.responses.forEach((r, i) => {
            if (!r.success) {
              const code = r.error?.code || "";
              if (code.includes("registration-token-not-registered")) {
                failedTokens.push(multicast.tokens[i]);
              }
            }
          });

          if (failedTokens.length > 0) {
            console.log("🧹 Removing invalid tokens (orders main):", failedTokens);
            const batch = db.batch();
            if (failedTokens.includes(token)) {
              batch.update(userDoc.ref, { fcmToken: FieldValue.delete() });
            }
            await batch.commit();
          }

          console.log(
            `✅ Order push (orders) sent to driver ${driverId} for order ${doc.id}`
          );
        } catch (err) {
          console.error(
            "Listener error while processing order assignment (orders)",
            doc.ref.path,
            err
          );
        }
      }

      // 2. (Optional) status-change pushes could go here if you want them later
    }
  },
  (err) => {
    console.error("Listener error (orders):", err);
    process.exitCode = 1;
  }
);
