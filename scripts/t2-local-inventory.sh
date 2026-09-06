#!/usr/bin/env bash
# T2a: local credential/agent inventory on hosted runner (own VM, public-knowledge layer).
set -u
mkdir -p reports

echo "== identity & sudo"
id
sudo -n true 2>/dev/null && echo "passwordless sudo: YES" || echo "passwordless sudo: NO"

echo "== agent dir"
ls -la /home/runner/actions-runner/ 2>/dev/null | head -25 || echo "no /home/runner/actions-runner"

for f in .runner .credentials .credentials_rsajs; do
  FP="/home/runner/actions-runner/$f"
  if sudo test -f "$FP" 2>/dev/null || test -f "$FP"; then
    echo "--- $f (values redacted to prefix) ---"
    sudo cat "$FP" 2>/dev/null | python3 -c "
import json,sys
raw=sys.stdin.read()
try:
    d=json.loads(raw)
    def red(v):
        s=str(v)
        return (s[:6]+'...len'+str(len(s))) if len(s)>12 else v
    print(json.dumps({k:red(x) for k,x in d.items()}, indent=1)[:600])
except Exception:
    print(raw[:200].replace(chr(10),' ') + ' ...')
" || true
  else
    echo "--- $f: NOT FOUND"
  fi
done

echo "== runner processes"
ps aux 2>/dev/null | grep -iE 'Runner|Worker|AgentService' | grep -v grep | head -10

echo "== listening sockets"
ss -tlnp 2>/dev/null | head -12 || netstat -tlnp 2>/dev/null | head -12

echo "== GITHUB_/RUNNER_ env (no secrets)"
env | grep -E '^(GITHUB_|RUNNER_|CORVUS)' | grep -viE 'token|secret|key' | sort | head -25

echo "== IMDS reachability probe (status code only, no data)"
curl -sS -m 3 -o /dev/null -w "IMDS http: %{http_code}\n" -H 'Metadata:true' 'http://169.254.169.254/metadata/instance?api-version=2021-02-01' 2>/dev/null || echo "IMDS: unreachable"
echo "T2a DONE"
