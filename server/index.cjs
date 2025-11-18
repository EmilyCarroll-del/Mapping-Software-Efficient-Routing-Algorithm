// server/index.cjs
// Run with: node server/index.cjs

// ---------------- Core imports ----------------
const path = require('path');
const express = require('express');
const cors = require('cors');
const axios = require('axios');
require('dotenv').config({ path: path.resolve(__dirname, '.env') });

// ---------------- Firebase Admin ----------------
const admin = require('firebase-admin');

// service account must exist at server/serviceAccount.json
const serviceAccountPath = path.resolve(__dirname, 'serviceAccount.json');
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

// ---------------- Express app ----------------
const app = express();
app.use(cors());
app.use(express.json());

// Health check
app.get('/health', (_req, res) => res.json({ ok: true }));

// Debug endpoint to check API key (remove in production)
app.get('/debug/key', (_req, res) => {
  const hasKey = !!process.env.PLACES_API_KEY;
  const keyLength = process.env.PLACES_API_KEY ? process.env.PLACES_API_KEY.length : 0;
  const keyPreview = process.env.PLACES_API_KEY 
    ? process.env.PLACES_API_KEY.substring(0, 10) + '...' 
    : 'NOT SET';
  res.json({ 
    hasKey, 
    keyLength, 
    keyPreview,
    message: hasKey ? 'API key is loaded' : 'API key is NOT loaded - check .env file'
  });
});

// Test endpoint to directly test the API key with Google
app.get('/debug/test-api', async (_req, res) => {
  if (!process.env.PLACES_API_KEY) {
    return res.status(500).json({ 
      error: 'PLACES_API_KEY not set',
      message: 'Check your .env file'
    });
  }

  try {
    // Test with a simple autocomplete request
    const testParams = {
      input: 'New York',
      key: process.env.PLACES_API_KEY,
      types: 'geocode', // Same as production - includes addresses and establishments
    };

    console.log('🧪 Testing API key directly with Google...');
    console.log(`   Key: ${process.env.PLACES_API_KEY.substring(0, 15)}...`);
    
    const response = await axios.get('https://maps.googleapis.com/maps/api/place/autocomplete/json', { 
      params: testParams,
      // Explicitly remove any referrer headers
      headers: {
        'Referer': undefined
      }
    });

    const result = {
      status: response.data.status,
      error_message: response.data.error_message,
      predictions_count: response.data.predictions?.length || 0,
      success: response.data.status === 'OK',
      full_response: response.data
    };

    if (response.data.status !== 'OK') {
      console.error(`❌ API test failed: ${response.data.status}`);
      console.error(`   Error: ${response.data.error_message || 'No error message'}`);
      
      if (response.data.status === 'REQUEST_DENIED') {
        result.troubleshooting = [
          '1. Go to Google Cloud Console → APIs & Services → Credentials',
          '2. Click on your API key',
          '3. Under "Application restrictions", make sure it says "None" (not "IP addresses" or "HTTP referrers")',
          '4. Under "API restrictions", set to "Restrict key" and select only "Places API"',
          '5. Save and wait 5-10 minutes for changes to propagate',
          '6. If still not working, create a BRAND NEW API key with no restrictions first, test it, then add API restrictions'
        ];
      }
    } else {
      console.log(`✅ API test successful! Got ${response.data.predictions?.length || 0} predictions`);
    }

    return res.json(result);
  } catch (error) {
    console.error('❌ Exception testing API:', error.message);
    return res.status(500).json({
      error: 'Exception occurred',
      message: error.message,
      stack: error.stack
    });
  }
});

// ------------- Google Places PROXY endpoints -------------
// These avoid CORS/referrer issues and keep your key off the client.
app.get('/places/autocomplete', async (req, res) => {
  try {
    const { input, sessiontoken, country } = req.query;

    if (!process.env.PLACES_API_KEY) {
      console.error('❌ PLACES_API_KEY is not set in environment variables');
      console.error('   Make sure you have a .env file in the server directory with:');
      console.error('   PLACES_API_KEY=your_key_here');
      return res.status(500).json({ status: 'ERROR', message: 'PLACES_API_KEY missing on server' });
    }
    
    console.log(`🔍 Autocomplete request: input="${input}", country="${country}"`);
    console.log(`   Using API key: ${process.env.PLACES_API_KEY.substring(0, 10)}...`);
    if (!input) {
      return res.status(400).json({ status: 'ERROR', message: 'Missing query param: input' });
    }

    const params = {
      input,
      key: process.env.PLACES_API_KEY,
      sessiontoken,
      // Remove type restriction to search for all places (addresses, establishments, etc.)
      // This allows searching for businesses, landmarks, and addresses like Google Maps
    };
    // Make country restriction optional - only apply if explicitly requested
    // This allows finding places that might not be strictly in the specified country
    if (country && country !== 'none') {
      params.components = `country:${country}`;
    }

    const r = await axios.get('https://maps.googleapis.com/maps/api/place/autocomplete/json', { params });
    
    // Log the response status for debugging
    if (r.data.status !== 'OK') {
      console.error(`❌ Google Places API error: ${r.data.status}`);
      console.error(`   Error message: ${r.data.error_message || 'No error message'}`);
      if (r.data.status === 'REQUEST_DENIED') {
        console.error('   ⚠️  This usually means:');
        console.error('      1. API key restrictions are still blocking the request');
        console.error('      2. Places API is not enabled for this project');
        console.error('      3. API key is invalid or expired');
      }
    } else {
      console.log(`✅ Got ${r.data.predictions?.length || 0} predictions`);
    }
    
    return res.status(r.status).json(r.data);
  } catch (e) {
    console.error('❌ Exception in /places/autocomplete:', e.message);
    return res.status(500).json({ status: 'ERROR', message: e.message || String(e) });
  }
});

