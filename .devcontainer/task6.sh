#!/usr/bin/env bash
set +e
OUT=/workspaces/container-escape-lab/codespace-recon6.txt
{
echo "RECON6 START $(date -u +%FT%TZ)"
echo "== [1] agent HTTP API path enumeration (all localhost ports x paths)"
PATHS="/ api/v1/agenttelemetry api/v1/agenttelemetry api/v1/environment api/v1/status healthz health ping version api/v1/connection api/v1/portforward api/v1/session"
for p in 16634 16635 16636 12563 13005 44169 46427; do
  for path in $PATHS; do
    C=$(curl -sS -m 3 -o /tmp/e.out -w "%{http_code}" "http://127.0.0.1:$p/$path" 2>/dev/null)
    if [ "$C" != "404" ] && [ "$C" != "000" ]; then
      echo "port $p /$path -> $C :: $(head -c 150 /tmp/e.out | tr '\n' ' ')"
    fi
  done
done
echo "(non-404 responses above; 404s suppressed)"

echo "== [2] cs-agent.sock gRPC probe (correct unix syntax)"
SOCK=/workspaces/.codespaces/shared/cs-agent.sock
ls -la $SOCK
which grpcurl >/dev/null && timeout 8 grpcurl -plaintext -unix $SOCK list 2>&1 | head -8
echo "-- h2c manual probe over unix sock:"
timeout 5 curl -sS --unix-socket $SOCK --http2-prior-knowledge -o /tmp/u.out -w "%{http_code}\n" http://localhost/ 2>&1 | head -2

echo "== [3] strings from agent binary (endpoints/routes)"
for f in /.codespaces/bin/codespaces /.codespaces/bin/Microsoft.VisualStudio.VSOnline.Core.dll; do
  if [ -f "$f" ]; then
    echo "-- $f:"
    strings -n 8 "$f" 2>/dev/null | grep -E '^api/v1|^/api/|localhost:|https://[a-z]' | sort -u | head -25
  fi
done

echo "== [4] port 46427/12563/13005/44169 banner grab"
for p in 46427 12563 13005 44169; do
  timeout 4 bash -c "exec 3<>/dev/tcp/127.0.0.1/$p; timeout 2 head -c 100 <&3" 2>&1 | head -3
  echo "^^^ port $p banner"
done

echo "== [5] process names on VM (via /proc readable?)"
ls /proc/ | grep -E '^[0-9]+$' | head -5
for pid in $(ls /proc/ | grep -E '^[0-9]+$' | head 2>/dev/null); do
  N=$(cat /proc/$pid/comm 2>/dev/null)
  echo "pid $pid: $N"
done | head -10
echo "RECON6 DONE $(date -u +%FT%TZ)"
} > "$OUT" 2>&1
exit 0
