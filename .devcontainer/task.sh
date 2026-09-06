#!/usr/bin/env bash
set +e
OUT=/workspaces/container-escape-lab/mount-escape-proof.txt
{
echo "MOUNT-ESCAPE PROBE $(date -u +%FT%TZ)"
echo "== [1] VM root visible via /host-root?"
ls /host-root 2>/dev/null | head -20 || echo "/host-root NOT mounted"
echo "-- key paths in VM root (existence only):"
for p in host-root/.codespaces host-root/.codespaces/agent host-root/root host-root/etc/ssh host-root/var/lib/docker; do
  sudo ls -d /$p 2>/dev/null && echo "  ^^ EXISTS (VM fs reachable)" || echo "  /$p missing"
done
echo "== [2] /vm-root-home (VM /root)?"
ls /vm-root-home 2>/dev/null | head -15 || echo "/vm-root-home NOT mounted"
sudo ls -la /vm-root-home/.codespaces 2>/dev/null | head -10 || echo "  .codespaces not visible"
echo "== [3] docker.sock mounted?"
ls -la /var/run/docker.sock 2>/dev/null || echo "docker.sock NOT mounted"
command -v docker >/dev/null && sudo docker -H unix:///var/run/docker.sock ps 2>&1 | head -5 || echo "(no docker cli)"
echo "== [4] agent appsettings reachable via host-root? (existence only, values NOT read)"
sudo ls -la /host-root/.codespaces/agent/mount/appsettings.json 2>/dev/null && echo "  ^^ AGENT CONFIG REACHABLE" || echo "  not at expected path"
echo "PROBE DONE $(date -u +%FT%TZ)"
} > "$OUT" 2>&1
exit 0
