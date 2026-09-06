const fs = require('fs');
const https = require('https');
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
})().catch(e => { console.error('FATAL', e); process.exit(1); });