app.get('/places/details', async (req, res) => {
  try {
    const { place_id, sessiontoken } = req.query;

    if (!process.env.PLACES_API_KEY) {
      return res.status(500).json({ status: 'ERROR', message: 'PLACES_API_KEY missing on server' });
    }
    if (!place_id) {
      return res.status(400).json({ status: 'ERROR', message: 'Missing query param: place_id' });
    }

    const params = {
      place_id,
      key: process.env.PLACES_API_KEY,
      sessiontoken,
      fields: 'formatted_address,geometry,address_components,name,vicinity,plus_code',
    };

    const r = await axios.get('https://maps.googleapis.com/maps/api/place/details/json', { params });
    return res.status(r.status).json(r.data);
  } catch (e) {
    return res.status(500).json({ status: 'ERROR', message: e.message || String(e) });
  }
});

// ---------------- Chat notifications listener ----------------
console.log('🔥 notifier listening for new chat messages…');

// Only notify for docs created AFTER this process starts
const SERVER_STARTED_AT = admin.firestore.Timestamp.now();

// Small de-dupe for reconnects
const processed = new Set();
const MAX_SEEN = 500;
function remember(id) {
  processed.add(id);
  if (processed.size > MAX_SEEN) processed.delete(processed.values().next().value);
}
function getOtherParticipants(usersArr, senderId) {
  return Array.isArray(usersArr) ? usersArr.filter((u) => u !== senderId) : [];
}

db.collectionGroup('messages').onSnapshot(
  async (snap) => {
    for (const change of snap.docChanges()) {
      try {
        if (change.type !== 'added') continue;

        const msgRef = change.doc.ref;
        const msgId = change.doc.id;

        // Skip messages created before listener started
        const createdAt = change.doc.createTime;
        if (createdAt && createdAt.toMillis() <= SERVER_STARTED_AT.toMillis()) continue;
        if (processed.has(msgId)) continue;

        const data = change.doc.data() || {};
        const senderId = (data.senderId || '').toString();
        const text = (data.message || '').toString();

        // parent chat (/chats/{chatId})
        const chatRef = msgRef.parent.parent;
        if (!chatRef) { remember(msgId); continue; }

        const chatSnap = await chatRef.get();
        if (!chatSnap.exists) { remember(msgId); continue; }

        const chat = chatSnap.data() || {};
        const recipients = getOtherParticipants(chat.users, senderId);
        if (recipients.length === 0) { remember(msgId); continue; }

        // Look up recipient tokens
        const userDocs = await Promise.all(
          recipients.map((uid) => db.collection('users').doc(uid).get())
        );
        const tokens = userDocs
          .map((d) => (d.exists ? d.data().fcmToken : null))
          .filter((t) => typeof t === 'string' && t.length > 0);

        if (tokens.length === 0) { remember(msgId); continue; }

        // Fetch sender's display name (fallbacks)
        let senderName = 'Someone';
        try {
          const senderDoc = await db.collection('users').doc(senderId).get();
          const u = senderDoc.exists ? (senderDoc.data() || {}) : {};
          senderName = u.displayName || u.name || u.email || 'Someone';
        } catch {}

        // Build payload
        const title = `${senderName} sent you a message`;
        const body = text ? (text.length > 80 ? text.slice(0, 80) + '…' : text) : 'New message';

        const multicast = {
          tokens,
          data: {
            type: 'CHAT_MESSAGE',
            chatId: chatRef.id,
            senderId,
            title,
            body,
          },
          webpush: { fcmOptions: { link: '/' } },
          android: { priority: 'high' },
          apns: { headers: { 'apns-priority': '10' } },
        };

        const res = await messaging.sendEachForMulticast(multicast);

        // Clean up invalid tokens
        const failedTokens = [];
        res.responses.forEach((r, i) => {
          if (!r.success) {
            const code = r.error?.code || '';
            if (code.includes('registration-token-not-registered')) {
              failedTokens.push(tokens[i]);
            }
          }
        });

        if (failedTokens.length > 0) {
          console.log('🧹 Removing invalid tokens:', failedTokens);
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
        remember(msgId);
      } catch (err) {
        console.error('Listener error while processing a message change:', err);
      }
    }
  },
  (err) => {
    console.error('Listener error:', err);
    process.exitCode = 1;
  }
);

// ---------------- Start server ----------------
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Notifier + Places proxy on http://localhost:${PORT}`);
});
