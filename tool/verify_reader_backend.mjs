// Read-only production checks; never creates or publishes test content.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
const base = 'https://asia-northeast3-koofy-reader.cloudfunctions.net/';
const origin = 'https://admin.koofy.co.kr';
const fetchTimed = (url, options = {}) => fetch(url, { ...options, signal: AbortSignal.timeout(60000) });
let verifiedAssets = 0;
for (const kind of ['book', 'font']) {
  const response = await fetchTimed(`${base}readerCatalog?kind=${kind}${kind === 'book' ? '&supportsTxt=1' : ''}`);
  assert.equal(response.status, 200, `${kind} catalog must return 200`);
  const catalog = await response.json();
  assert(Array.isArray(catalog.items));
  assert(catalog.nextCursor === null || typeof catalog.nextCursor === 'string');
  console.log(`PASS ${kind} catalog (${catalog.items.length} published items on first page)`);
  if (process.argv.includes('--assets') && catalog.items.length) {
    const item = catalog.items[0];
    for (const [slot, asset] of Object.entries(item.assets)) {
      assert(!Object.hasOwn(asset, 'path'), 'Public response must not expose private object paths');
      const query = new URLSearchParams({action: 'download', id: item.id, version: String(item.version), slot});
      const signed = await fetchTimed(`${base}readerCatalog?${query}`);
      assert.equal(signed.status, 200, 'Signing must succeed');
      const data = await signed.json();
      assert.equal(data.sha256, asset.sha256);
      assert.equal(data.size, asset.size);
      const url = new URL(data.url);
      assert(url.protocol === 'https:' && (url.hostname === 'storage.googleapis.com' || url.hostname.endsWith('.storage.googleapis.com')));
      const download = await fetchTimed(url, {redirect: 'error'});
      assert.equal(download.status, 200, 'Signed object must be readable');
      let size = 0; const hash = createHash('sha256');
      for await (const chunk of download.body) {
        size += chunk.length;
        assert(size <= asset.size && size <= 20 * 1024 * 1024, 'Download exceeded declared size');
        hash.update(chunk);
      }
      assert.equal(size, asset.size); assert.equal(hash.digest('hex'), asset.sha256);
      verifiedAssets++;
    }
  }
}
const denied = await fetchTimed(`${base}readerAdmin?kind=book`, {headers: {Origin: origin}});
assert.equal(denied.status, 401, 'Unauthenticated admin must be rejected by the application');
assert.equal(denied.headers.get('access-control-allow-origin'), origin);
assert.equal(typeof (await denied.json()).error, 'string');
console.log('PASS admin denies unauthenticated access; production CORS is configured');
const preflight = await fetchTimed(`${base}readerAdmin`, {method: 'OPTIONS', headers: {
  Origin: origin, 'Access-Control-Request-Method': 'POST', 'Access-Control-Request-Headers': 'authorization,content-type',
}});
assert.equal(preflight.status, 204);
assert.equal(preflight.headers.get('access-control-allow-origin'), origin);
assert(preflight.headers.get('access-control-allow-headers').toLowerCase().includes('authorization'));
console.log('PASS admin upload preflight');
const otherOrigin = await fetchTimed(`${base}readerAdmin?kind=book`, {headers: {Origin: 'https://untrusted.example'}});
assert.equal(otherOrigin.status, 403);
console.log('PASS unapproved browser origin rejected');
if (process.argv.includes('--assets')) console.log(verifiedAssets ? `PASS ${verifiedAssets} signed downloads verified` : 'PENDING signed downloads: no published content yet');
