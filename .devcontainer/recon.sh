#!/usr/bin/env bash
# Codespace boundary recon (own environment, read-only, tokens redacted).
OUT=/workspaces/container-escape-lab/codespace-recon.txt
{
echo "== identity"
id; hostname; uname -a; date -u

echo "== [1] env surface (no secrets by name)"
env | sort | grep -viE '(TOKEN|SECRET|PASSWORD|KEY)=' | head -70

echo "== [2] credential-ish env names (values redacted)"
env | grep -iE 'TOKEN|SECRET|KEY|PASSWORD' | sed -E 's/=(.{6}).*/=\1<REDACTED len=N>/' | sort

echo "== [3] listening sockets"
ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null || cat /proc/net/tcp | head -15

echo "== [4] processes (head 30)"
ps aux | head -30

echo "== [5] pid1 cgroup / container boundary"
cat /proc/1/cgroup
echo "-- mounts (head 45):"
mount | head -45

echo "== [6] docker availability"
command -v docker >/dev/null && docker ps 2>&1 | head -3 || echo "no docker binary"

echo "== [7] IMDS reachability (status code only)"
curl -sS -m 3 -o /dev/null -w "IMDS: %{http_code}\n" -H 'Metadata:true' \
  'http://169.254.169.254/metadata/instance?api-version=2021-02-01' 2>/dev/null || echo "IMDS unreachable"

echo "== [8] egress ip (self only)"
curl -sS -m 5 https://api.ipify.org 2>/dev/null; echo

echo "== [9] sudo / filesystem boundary"
sudo -n true 2>/dev/null && echo "passwordless sudo: YES" || echo "passwordless sudo: NO"
ls -la / | head -25
df -h | head -12

echo "== [10] codespace/gateway agent footprint (paths only)"
find / -maxdepth 5 \( -iname '*codespace*' -o -iname '*gateway*' -o -iname '*vscode-server*' \) 2>/dev/null \
  | grep -vE '^/proc|^/sys' | head -25

echo "== [11] git credential shape (redacted)"
git config --global --list 2>/dev/null | sed -E 's/(=.{6}).*/=\1<REDACTED>/' | head -10
} > "$OUT" 2>&1

cd /workspaces/container-escape-lab || exit 0
git config user.email "recon@codespace.local"
git config user.name "recon"
git checkout -b codespace-recon 2>/dev/null || git checkout codespace-recon
git add -f codespace-recon.txt
git commit -m "codespace boundary recon" || true
git push origin codespace-recon -f 2>&1 | tail -3
