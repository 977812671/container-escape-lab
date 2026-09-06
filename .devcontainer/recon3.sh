#!/usr/bin/env bash
# Codespace recon3: secrets layout, cs-agent.sock protocol, agent config/log intel.
OUT=/workspaces/container-escape-lab/codespace-recon3.txt
SH=/workspaces/.codespaces/shared

redact_file() {
  python3 - "$1" <<'EOF'
import sys, json
try:
    raw = open(sys.argv[1], errors='replace').read()
except Exception as e:
    print('read err', e); sys.exit()
lines = raw.splitlines()
for l in lines[:40]:
    if '=' in l and len(l) > 24 and not l.startswith('#'):
        k, _, v = l.partition('=')
        print(f'{k}=<{red if False else "REDACTED len=" + str(len(v))}>')
    else:
        print(l[:160])
EOF
}

json_keys() {
  python3 - "$1" <<'EOF'
import sys, json
try:
    raw = open(sys.argv[1], errors='replace').read()
    d = json.loads(raw)
    def walk(o, pre=''):
        if isinstance(o, dict):
            for k, v in o.items():
                if isinstance(v, (dict, list)):
                    walk(v, pre + k + '.')
                else:
                    s = str(v)
                    lk = k.lower()
                    if any(x in lk for x in ('token', 'secret', 'key', 'password', 'sig')):
                        print(f'{pre}{k} = <REDACTED len={len(s)}>')
                    else:
                        print(f'{pre}{k} = {s[:100]}')
        elif isinstance(o, list):
            for i, v in enumerate(o[:8]):
                walk(v, pre + f'[{i}].')
    walk(d)
except Exception as e:
    print('parse err:', e, '| raw head:', raw[:120])
EOF
}

{
echo "== [A] shared/.env (keys + value lengths only)"
sudo cat $SH/.env 2>/dev/null | redact_file $SH/.env 2>/dev/null || redact_file $SH/.env

echo "== [A2] shared/.env-secrets (key names + lengths only)"
redact_file $SH/.env-secrets

echo "== [A3] shared/.user-secrets.json (key tree, values redacted)"
json_keys $SH/.user-secrets.json

echo "== [A4] user-secrets-envs.json"
json_keys $SH/user-secrets-envs.json

echo "== [A5] environment-variables.json"
json_keys $SH/environment-variables.json

echo "== [A6] read-config.json (endpoints/config, secrets redacted)"
json_keys $SH/read-config.json

echo "== [A7] merged_devcontainer.json + repo_devcontainer.json"
json_keys $SH/merged_devcontainer.json
json_keys /workspaces/.codespaces/.persistedshare/repo_devcontainer.json

echo "== [B] cs-agent.sock protocol probe"
SOCK=$SH/cs-agent.sock
for path in / /health /status /v1/ /api/ /info; do
  C=$(curl -sS -m 4 --unix-socket $SOCK -o /tmp/a.out -w "%{http_code}" "http://localhost$path" 2>/dev/null || echo ERR)
  echo "GET $path: $C :: $(head -c 100 /tmp/a.out 2>/dev/null | tr '\n' ' ')"
done
# HTTP upgrade probe
curl -sS -m 4 --unix-socket $SOCK -o /tmp/a2.out -w "GET / w/ upgrade: %{http_code}\n" \
  -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' -H 'Sec-WebSocket-Version: 13' \
  http://localhost/ 2>/dev/null || true
head -c 150 /tmp/a2.out 2>/dev/null | tr '\n' ' '; echo
ls -la $SOCK

echo "== [C] creation.log architecture intel (redacted)"
redact_file /workspaces/.codespaces/.persistedshare/creation.log | grep -iE 'agent|gateway|endpoint|url|host|token|socket|port|vm|docker' | head -30

echo "== [D] agent bin full inventory"
ls /.codespaces/bin | wc -l
ls /.codespaces/bin | grep -vE '\.dll$' | head -20
echo "-- config/json files:"
find /.codespaces/bin -maxdepth 1 \( -name '*.json' -o -name '*.config' -o -name '*.runtimeconfig*' \) 2>/dev/null | head -10

echo "== [E] HTTP2 endpoints probe"
for p in 16634 16636 44169; do
  for scheme in http https; do
    C=$(curl -sS -m 4 --http2-prior-knowledge -k -o /tmp/h.out -w "%{http_code}" "$scheme://127.0.0.1:$p/" 2>/dev/null || echo ERR)
    echo "port $p ($scheme h2c): $C :: $(head -c 80 /tmp/h.out 2>/dev/null | tr '\n' ' ')"
  done
done

echo "== [F] unifiedContainerInformation + unifiedPostCreateOutput"
json_keys /workspaces/.codespaces/.persistedshare/unifiedContainerInformation.json 2>/dev/null
echo "== RECON3 DONE"
} > "$OUT" 2>&1

cd /workspaces/container-escape-lab || exit 0
git config user.email "recon@codespace.local"; git config user.name "recon"
git checkout -b codespace-recon3 2>/dev/null || git checkout codespace-recon3
git add -f codespace-recon3.txt
git commit -m "recon3: secrets layout + cs-agent" || true
git push origin codespace-recon3 -f 2>&1 | tail -2
