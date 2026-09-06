#!/usr/bin/env bash
set +e
OUT=/workspaces/container-escape-lab/mount-variant-matrix.txt
{
echo "MOUNT VARIANT MATRIX $(date -u +%FT%TZ)"
echo "== probe each injected mount (existence only)"
for m in /vm-log /vm-etc /vm-docker /vm-home /vm-mnt; do
  if [ -d "$m" ]; then
    echo "$m -> MOUNTED (filter BYPASSED)"
    echo "  sample entries: $(ls "$m" 2>/dev/null | head -5 | tr '\n' ' ')"
  else
    echo "$m -> not mounted (filtered)"
  fi
done
echo "== docker.sock:"
ls -la /var/run/docker.sock 2>/dev/null || echo "  not mounted"
echo "== sanity: this is still the codespace container:"
hostname
echo "MATRIX DONE $(date -u +%FT%TZ)"
} > "$OUT" 2>&1
exit 0
