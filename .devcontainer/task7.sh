#!/usr/bin/env bash
set +e
OUT=/workspaces/container-escape-lab/codespace-recon7.txt
{
echo "RECON7 START $(date -u +%FT%TZ)"
echo "== [1] UTF-16 strings from agent main dll (endpoints/routes)"
strings -e l -n 10 /.codespaces/bin/codespaces.dll 2>/dev/null | grep -E 'https?://|api/v|/twirp|Service/|localhost|127\.0\.0\.1|\.sock' | sort -u | head -40
echo "-- VSOnline.Core.dll:"
strings -e l -n 10 /.codespaces/bin/Microsoft.VisualStudio.VSOnline.Core.dll 2>/dev/null | grep -E 'https?://|api/v|/twirp|Service/' | sort -u | head -25
echo "-- CloudEnvironments Telemetry dll:"
strings -e l -n 10 /.codespaces/bin/Microsoft.CloudEnvironments.Telemetry.Contracts.dll 2>/dev/null | grep -E 'Service|api/v|/twirp' | sort -u | head -20

echo "== [2] installSSH.sh / installCWTools.sh (agent-VM interaction)"
cat /.codespaces/bin/Ssh/installSSH.sh 2>/dev/null | head -50
echo "----"
cat /.codespaces/bin/Utilities/installCWTools.sh 2>/dev/null | head -30

echo "== [3] full mountinfo (host bind leaks)"
cat /proc/self/mountinfo | grep -vE 'proc|sysfs|cgroup|devpts|mqueue|tmpfs /dev' | head -30

echo "== [4] appsettings.json FULL (comments stripped)"
python3 - <<'PYEOF'
import re, json
raw = open('/.codespaces/bin/appsettings.json', errors='replace').read()
cleaned = re.sub(r'^\s*//.*$', '', raw, flags=re.M)
cleaned = re.sub(r'/\*.*?\*/', '', cleaned, flags=re.S)
try:
    d = json.loads(cleaned)
    def walk(o, pre=''):
        if isinstance(o, dict):
            for k, v in o.items():
                if isinstance(v, (dict, list)):
                    walk(v, pre + k + '.')
                else:
                    s = str(v)
                    print(pre + k + ' = ' + s[:180])
        elif isinstance(o, list):
            for i, v in enumerate(o):
                walk(v, pre + '[' + str(i) + '].')
    walk(d)
except Exception as e:
    print('json err:', e)
PYEOF

echo "== [5] 46427 redirect follow"
curl -sSL -m 5 -o /tmp/red.out -w "final: %{url_effective} -> %{http_code}\n" http://127.0.0.1:46427/ 2>&1 | head -2
head -c 200 /tmp/red.out 2>/dev/null | tr '\n' ' '; echo

echo "== [6] Ssh dir + UnifiedContainers/Package"
ls -la /.codespaces/bin/Ssh/ 2>/dev/null
ls -la /.codespaces/bin/UnifiedContainers/ 2>/dev/null
ls -la /.codespaces/bin/UnifiedContainers/Package 2>/dev/null | head -10
echo "RECON7 DONE $(date -u +%FT%TZ)"
} > "$OUT" 2>&1
exit 0
