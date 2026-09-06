#!/usr/bin/env bash
# codespace deep-dive round: VM escape channel + cs-agent intel (own environment only).
OUT=/workspaces/container-escape-lab/codespace-recon4.txt

{
echo "RECON4 START $(date -u +%FT%TZ)"
echo "== [1] container -> VM ssh channel (localhost:2222)"
ls -la ~/.ssh/ 2>/dev/null
echo "-- try ssh vscode@localhost:2222 (BatchMode, key auth):"
ssh -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    vscode@localhost 'echo VM_SSH_OK; hostname; id; uname -a' 2>&1 | head -8

echo "== [2] VM-side enumeration (only if ssh worked)"
ssh -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    vscode@localhost '
echo "-- whoami/host:"; whoami; hostname; uname -a
echo "-- sudo:"; sudo -n true 2>/dev/null && echo "passwordless sudo YES" || echo "sudo NO"
echo "-- processes (github/codespace/agent):"; ps aux | grep -iE "codespace|agent|vscs|cloudenv|dotnet|docker" | grep -v grep | head -15
echo "-- listening ports:"; sudo ss -tlnp 2>/dev/null | head -20
echo "-- docker socket:"; ls -la /var/run/docker.sock 2>/dev/null || echo "no docker.sock"
echo "-- agent binaries:"; ls -d /.codespaces/bin 2>/dev/null && ls /.codespaces/bin | head -5
echo "-- root fs listing:"; sudo ls / 2>/dev/null | head -20
' 2>&1 | head -60

echo "== [3] cs-agent appsettings (in-container mount, secrets redacted)"
for f in appsettings.json appsettings.standalone.json codespaces.runtimeconfig.json version.json codespaces.deps.json; do
  echo "-- bin/$f:"
  cat "/.codespaces/bin/$f" 2>/dev/null | python3 -c "
import sys, json
raw = sys.stdin.read()
try:
    d = json.loads(raw)
    def walk(o, pre=''):
        if isinstance(o, dict):
            for k, v in o.items():
                if isinstance(v, (dict, list)):
                    walk(v, pre + k + '.')
                else:
                    s = str(v)
                    lk = k.lower()
                    if any(x in lk for x in ('token', 'secret', 'password', 'key', 'sig', 'connectionstring', 'sas')):
                        print(pre + k + ' = <REDACTED len=' + str(len(s)) + '>')
                    else:
                        print(pre + k + ' = ' + s[:120])
        elif isinstance(o, list):
            for i, v in enumerate(o[:6]):
                walk(v, pre + '[' + str(i) + '].')
    walk(d)
except Exception:
    print('non-json, head:', raw[:150])
" 2>&1 | head -30
done

echo "== [4] agent dirs of interest"
for d in Ssh UnifiedContainers PrefetchScripts Utilities cache; do
  echo "-- bin/$d:"
  ls "/.codespaces/bin/$d" 2>/dev/null | head -8
done

echo "== [5] VM-hosted gRPC ports deep probe (host network = VM ports)"
curl -sS -m 4 --http2-prior-knowledge -o /tmp/g.out -w "16634 POST: %{http_code}\n" \
  -X POST -H 'Content-Type: application/grpc' http://127.0.0.1:16634/ 2>/dev/null | head -2
head -c 120 /tmp/g.out 2>/dev/null | tr '\n' ' '; echo

echo "== [6] env GITHUB_/INTERNAL (URLs only)"
env | grep -E '^(GITHUB|INTERNAL|CODESPACE)' | grep -viE 'token'

echo "RECON4 DONE $(date -u +%FT%TZ)"
} > "$OUT" 2>&1
exit 0
