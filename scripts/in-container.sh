#!/bin/sh
# Container escape probe runner (alpine, POSIX sh). Detection-oriented: no destructive ops.
V="$1"
OUT="/lab/reports/container-${V}.txt"
{
  echo "### escape-probe variant=$V time=$(date -u '+%FT%TZ')"
  echo "## identity"; id
  echo "## hostname"; hostname
  echo "## caps/seccomp/nnp"; grep -E 'Cap(Inh|Prm|Eff|Bnd|Amb)|Seccomp|NoNewPrivs' /proc/self/status
  echo "## apparmor label"; cat /proc/self/attr/current 2>/dev/null || echo none
  echo "## cgroup"; cat /proc/self/cgroup
  echo "## mounts (head 50)"; mount 2>/dev/null | head -50
  echo "## host root visible?"; ls /host 2>/dev/null | head -20 || echo "NO /host mount"
  echo "## docker.sock?"; ls -la /var/run/docker.sock 2>/dev/null || echo "NO sock"
  echo "## kernel"; uname -a

  echo "## tools install"
  apk add --no-cache bash curl >/dev/null 2>&1 || echo "apk add failed"

  echo "## CDK evaluate"
  CDK_OK=0
  if curl -fsSL -o /tmp/cdk "https://github.com/cdk-team/CDK/releases/latest/download/cdk_linux_amd64"; then
    CDK_OK=1
  else
    CDM_URL=$(curl -fsSL https://api.github.com/repos/cdk-team/CDK/releases/latest 2>/dev/null | grep -o '"browser_download_url": *"[^"]*linux_amd64[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$CDM_URL" ] && curl -fsSL -o /tmp/cdk "$CDM_URL"; then CDK_OK=1; fi
  fi
  if [ "$CDK_OK" = "1" ]; then
    chmod +x /tmp/cdk
    /tmp/cdk evaluate 2>&1 | sed -n '1,220p'
  else
    echo "cdk download failed"
  fi

  echo "## deepce"
  if curl -fsSL -o /tmp/deepce "https://raw.githubusercontent.com/stealthcopter/deepce/main/deepce.sh"; then
    bash /tmp/deepce 2>&1 | sed -n '1,180p'
  else
    echo "deepce download failed"
  fi

  echo "## docker.sock non-destructive check"
  if [ -S /var/run/docker.sock ]; then
    apk add --no-cache docker-cli >/dev/null 2>&1 || true
    docker version 2>&1 | sed -n '1,8p' || true
    echo "=> sock-attached container: docker-out-of-docker escape path (start privileged sibling) is available"
  else
    echo "no sock in this variant"
  fi
} > "$OUT" 2>&1
echo "written $OUT"
sed -n '1,10p' "$OUT"
