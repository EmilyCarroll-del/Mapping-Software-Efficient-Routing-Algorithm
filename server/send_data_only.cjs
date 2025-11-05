const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccount.json');

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: serviceAccount.project_id,
  });
}

const token = process.argv[2];

(async () => {
  try {
    // DATA-ONLY: your SW's onBackgroundMessage will show a notification
    const res = await admin.messaging().send({
      token,
      data: {
        title: 'GraphGo',
        body: 'Background SW test (data-only)',
        type: 'CHAT_MESSAGE',
      },
    });
    console.log('Sent:', res);
  } catch (e) {
    console.error('Failed:', e);
  } finally {
    process.exit(0);
  }
})();
