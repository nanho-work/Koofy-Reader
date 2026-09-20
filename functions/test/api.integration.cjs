const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const base = 'http://127.0.0.1:5001/demo-koofy-reader/asia-northeast3/';
function token(project = 'slimestrikeforce', superAdmin = true) {
  const now = Math.floor(Date.now() / 1000);
  const encode = data => Buffer.from(JSON.stringify(data)).toString('base64url');
  return `${encode({ alg: 'none', typ: 'JWT' })}.${encode({ iss: `https://securetoken.google.com/${project}`, aud: project, sub: 'test-admin', user_id: 'test-admin', iat: now, auth_time: now, exp: now + 3600, firebase: { sign_in_provider: 'custom', identities: {} }, superAdmin })}.`;
}
async function api(action, input = {}, jwt = token()) {
  const response = await fetch(base + 'readerAdmin', { method: 'POST', headers: { 'Content-Type': 'application/json', ...(jwt ? { Authorization: `Bearer ${jwt}` } : {}) }, body: JSON.stringify({ action, ...input }) });
  return { status: response.status, body: await response.json() };
}
test('HTTP API rejects unsigned outsiders and enforces trusted issuer + exact superAdmin', async () => {
  assert.equal((await api('create', {}, '')).status, 401);
  assert.equal((await api('create', {}, token('koofy-reader'))).status, 401);
  assert.equal((await api('create', {}, token('slimestrikeforce', false))).status, 403);
  const cors = await fetch(base + 'readerAdmin?kind=book', { headers: { Origin: 'https://untrusted.example', Authorization: `Bearer ${token()}` } });
  assert.equal(cors.status, 403);
});
test('draft upload, publish, edit isolation, optimistic conflict and unpublish work through Firestore', async () => {
  const created = await api('create', { kind: 'font', metadata: { title: 'Integration font', author: 'Test', description: '', license: 'Test fixture only' } });
  assert.equal(created.status, 201, JSON.stringify(created.body));
  let item = created.body;
  let response = await fetch(base + 'readerCatalog?kind=font');
  assert.equal((await response.json()).items.length, 0);
  const fontCatalog = JSON.parse(readFileSync('assets/fonts/catalog.json', 'utf8'));
  const bytes = readFileSync('assets/fonts/' + fontCatalog.families[0].faces[0].file);
  response = await fetch(base + `readerAdmin?action=upload&id=${item.id}&revision=${item.revision}&slot=font300`, { method: 'POST', headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/octet-stream' }, body: bytes });
  const uploaded = await response.json(); assert.equal(response.status, 200, JSON.stringify(uploaded)); item = uploaded;
  const simultaneous = await Promise.all(['font300', 'font700'].map(async slot => {
    const result = await fetch(base + `readerAdmin?action=upload&id=${item.id}&revision=${item.revision}&slot=${slot}`, { method: 'POST', headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/octet-stream' }, body: bytes });
    return { status: result.status, body: await result.json() };
  }));
  assert.deepEqual(simultaneous.map(result => result.status).sort(), [200, 409]);
  item = simultaneous.find(result => result.status === 200).body;
  const published = await api('publish', { id: item.id, revision: item.revision }); assert.equal(published.status, 200); item = published.body;
  response = await fetch(base + 'readerCatalog?kind=font');
  const visible = (await response.json()).items[0]; assert.equal(visible.title, 'Integration font'); assert.equal('path' in visible.assets.font300, false);
  const saved = await api('save', { id: item.id, revision: item.revision, metadata: { title: 'Unpublished draft title', author: 'Test', description: '', license: 'Test only' } }); assert.equal(saved.status, 200);
  assert.equal((await api('unpublish', { id: item.id, revision: item.revision })).status, 409);
  response = await fetch(base + 'readerCatalog?kind=font'); assert.equal((await response.json()).items[0].title, 'Integration font');
  response = await fetch(base + `readerCatalog?action=download&id=${item.id}&slot=font300&version=999`); assert.equal(response.status, 409);
  response = await fetch(base + `readerCatalog?action=download&id=${item.id}&slot=../../other&version=${visible.version}`); assert.equal(response.status, 400);
  response = await fetch(base + `readerCatalog?action=download&id=${item.id}&slot=font300&version=${visible.version}`);
  assert.equal(response.status, 200);
  const download = await response.json();
  assert.equal(download.sha256, visible.assets.font300.sha256);
  assert.equal(download.url, 'https://storage.googleapis.com/emulator-only/' + encodeURIComponent(item.publishedContent.assets.font300.path));
  item = saved.body;
  const hidden = await api('unpublish', { id: item.id, revision: item.revision }); assert.equal(hidden.status, 200);
  response = await fetch(base + `readerCatalog?action=download&id=${item.id}&slot=font300&version=${visible.version}`); assert.equal(response.status, 404);
  response = await fetch(base + 'readerCatalog?kind=font'); assert.equal((await response.json()).items.length, 0);
});
test('direct anonymous database and storage access are denied', async () => {
  const database = await fetch('http://127.0.0.1:8080/v1/projects/demo-koofy-reader/databases/(default)/documents/readerContent');
  assert.equal(database.status, 403);
  const dbWrite = await fetch('http://127.0.0.1:8080/v1/projects/demo-koofy-reader/databases/(default)/documents/readerContent?documentId=unauthorized', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ fields: {} }) });
  assert.equal(dbWrite.status, 403);
  const files = await fetch('http://127.0.0.1:9199/v0/b/koofy-reader.firebasestorage.app/o');
  assert.equal(files.status, 403);
  const write = await fetch('http://127.0.0.1:9199/v0/b/koofy-reader.firebasestorage.app/o?uploadType=media&name=unauthorized.otf', { method: 'POST', headers: { 'Content-Type': 'application/octet-stream' }, body: 'blocked' });
  assert.equal(write.status, 403);
});
