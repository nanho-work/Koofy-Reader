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
  assert(visible.preview && visible.preview.extension === 'png');
  assert.equal('path' in visible.preview, false);
  assert.equal('preview' in visible.assets, false);
  const previewResponse = await fetch(base + `readerCatalog?action=download&id=${item.id}&slot=preview&version=${visible.version}`);
  assert.equal(previewResponse.status, 200);
  const previewDownload = await previewResponse.json();
  assert.equal(previewDownload.sha256, visible.preview.sha256);
  assert.equal(previewDownload.url, 'https://storage.googleapis.com/emulator-only/' + encodeURIComponent(item.publishedContent.preview.path));
  assert.equal(download.sha256, visible.assets.font300.sha256);
  assert.equal(download.url, 'https://storage.googleapis.com/emulator-only/' + encodeURIComponent(item.publishedContent.assets.font300.path));
  item = saved.body;
  const republished = await api('publish', { id: item.id, revision: item.revision });
  assert.equal(republished.status, 200, JSON.stringify(republished.body));
  item = republished.body;
  assert.notEqual(item.publishedContent.preview.sha256, visible.preview.sha256);
  assert.equal((await fetch(base + `readerCatalog?action=download&id=${item.id}&slot=preview&version=${visible.version}`)).status, 409);
  const hidden = await api('unpublish', { id: item.id, revision: item.revision }); assert.equal(hidden.status, 200);
  response = await fetch(base + `readerCatalog?action=download&id=${item.id}&slot=font300&version=${visible.version}`); assert.equal(response.status, 404);
  response = await fetch(base + 'readerCatalog?kind=font'); assert.equal((await response.json()).items.length, 0);
  assert.equal((await fetch(base + `readerCatalog?action=download&id=${item.id}&slot=preview&version=${item.publishedContent.version}`)).status, 404);
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

test('TXT upload, format replacement, publishing and legacy catalog compatibility', async () => {
  const sharp = require('sharp');
  const { createHash } = require('node:crypto');
  const { getStorage } = require('firebase-admin/storage');
  const created = await api('create', { kind: 'book', metadata: { title: 'TXT integration', author: 'Test', description: '', license: 'Test fixture only' } });
  assert.equal(created.status, 201);
  let item = created.body;
  async function upload(slot, bytes, status = 200) {
    const response = await fetch(base + `readerAdmin?action=upload&id=${item.id}&revision=${item.revision}&slot=${slot}`, {
      method: 'POST', headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/octet-stream' }, body: bytes,
    });
    const body = await response.json();
    assert.equal(response.status, status, JSON.stringify(body));
    if (status === 200) item = body;
  }
  await upload('epub', readFileSync('functions/test/fixtures/valid.epub'));
  await upload('cover', await sharp({ create: { width: 10, height: 15, channels: 3, background: '#f7f5ee' } }).png().toBuffer());
  let published = await api('publish', { id: item.id, revision: item.revision });
  assert.equal(published.status, 200); item = published.body;
  const originalEpub = item.publishedContent.assets.epub;
  await upload('txt', Buffer.from('\ufeff등록한 텍스트\r\n둘째 줄'));
  assert.equal(item.assets.epub, undefined);
  assert.equal(item.assets.txt.extension, 'txt');
  assert.equal(item.publishedContent.assets.epub.path, originalEpub.path);
  const stored = (await getStorage().bucket().file(item.assets.txt.path).download())[0];
  assert.equal(stored.toString('utf8'), '등록한 텍스트\n둘째 줄');
  assert.equal(item.assets.txt.sha256, createHash('sha256').update(stored).digest('hex'));
  const revision = item.revision;
  await upload('txt', Buffer.from('invalid\x00'), 400);
  assert.equal(item.revision, revision);
  let catalog = await (await fetch(base + 'readerCatalog?kind=book')).json();
  assert(catalog.items.some(book => book.id === item.id && book.assets.epub));
  published = await api('publish', { id: item.id, revision: item.revision });
  assert.equal(published.status, 200); item = published.body;
  catalog = await (await fetch(base + 'readerCatalog?kind=book')).json();
  assert(!catalog.items.some(book => book.id === item.id));
  catalog = await (await fetch(base + 'readerCatalog?kind=book&supportsTxt=1')).json();
  const visible = catalog.items.find(book => book.id === item.id);
  assert.equal(visible.assets.txt.extension, 'txt');
  assert.equal(visible.assets.epub, undefined);
  assert.equal('path' in visible.assets.txt, false);
  const download = await fetch(base + `readerCatalog?action=download&id=${item.id}&slot=txt&version=${visible.version}`);
  assert.equal(download.status, 200);
  assert.equal((await download.json()).sha256, item.assets.txt.sha256);
  assert.equal((await fetch(base + `readerCatalog?action=download&id=${item.id}&slot=epub&version=${visible.version}`)).status, 400);
});

