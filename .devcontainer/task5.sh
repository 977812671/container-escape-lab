#!/usr/bin/env bash
set +e
OUT=/workspaces/container-escape-lab/codespace-recon5.txt
{
echo "RECON5 START $(date -u +%FT%TZ)"
echo "== [1] full VM port table (host network => VM netns)"
ss -tlnp 2>/dev/null

echo "== [2] docker daemon ports probe"
for p in 2375 2376; do
  C=$(curl -sS -m 3 -o /tmp/d.out -w "%{http_code}" "http://127.0.0.1:$p/version" 2>/dev/null)
  echo "docker :$p/version -> $C :: $(head -c 100 /tmp/d.out | tr '\n' ' ')"
done

echo "== [3] strip comments from appsettings (full config)"
python3 - <<'PYEOF'
import re, json
for f in ['/.codespaces/bin/appsettings.json', '/.codespaces/bin/appsettings.standalone.json']:
    print('=====', f)
    try:
        raw = open(f, errors='replace').read()
        # strip // comments (naive but fine for this file)
        cleaned = re.sub(r'^\s*//.*$', '', raw, flags=re.M)
        cleaned = re.sub(r'/\*.*?\*/', '', cleaned, flags=re.S)
        d = json.loads(cleaned)
        def walk(o, pre=''):
            if isinstance(o, dict):
                for k, v in o.items():
                    if isinstance(v, (dict, list)):
                        walk(v, pre + k + '.')
                    else:
                        s = str(v)
                        lk = k.lower()
                        if any(x in lk for x in ('token', 'secret', 'password', 'accountkey', 'connectionstring')):
                            print(pre + k + ' = <REDACTED len=' + str(len(s)) + '>')
                        else:
                            print(pre + k + ' = ' + s[:150])
            elif isinstance(o, list):
                for i, v in enumerate(o[:6]):
                    walk(v, pre + '[' + str(i) + '].')
        walk(d)
    except Exception as e:
        print('err:', e, '| head:', raw[:100])
PYEOF

echo "== [4] grpcurl reflection enumeration"
which grpcurl >/dev/null 2>&1 || {
  curl -sSL -m 60 -o /tmp/grpcurl.tgz https://github.com/fullstorydev/grpcurl/releases/download/v1.9.1/grpcurl_1.9.1_linux_x86_64.tar.gz 2>/dev/null
  tar xzf /tmp/grpcurl.tgz -C /tmp grpcurl 2>/dev/null && chmod +x /tmp/grpcurl && mv /tmp/grpcurl /usr/local/bin/ 2>/dev/null || sudo mv /tmp/grpcurl /usr/local/bin/ 2>/dev/null
}
for p in 16634 16636; do
  echo "-- 127.0.0.1:$p list:"
  timeout 10 grpcurl -plaintext 127.0.0.1:$p list 2>&1 | head -15
done
echo "-- cs-agent.sock (unix) list:"
timeout 10 grpcurl -plaintext -unix $SH/cs-agent.sock list 2>&1 | head -10

echo "== [5] port 2000 raw probe"
timeout 4 bash -c 'exec 3<>/dev/tcp/127.0.0.1/2000; printf "GET / HTTP/1.0\r\n\r\n" >&3; timeout 3 cat <&3 | head -c 200' 2>&1 | head -6
echo "RECON5 DONE $(date -u +%FT%TZ)"
} > "$OUT" 2>&1
exit 0
