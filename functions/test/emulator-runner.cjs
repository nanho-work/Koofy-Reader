// Exercise actual onRequest handlers with emulated Firestore/Storage, without
// depending on the globally installed Functions emulator runtime version.
const { before, after, mock } = require('node:test');
const express = require('express');
const path = require('node:path');
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) throw new Error('Local Firestore and Storage emulators are required.');
process.env.GCLOUD_PROJECT = 'demo-koofy-reader';
process.env.READER_ADMIN_ORIGINS = 'http://localhost:3000,https://admin.koofy.co.kr';
process.chdir(path.resolve(__dirname, '../..'));
// Signing is an IAM integration tested only after cloud deployment.
const { File } = require('@google-cloud/storage');
mock.method(File.prototype, 'getSignedUrl', async function () { return ['https://storage.googleapis.com/emulator-only/' + encodeURIComponent(this.name)]; });
const { readerAdmin, readerCatalog } = require('../lib/src/index.js');
const app = express();
app.use(express.raw({ type: () => true, limit: '25mb' }));
app.use((req, res, next) => {
  req.rawBody = Buffer.isBuffer(req.body) ? req.body : Buffer.alloc(0);
  if (req.is('application/json')) req.body = JSON.parse(req.rawBody.toString());
  next();
});
app.all('/demo-koofy-reader/asia-northeast3/readerAdmin', readerAdmin);
app.all('/demo-koofy-reader/asia-northeast3/readerCatalog', readerCatalog);
let server;
before(async () => {
  const { getApp } = require('firebase-admin/app');
  const { getAuth } = require('firebase-admin/auth');
  await getAuth(getApp('existing-admin-identity')).createUser({ uid: 'test-admin' });
  await new Promise(resolve => { server = app.listen(5001, '127.0.0.1', resolve); });
});
after(async () => { await new Promise(resolve => server.close(resolve)); });
require('./api.integration.cjs');