test('delete blocks downloads, removes all versions and safely retries books and fonts', async t => {
  const { getFirestore } = require('firebase-admin/firestore');
  const { getStorage } = require('firebase-admin/storage');
  const { Bucket } = require('@google-cloud/storage');
  const bucket = getStorage().bucket();
  for (const kind of ['book', 'font']) {
    const { body: item } = await api('create', { kind, metadata: { title: `Delete ${kind}`, author: 'Test', description: '', license: 'Test only' } });
    const prefix = `readerContent/${item.id}/`, neighbor = `readerContent/${item.id}0/keep.txt`;
    await Promise.all(['old/file', 'current/file', 'draft/file'].map(name => bucket.file(prefix + name).save('fixture')));
    await bucket.file(neighbor).save('keep');
    const ref = getFirestore().collection('readerContent').doc(item.id);
    await ref.update({ published: true, publishedContent: { title: item.title, author: 'Test', description: '', license: 'Test', version: 1, assets: {} } });
    assert.equal((await api('delete', { id: item.id, revision: 99 })).status, 409);
    assert.equal((await api('delete', { id: item.id, revision: 1 }, token('slimestrikeforce', false))).status, 403);
    assert.equal((await bucket.getFiles({ prefix }))[0].length, 3);
    const failure = t.mock.method(Bucket.prototype, 'deleteFiles', async () => { throw new Error('simulated storage failure'); });
    const failed = await api('delete', { id: item.id, revision: 1 });
    failure.mock.restore();
    assert.equal(failed.status, 503);
    const pending = (await ref.get()).data();
    assert.equal(pending.deleting, true);
    assert.equal(pending.published, false);
    assert.equal((await api('publish', { id: item.id, revision: pending.revision })).status, 409);
    const upload = await fetch(base + `readerAdmin?action=upload&id=${item.id}&revision=${pending.revision}&slot=txt`, { method: 'POST', headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/octet-stream' }, body: 'blocked' });
    assert.equal(upload.status, 409);
    const catalog = await (await fetch(base + `readerCatalog?kind=${kind}&supportsTxt=1`)).json();
    assert(!catalog.items.some(value => value.id === item.id));
    assert.equal((await fetch(base + `readerCatalog?action=download&id=${item.id}&version=1&slot=txt`)).status, 404);
    const deleted = await api('delete', { id: item.id, revision: 1 });
    assert.equal(deleted.status, 200, JSON.stringify(deleted.body));
    assert.equal(deleted.body.deleted, true);
    assert.equal((await ref.get()).exists, false);
    assert.equal((await bucket.getFiles({ prefix }))[0].length, 0);
    assert.equal((await bucket.file(neighbor).exists())[0], true);
    assert.equal((await api('delete', { id: item.id, revision: 1 })).status, 200);
    const audit = await getFirestore().collection('readerAudit').where('contentId', '==', item.id).get();
    assert(audit.docs.some(doc => doc.data().action === 'deleteCompleted'));
    await bucket.file(neighbor).delete();
  }
});


test('admin categories persist, deduplicate and require super-admin', async () => {
  const url = base + 'readerAdmin?action=categories';
  assert.equal((await fetch(url)).status, 401);
  assert.equal((await api('addCategory', { name: '역사' }, token('slimestrikeforce', false))).status, 403);
  const first = await api('addCategory', { name: '  역사  ' });
  assert.equal(first.status, 200, JSON.stringify(first.body));
  assert(first.body.categories.includes('역사'));
  const second = await api('addCategory', { name: '역사' });
  assert.deepEqual(second.body, first.body);
  assert.equal((await api('addCategory', { name: '' })).status, 400);
  const listed = await (await fetch(url, { headers: { Authorization: `Bearer ${token()}` } })).json();
  assert.deepEqual(listed.categories, first.body.categories);
  const created = await api('create', { kind: 'book', metadata: { title: '역사 이야기', author: 'Test', description: '', license: 'Test only', category: '역사' } });
  assert.equal(created.status, 201);
  assert.equal(created.body.category, '역사');
  const { getFirestore } = require('firebase-admin/firestore');
  await getFirestore().collection('readerSettings').doc('bookCategories').set({ names: Array.from({ length: 96 }, (_, i) => `분류${i}`) });
  assert.equal((await api('addCategory', { name: '초과' })).status, 400);
});
