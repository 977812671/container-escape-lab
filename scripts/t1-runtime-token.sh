#!/usr/bin/env bash
# T1: ACTIONS_RUNTIME_TOKEN scope analysis + cache/artifact API cross-repo oracle.
set -u
mkdir -p reports

echo "== runtime env vars"
env | grep -E '^ACTIONS_' | sed -E 's/(TOKEN=).{24,}/\1<redacted>/' | sort

RT="${ACTIONS_RUNTIME_TOKEN:-}"
CACHE_URL="${ACTIONS_CACHE_URL:-}"
RESULTS_URL="${ACTIONS_RESULTS_URL:-}"
RUNTIME_URL="${ACTIONS_RUNTIME_URL:-}"
echo "CACHE_URL=$CACHE_URL"
echo "RESULTS_URL=$RESULTS_URL"
echo "RUNTIME_URL=$RUNTIME_URL"

echo "== runtime token JWT payload"
python3 - "$RT" <<'EOF'
import base64, json, sys
try:
    tok = sys.argv[1]
    p = tok.split('.')[1]
    p += '=' * (-len(p) % 4)
    print(json.dumps(json.loads(base64.urlsafe_b64decode(p)), indent=1, sort_keys=True))
except Exception as e:
    print('decode error:', e)
EOF

code() { curl -sS -m 20 -o /tmp/body.out -w "%{http_code}" -H "Authorization: Bearer $RT" "$@"; }

echo "== [A-baseline] own cache reserve/upload/commit/get"
VER_A="deadbeef$(printf 'a%.0s' $(seq 1 56))"
KEY_A="cross-a-${GITHUB_RUN_ID}"
BODY="{\"key\":\"$KEY_A\",\"version\":\"$VER_A\",\"size\":13}"
C=$(code -X POST -H 'Content-Type: application/json' -d "$BODY" "${CACHE_URL}_apis/artifactcache/caches")
echo "reserve own cache: $C"; head -c 200 /tmp/body.out; echo
UP=$(python3 -c "import json;print(json.load(open('/tmp/body.out')).get('signedUploadUrl',''))" 2>/dev/null)
CID=$(python3 -c "import json;print(json.load(open('/tmp/body.out')).get('cacheId',''))" 2>/dev/null)
if [ -n "$UP" ]; then
  printf 'seed-data-a-13' > /tmp/blob.bin
  echo "upload blob: $(curl -sS -m 20 -o /dev/null -w '%{http_code}' -X PUT --upload-file /tmp/blob.bin "$UP")"
  echo "commit own cache: $(curl -sS -m 20 -o /dev/null -w '%{http_code}' -X PATCH -H 'Content-Type: application/json' -d '{"size":13}' "${CACHE_URL}_apis/artifactcache/caches/$CID")"
fi
C=$(code "${CACHE_URL}_apis/artifactcache/cache?keys=$KEY_A&version=$VER_A")
echo "GET own cache: $C"
C=$(code "${CACHE_URL}_apis/artifactcache/cache?keys=nope-nonexist&version=$VER_A")
echo "GET nonexistent cache (baseline negative): $C"

echo "== [T1-cross] own token probing CROSS-REPO cache"
C=$(code "${CACHE_URL}_apis/artifactcache/cache?keys=${B_KEY}&version=${B_VER}")
echo "GET cross-repo cache key=$B_KEY: $C   <-- 404/403=isolated, 200=HIGH FINDING"

echo "== [A-baseline] own run artifacts via results API"
SELF_RUN="$GITHUB_RUN_ID"
for path in \
  "_apis/pipelines/workflowruns/$SELF_RUN/artifacts?api-version=6.0-preview" \
  "_apis/pipelines/1/workflowruns/$SELF_RUN/artifacts?api-version=6.0-preview"; do
  C=$(code "${RESULTS_URL}${path}")
  echo "GET own artifacts ($path): $C"; head -c 200 /tmp/body.out; echo
done

echo "== [T1-cross] own token probing CROSS-REPO run artifacts (run_id=$B_RUN_ID)"
for path in \
  "_apis/pipelines/workflowruns/$B_RUN_ID/artifacts?api-version=6.0-preview" \
  "_apis/pipelines/1/workflowruns/$B_RUN_ID/artifacts?api-version=6.0-preview"; do
  C=$(code "${RESULTS_URL}${path}")
  echo "GET cross-repo run artifacts ($path): $C   <-- 404/403=isolated, 200=HIGH FINDING"
  head -c 200 /tmp/body.out; echo
done

echo "== [T1-scope] runtime token against other surfaces"
echo "api.github.com/user: $(curl -sS -m 20 -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $RT" https://api.github.com/user)"
C=$(code "${RUNTIME_URL}_apis/distributedtask/pools?api-version=6.0-preview" 2>/dev/null)
echo "runtime_url distributedtask pools: ${C:-n/a}"
echo "T1 DONE"
