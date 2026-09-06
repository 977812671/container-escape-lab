#!/usr/bin/env bash
set -u
mkdir -p reports
{
  echo "## host kernel"; uname -a
  echo "## host caps"; capsh --print 2>/dev/null | sed -n '1,6p'
  echo "## docker server"; docker version --format 'server={{.Server.Version}} api={{.Server.APIVersion}}' 2>/dev/null
  echo "## default-container caps baseline"; docker run --rm alpine:3.19 sh -c 'grep -E "Cap(Eff|Bnd)|Seccomp" /proc/self/status'
  echo "## host disk layout"; lsblk 2>/dev/null | head -10
} > reports/host-baseline.txt 2>&1
cat reports/host-baseline.txt
